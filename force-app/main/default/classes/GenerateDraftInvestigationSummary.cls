/**
 * Agent action: builds the grounding text for a Complaint (all fields, linked
 * Product History Reviews and checklist items, CQ Tasks, and associated items),
 * runs the "Complaint Draft Investigation Summary" prompt template, and returns
 * the PHR Summary. Optionally saves it (see SaveDraftInvestigationSummary).
 *
 * The prompt wording lives in Prompt Builder, so it can be edited there without
 * changing this class.
 */
public with sharing class GenerateDraftInvestigationSummary {

    @TestVisible static final String TEMPLATE_NAME = 'Complaint_Draft_Investigation_Summary';
    @TestVisible static String mockResponse;

    public class Request {
        @InvocableVariable(required=true label='Complaint Record Id'
            description='Record Id of the Complaint to summarize. A Product History Review, CQ Task or Investigation Id also works: its complaint is used.')
        public Id complaintId;

        @InvocableVariable(label='Save to Complaint'
            description='When true, the summary is also saved to the PHR Summary on the Complaint and the Summary on its Product History Review.')
        public Boolean saveToRecord;
    }

    public class Result {
        @InvocableVariable(label='PHR Summary')
        public String summary;

        @InvocableVariable(label='Saved')
        public Boolean saved;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Generate PHR Summary'
        description='Reads every field on a Complaint and its linked Product History Reviews and checklist items, and generates the PHR Summary. Works from the Complaint or its Product History Review. Can optionally save it.')
    public static List<Result> generate(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<SaveDraftInvestigationSummary.Request> toSave = new List<SaveDraftInvestigationSummary.Request>();
        Map<Integer, Integer> saveIndex = new Map<Integer, Integer>();

        for (Request req : requests) {
            Result r = new Result();
            r.saved = false;
            try {
                // The agent may be opened on the complaint, its Product History Review, a CQ Task or the investigation.
                Id complaintId = PhrRecordContext.complaintIdFor(req.complaintId);
                if (complaintId == null) {
                    r.message = 'I could not find the complaint for this record. Open the agent from a complaint or its Product History Review.';
                    results.add(r);
                    continue;
                }
                String data = ComplaintInvestigationGrounding.buildGroundingText(complaintId)
                    + '\n\n' + ComplaintLeadRanking.buildText(complaintId);
                PhrReportSettings.Values settings = PhrReportSettings.get();
                if (!PhrSummarySections.anySectionOn(settings)) {
                    r.message = 'No summary sections are turned on in the PHR Report Setting, so no summary was generated.';
                    results.add(r);
                    continue;
                }
                r.summary = PhrSummaryText.stripDisclaimer(PhrSummarySections.apply(runTemplate(data), settings));
                r.message = 'PHR Summary generated.';
                if (req.saveToRecord == true) {
                    SaveDraftInvestigationSummary.Request s = new SaveDraftInvestigationSummary.Request();
                    s.complaintId = req.complaintId; // Save resolves it the same way and also knows which PHR was open
                    s.summary = r.summary;
                    saveIndex.put(results.size(), toSave.size());
                    toSave.add(s);
                }
            } catch (Exception e) {
                r.message = 'The summary could not be generated: ' + e.getMessage();
            }
            results.add(r);
        }

        // DML runs after all prompt calls, since a callout can't follow uncommitted work.
        if (!toSave.isEmpty()) {
            List<SaveDraftInvestigationSummary.Result> saveResults = SaveDraftInvestigationSummary.save(toSave);
            for (Integer i : saveIndex.keySet()) {
                SaveDraftInvestigationSummary.Result sr = saveResults[saveIndex.get(i)];
                results[i].saved = sr.success;
                results[i].message = sr.message;
            }
        }
        return results;
    }

    @TestVisible
    static String runTemplate(String complaintData) {
        if (Test.isRunningTest()) {
            return mockResponse == null ? 'TEST SUMMARY' : mockResponse;
        }
        ConnectApi.WrappedValue dataValue = new ConnectApi.WrappedValue();
        dataValue.value = complaintData;

        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ 'Input:Complaint_Data' => dataValue };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptBuilderPreview';

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(TEMPLATE_NAME, input);
        if (output.generations == null || output.generations.isEmpty()) {
            throw new GenerationException('The prompt template returned no text.');
        }
        return output.generations[0].text.trim();
    }

    public class GenerationException extends Exception {}
}

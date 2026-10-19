/**
 * Agent action: builds the grounding text for a Complaint (all fields, linked
 * Product History Reviews and checklist items, CQ Tasks, and associated items),
 * runs the "Complaint Draft Investigation Summary" prompt template, and returns
 * the draft. Optionally saves the draft to the Complaint's Draft Investigation
 * Summary field.
 *
 * The prompt wording lives in Prompt Builder, so it can be edited there without
 * changing this class.
 */
public with sharing class GenerateDraftInvestigationSummary {

    @TestVisible static final String TEMPLATE_NAME = 'Complaint_Draft_Investigation_Summary';
    @TestVisible static String mockResponse;

    public class Request {
        @InvocableVariable(required=true label='Complaint Record Id'
            description='Salesforce record Id of the Complaint to summarize.')
        public Id complaintId;

        @InvocableVariable(label='Save to Complaint'
            description='When true, the draft is also saved to the Draft Investigation Summary field on the Complaint.')
        public Boolean saveToRecord;
    }

    public class Result {
        @InvocableVariable(label='Draft Investigation Summary')
        public String summary;

        @InvocableVariable(label='Saved')
        public Boolean saved;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Generate Draft Investigation Summary'
        description='Reads every field on a Complaint and its linked Product History Reviews and checklist items, and generates a draft investigation summary. Can optionally save it to the Complaint.')
    public static List<Result> generate(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<SaveDraftInvestigationSummary.Request> toSave = new List<SaveDraftInvestigationSummary.Request>();
        Map<Integer, Integer> saveIndex = new Map<Integer, Integer>();

        for (Request req : requests) {
            Result r = new Result();
            r.saved = false;
            try {
                String data = ComplaintInvestigationGrounding.buildGroundingText(req.complaintId)
                    + '\n\n' + ComplaintLeadRanking.buildText(req.complaintId);
                PhrReportSettings.Values settings = PhrReportSettings.get();
                if (!PhrSummarySections.anySectionOn(settings)) {
                    r.message = 'No summary sections are turned on in the PHR Report Setting, so no summary was generated.';
                    results.add(r);
                    continue;
                }
                r.summary = PhrSummarySections.apply(runTemplate(data), settings);
                r.message = 'Draft generated.';
                if (req.saveToRecord == true) {
                    SaveDraftInvestigationSummary.Request s = new SaveDraftInvestigationSummary.Request();
                    s.complaintId = req.complaintId;
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

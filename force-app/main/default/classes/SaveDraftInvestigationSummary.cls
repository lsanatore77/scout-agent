/**
 * Agent action: saves generated summary text to the Draft Investigation Summaries
 * rich text field on a ComplianceQuest Complaint. Markdown or HTML from Agentforce
 * is converted and sanitized by SummaryRichText so bold text, bullet and numbered
 * lists, headings and links display in the field. Runs in USER_MODE so the running
 * user's edit access and field-level security are enforced.
 */
public with sharing class SaveDraftInvestigationSummary {

    static final String COMPLAINT_OBJ = 'compliancequest__SQX_Complaint__c';

    static final String SUMMARY_FIELD = 'Draft_Investigation_Summaries__c';

    public class Request {
        @InvocableVariable(required=true label='Complaint Record Id'
            description='Salesforce record Id of the Complaint to update.')
        public Id complaintId;

        @InvocableVariable(required=true label='Summary'
            description='Full text of the draft investigation summary to save. Markdown (bold, bullets, numbered lists, headings) or simple HTML is kept as formatting.')
        public String summary;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Save Draft Investigation Summary'
        description='Saves the draft investigation summary text to the Draft Investigation Summaries rich text field on the Complaint record, keeping bold text, bullet points and other formatting.')
    public static List<Result> save(List<Request> requests) {
        List<SObject> updates = new List<SObject>();
        for (Request req : requests) {
            SObject complaint = Schema.getGlobalDescribe()
                .get(COMPLAINT_OBJ).newSObject(req.complaintId);
            complaint.put(SUMMARY_FIELD, SummaryRichText.fromAgent(SummaryHtmlRepair.repair(req.summary)));
            updates.add(complaint);
        }

        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        List<Result> results = new List<Result>();
        for (Database.SaveResult sr : saveResults) {
            Result r = new Result();
            r.success = sr.isSuccess();
            if (sr.isSuccess()) {
                r.message = 'Draft investigation summary saved to the complaint.';
            } else {
                List<String> errors = new List<String>();
                for (Database.Error e : sr.getErrors()) {
                    errors.add(e.getMessage());
                }
                r.message = 'The summary was not saved: ' + String.join(errors, '; ');
            }
            results.add(r);
        }
        return results;
    }
}

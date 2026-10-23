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
        List<String> htmls = new List<String>();
        for (Request req : requests) {
            SObject complaint = Schema.getGlobalDescribe()
                .get(COMPLAINT_OBJ).newSObject(req.complaintId);
            String html = SummaryRichText.boldRecordIds(SummaryRichText.boldHeadings(SummaryRichText.fromAgent(SummaryHtmlRepair.repair(req.summary))));
            // Ends the summary with a link to the Product History Review Report PDF, when the complaint has one.
            html = PhrReportLink.withReportLink(req.complaintId, html);
            complaint.put(SUMMARY_FIELD, html);
            updates.add(complaint);
            htmls.add(html);
        }

        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < saveResults.size(); i++) {
            Database.SaveResult sr = saveResults[i];
            Result r = new Result();
            r.success = sr.isSuccess();
            if (sr.isSuccess()) {
                r.message = 'Draft investigation summary saved to the complaint.' + updateInvestigations(requests[i].complaintId, htmls[i])
                    + PhrReportLink.shareWithInvestigations(requests[i].complaintId);
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

    /**
     * Copies the saved summary to the Investigation Summary field of the complaint's primary investigation only.
     * Other linked investigations are left alone. The complaint is already saved, so a problem here never
     * undoes it: the problem is reported in the message instead.
     */
    @TestVisible
    private static String updateInvestigations(Id complaintId, String html) {
        try {
            Set<Id> invIds = PhrReportLink.investigationIds(complaintId);
            if (invIds.isEmpty()) { return ' No primary investigation is set on this complaint, so only the complaint was updated.'; }

            List<compliancequest__SQX_Investigation__c> invs = new List<compliancequest__SQX_Investigation__c>();
            for (Id invId : invIds) {
                invs.add(new compliancequest__SQX_Investigation__c(Id = invId, compliancequest__Investigation_Summary__c = html));
            }
            List<Database.SaveResult> rs = Database.update(invs, false, AccessLevel.USER_MODE);
            List<String> problems = new List<String>();
            for (Database.SaveResult r : rs) {
                if (!r.isSuccess()) { for (Database.Error e : r.getErrors()) { problems.add(e.getMessage()); } }
            }
            if (!problems.isEmpty()) {
                return ' The complaint was saved, but the primary investigation could not be updated: ' + String.join(problems, '; ');
            }
            return ' The investigation summary was also updated on 1 investigation (the primary investigation).';
        } catch (Exception ex) {
            return ' The complaint was saved, but the investigation summary could not be updated: ' + ex.getMessage();
        }
    }
}

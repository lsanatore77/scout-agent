/**
 * Agent action: saves the PHR Summary.
 *
 * The summary is saved to:
 *  1. the complaint (field Draft_Investigation_Summaries__c, labelled "PHR Summary"),
 *  2. the Summary field of the Product History Review (the PHR the agent was opened on,
 *     otherwise the complaint's most recent PHR),
 *  3. the Investigation Summary of the complaint's primary investigation, as a starting point.
 *
 * Markdown or HTML from Agentforce is converted and sanitized by SummaryRichText so bold text,
 * lists, headings and links display in the rich text fields. The "AI-generated draft" line is removed.
 * Runs in USER_MODE so the running user's edit access and field-level security are enforced.
 * The complaint is saved first; a problem with the PHR or the investigation never undoes it and is
 * reported in the message instead.
 *
 * The class keeps its original API name so existing agent scripts keep working.
 */
public with sharing class SaveDraftInvestigationSummary {

    static final String COMPLAINT_OBJ = 'compliancequest__SQX_Complaint__c';
    static final String SUMMARY_FIELD = 'Draft_Investigation_Summaries__c';

    public class Request {
        @InvocableVariable(required=true label='Record Id'
            description='Record Id of the Complaint or its Product History Review. A CQ Task or Investigation Id also works: its complaint is used.')
        public Id complaintId;

        @InvocableVariable(required=true label='Summary'
            description='Full text of the PHR Summary to save. Markdown (bold, bullets, numbered lists, headings) or simple HTML is kept as formatting.')
        public String summary;
    }

    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Save PHR Summary'
        description='Saves the PHR Summary to the Complaint, to the Summary field of its Product History Review, and copies it to the primary investigation as a starting point. Keeps bold text, bullet points and other formatting.')
    public static List<Result> save(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<SObject> updates = new List<SObject>();
        List<Integer> updateIndex = new List<Integer>();
        List<Id> complaintIds = new List<Id>();
        List<Id> phrIds = new List<Id>();
        List<String> htmls = new List<String>();

        for (Integer i = 0; i < requests.size(); i++) {
            Request req = requests[i];
            Result r = new Result();
            r.success = false;
            results.add(r);
            Id complaintId = PhrRecordContext.complaintIdFor(req.complaintId);
            complaintIds.add(complaintId);
            phrIds.add(null);
            htmls.add(null);
            if (complaintId == null) {
                r.message = 'The summary was not saved: I could not find the complaint for this record.';
                continue;
            }
            if (String.isBlank(PhrSummaryText.stripDisclaimer(req.summary))) {
                r.message = 'The summary was not saved: there was no summary text.';
                continue;
            }
            String html = SummaryRichText.boldRecordIds(SummaryRichText.boldHeadings(SummaryRichText.fromAgent(
                SummaryHtmlRepair.repair(PhrSummaryText.stripDisclaimer(req.summary)))));
            html = PhrSummaryText.stripDisclaimer(html);
            // Ends the summary with a link to the Product History Review Report PDF, when the complaint has one.
            html = PhrReportLink.withReportLink(complaintId, html);
            htmls[i] = html;
            try { phrIds[i] = PhrRecordContext.phrIdFor(req.complaintId); } catch (Exception e) { phrIds[i] = null; }

            SObject complaint = Schema.getGlobalDescribe().get(COMPLAINT_OBJ).newSObject(complaintId);
            complaint.put(SUMMARY_FIELD, html);
            updates.add(complaint);
            updateIndex.add(i);
        }

        if (updates.isEmpty()) { return results; }
        List<Database.SaveResult> saveResults = Database.update(updates, false, AccessLevel.USER_MODE);
        for (Integer k = 0; k < saveResults.size(); k++) {
            Integer i = updateIndex[k];
            Database.SaveResult sr = saveResults[k];
            Result r = results[i];
            r.success = sr.isSuccess();
            if (sr.isSuccess()) {
                r.message = 'PHR Summary saved to the complaint.'
                    + updatePhr(phrIds[i], htmls[i])
                    + updateInvestigations(complaintIds[i], htmls[i])
                    + PhrReportLink.shareWithInvestigations(complaintIds[i]);
            } else {
                List<String> errors = new List<String>();
                for (Database.Error e : sr.getErrors()) {
                    errors.add(e.getMessage());
                }
                r.message = 'The summary was not saved: ' + String.join(errors, '; ');
            }
        }
        return results;
    }

    /** Saves the summary to the Summary field of the Product History Review. */
    @TestVisible
    private static String updatePhr(Id phrId, String html) {
        if (phrId == null) { return ' This complaint has no Product History Review yet, so only the complaint was updated.'; }
        try {
            Database.SaveResult r = Database.update(new compliancequest__SQX_Product_History_Review__c(
                Id = phrId, compliancequest__Product_History_Review_Summary__c = html), false, AccessLevel.USER_MODE);
            if (r.isSuccess()) {
                return ' It was also saved to the Summary on the Product History Review' + phrName(phrId) + '.';
            }
            List<String> problems = new List<String>();
            for (Database.Error e : r.getErrors()) { problems.add(e.getMessage()); }
            return ' The Product History Review summary could not be updated: ' + String.join(problems, '; ');
        } catch (Exception ex) {
            return ' The Product History Review summary could not be updated: ' + ex.getMessage();
        }
    }

    static String phrName(Id phrId) {
        for (compliancequest__SQX_Product_History_Review__c p : [
            SELECT Name FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :phrId WITH USER_MODE LIMIT 1
        ]) {
            return ' (' + p.Name + ')';
        }
        return '';
    }

    /**
     * Copies the saved summary to the Investigation Summary field of the complaint's primary investigation only,
     * as a starting point. Other linked investigations are left alone.
     */
    @TestVisible
    private static String updateInvestigations(Id complaintId, String html) {
        try {
            Set<Id> invIds = PhrReportLink.investigationIds(complaintId);
            if (invIds.isEmpty()) { return ' No primary investigation is set on this complaint, so nothing was copied to an investigation.'; }

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
                return ' The primary investigation could not be updated: ' + String.join(problems, '; ');
            }
            return ' It was also copied to the Investigation Summary on the primary investigation as a starting point.';
        } catch (Exception ex) {
            return ' The investigation summary could not be updated: ' + ex.getMessage();
        }
    }
}

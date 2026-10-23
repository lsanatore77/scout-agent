/**
 * Used by the triageStepsWithSummary component that opens from the complaint triage button in eNBA.
 * When the user ticks "Include draft summary", this copies the complaint's saved Draft Investigation
 * Summary to the Investigation Summary field of its linked investigations, using the same save
 * logic as the agent (SaveDraftInvestigationSummary). Runs in USER_MODE through that class.
 */
public with sharing class TriageDraftSummaryController {

    public class Outcome {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Boolean hasDraft;
        @AuraEnabled public String message;
    }

    /** True when the complaint already has a draft summary to include. recordId may be a complaint or a CQ Task on it. */
    @AuraEnabled
    public static Boolean hasDraft(String recordId) {
        Id complaintId = resolveComplaintId(recordId);
        return complaintId != null && !String.isBlank(draftFor(complaintId));
    }

    /** Saves the existing draft summary to the complaint and its linked investigations. */
    @AuraEnabled
    public static Outcome includeDraftSummary(String recordId) {
        Outcome o = new Outcome();
        Id complaintId = resolveComplaintId(recordId);
        if (complaintId == null) {
            o.success = false;
            o.hasDraft = false;
            o.message = 'The complaint for this task could not be found.';
            return o;
        }
        String draft = draftFor(complaintId);
        if (String.isBlank(draft)) {
            o.success = true;
            o.hasDraft = false;
            o.message = 'There is no draft summary on this complaint yet, so nothing was included.';
            return o;
        }
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.summary = draft;
        SaveDraftInvestigationSummary.Result r =
            SaveDraftInvestigationSummary.save(new List<SaveDraftInvestigationSummary.Request>{ req })[0];
        o.success = r.success;
        o.hasDraft = true;
        o.message = r.message;
        return o;
    }

    /** Accepts a complaint Id or the Id of a CQ Task on a complaint and returns the complaint Id, or null. */
    public static Id resolveComplaintId(String recordId) {
        return PhrRecordContext.complaintIdFor(recordId);
    }

    private static String draftFor(Id complaintId) {
        for (compliancequest__SQX_Complaint__c c : [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c
            WHERE Id = :complaintId WITH USER_MODE LIMIT 1
        ]) {
            return c.Draft_Investigation_Summaries__c;
        }
        return null;
    }
}

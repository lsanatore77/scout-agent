/**
 * CqApprovals: Waiting for Your Approval on the Quality Management home (decided with Lou 25 Nov 2026).
 *
 * The open steps of CQ's approvals (cqext CQ Approval Step) assigned to the running user or delegated to them, from any
 * object: an NC's disposition approval, a field action committee seat, an audit. Approve and Reject sign first through
 * our e-signature standard (docs/esignature.md: CqEsign, CQ's own policy and password check) and then act on the step,
 * the same way the Field Action committee does. CQ closes the approval when its last step is approved, or when one is
 * rejected.
 *
 * Only objects with a signature log (SIGNABLE, below) can be signed from here; the others show Review,
 * which opens the record.
 */
public with sharing class CqApprovals {
    public static final Set<String> TITLE_FIELDS = new Set<String>{ 'compliancequest__NC_Title__c', 'compliancequest__Title__c', 'Title__c' };
    /**
     * The objects that keep a signature log (CqEsigBridge's SIGNABLE: keep the two in step). Named here rather than asked
     * of CqEsigBridge, which no class names directly, so nothing else depends on the CQ package's Apex (see CqEsign).
     */
    public static final Set<String> SIGNABLE = new Set<String>{ 'Field_Action_Review__c', 'Field_Action__c', 'compliancequest__SQX_Nonconformance__c' };
    public static Boolean isSignable(Id recordId) { return recordId != null && SIGNABLE.contains(String.valueOf(recordId.getSObjectType())); }

    public class Item {
        @AuraEnabled public Id stepId; @AuraEnabled public Id approvalId; @AuraEnabled public String approvalName;
        @AuraEnabled public Id recordId; @AuraEnabled public String recordName; @AuraEnabled public String recordTitle;
        @AuraEnabled public String objectName; @AuraEnabled public String objectLabel;
        @AuraEnabled public String what;              // what is being approved: CQ's Approval Type
        @AuraEnabled public String seat;              // the job function the step is for
        @AuraEnabled public String requestedBy; @AuraEnabled public Datetime requestedOn;
        @AuraEnabled public Boolean delegated = false;
        @AuraEnabled public Boolean canSign = false;
    }

    @AuraEnabled
    public static List<Item> mine() {
        Id me = UserInfo.getUserId();
        List<Item> out = new List<Item>();
        Map<String, Set<Id>> byObject = new Map<String, Set<Id>>();
        for (cqext__CQAPR_Approval_Step__c t : [
                SELECT Id, cqext__CQAPR_Assignee_User__c, cqext__CQAPR_Delegate_User__c, cqext__CQAPR_Job_Function__r.Name, CreatedDate,
                       cqext__CQAPR_Approval__c, cqext__CQAPR_Approval__r.Name, cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c,
                       cqext__CQAPR_Approval__r.cqext__Approval_Type__c, cqext__CQAPR_Approval__r.cqext__Approval_Record__c,
                       cqext__CQAPR_Approval__r.cqext__Submitted_By__r.Name, cqext__CQAPR_Approval__r.cqext__Submitted_Date__c,
                       cqext__CQAPR_Approval__r.CreatedBy.Name
                FROM cqext__CQAPR_Approval_Step__c
                WHERE cqext__Status__c = 'Open' AND (cqext__CQAPR_Assignee_User__c = :me OR cqext__CQAPR_Delegate_User__c = :me)
                ORDER BY CreatedDate ASC LIMIT 100]) {
            Item i = new Item();
            i.stepId = t.Id; i.approvalId = t.cqext__CQAPR_Approval__c; i.approvalName = t.cqext__CQAPR_Approval__r.Name;
            i.what = t.cqext__CQAPR_Approval__r.cqext__Approval_Type__c;
            i.seat = t.cqext__CQAPR_Job_Function__r?.Name;
            i.requestedBy = t.cqext__CQAPR_Approval__r.cqext__Submitted_By__r?.Name != null
                ? t.cqext__CQAPR_Approval__r.cqext__Submitted_By__r.Name : t.cqext__CQAPR_Approval__r.CreatedBy?.Name;
            i.requestedOn = t.cqext__CQAPR_Approval__r.cqext__Submitted_Date__c != null ? t.cqext__CQAPR_Approval__r.cqext__Submitted_Date__c : t.CreatedDate;
            i.delegated = t.cqext__CQAPR_Assignee_User__c != me;
            Id rec = toId(t.cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c);
            if (rec != null) {
                i.recordId = rec;
                String obj = String.valueOf(rec.getSObjectType());
                i.objectName = obj;
                i.objectLabel = rec.getSObjectType().getDescribe().getLabel();
                i.canSign = isSignable(rec);
                if (!byObject.containsKey(obj)) { byObject.put(obj, new Set<Id>()); }
                byObject.get(obj).add(rec);
            }
            if (String.isBlank(i.what)) { i.what = 'Approval'; }
            out.add(i);
        }
        // each record's name and title, one query per object
        Map<Id, SObject> recs = new Map<Id, SObject>();
        for (String obj : byObject.keySet()) {
            Map<String, Schema.SObjectField> fields = Schema.getGlobalDescribe().get(obj).getDescribe().fields.getMap();
            String title = null;
            for (String f : TITLE_FIELDS) { if (fields.containsKey(f.toLowerCase())) { title = f; break; } }
            Set<Id> ids = byObject.get(obj);
            String q = 'SELECT Id, Name' + (title == null ? '' : ', ' + title) + ' FROM ' + obj + ' WHERE Id IN :ids';
            for (SObject s : Database.query(q)) { recs.put(s.Id, s); }
            for (Item i : out) {
                if (i.objectName == obj && recs.containsKey(i.recordId)) {
                    SObject s = recs.get(i.recordId);
                    i.recordName = (String) s.get('Name');
                    if (title != null) { i.recordTitle = (String) s.get(title); }
                }
            }
        }
        for (Item i : out) { if (i.recordName == null) { i.recordName = i.approvalName; } }
        return out;
    }

    /**
     * Approve or reject one open step: the person it is assigned to or delegated to (or an administrator acting for
     * them). Signed first when CQ's policy asks (nothing changes if the signature is refused); a rejection needs a reason.
     */
    @AuraEnabled
    public static List<Item> act(Id stepId, String action, String comment, String password) {
        if (action != 'approve' && action != 'reject') { throw new AuraHandledException('Choose Approve or Reject.'); }
        if (action == 'reject' && String.isBlank(comment)) { throw new AuraHandledException('Say why you are rejecting it.'); }
        cqext__CQAPR_Approval_Step__c t = [
            SELECT Id, cqext__Status__c, cqext__CQAPR_Approval__c, cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c,
                   cqext__CQAPR_Assignee_User__c, cqext__CQAPR_Delegate_User__c
            FROM cqext__CQAPR_Approval_Step__c WHERE Id = :stepId];
        if (t.cqext__Status__c != 'Open') { throw new AuraHandledException('That approval is no longer open.'); }
        Boolean mine = t.cqext__CQAPR_Assignee_User__c == UserInfo.getUserId() || t.cqext__CQAPR_Delegate_User__c == UserInfo.getUserId();
        if (!mine && !CqTriageInbox.isAdmin()) { throw new AuraHandledException('This approval is assigned to someone else.'); }
        Id rec = toId(t.cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c);
        if (rec == null || !isSignable(rec)) { throw new AuraHandledException('Open the record to approve this one.'); }

        CqEsign.sign(rec, action, comment, password, mine);   // signed first when CQ's policy asks; nothing changes if refused

        update new cqext__CQAPR_Approval_Step__c(Id = stepId, cqext__Activity_Code__c = action, cqext__Remark__c = String.isBlank(comment) ? null : comment.left(1024));
        if (action == 'reject') {
            update new cqext__CQAPR_Approval__c(Id = t.cqext__CQAPR_Approval__c, cqext__Activity_Code__c = 'reject', cqext__Activity_Comment__c = comment.left(1024));
        } else if ([SELECT COUNT() FROM cqext__CQAPR_Approval_Step__c WHERE cqext__CQAPR_Approval__c = :t.cqext__CQAPR_Approval__c AND cqext__Status__c = 'Open'] == 0) {
            update new cqext__CQAPR_Approval__c(Id = t.cqext__CQAPR_Approval__c, cqext__Activity_Code__c = 'approve');
        }
        return mine();
    }

    public static Id toId(String s) {
        if (String.isBlank(s)) { return null; }
        try { return Id.valueOf(s); } catch (Exception e) { return null; }
    }
}

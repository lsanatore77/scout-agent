/**
 * CqFarEsigPolicies: registers Field Action Review and Field Action with CQ's electronic signature, the way CQ's own
 * add-on modules do (cqext CQDC_Esig_Policies and others). Every signable object of this app is added here (docs/esignature.md).
 *
 * To turn it on, an admin adds a row named CqFarEsigPolicies to the CQ Extension Esig Policy Provider custom
 * metadata (CQ Admin > Manage Extension Settings). CQ then offers Field Action Review in its Electronic Signature
 * Policies, with the actions in Field Action Review Record Activity's Activity Code (Committee Approve, Committee
 * Send Back), and writes each signature to that object. Field Action is offered the same way, with the actions in
 * Field Action Record Activity's Activity Code (Close Field Action).
 *
 * Global because CQ's managed code finds and creates it by name.
 */
global with sharing class CqFarEsigPolicies implements compliancequest.SQX_Ext_Object_Policy_Providers_Handler {
    public static final String APPROVE = 'approve';
    public static final String REJECT = 'reject';

    /** One provider per signable object: the object, its signature log, and the field whose values are the signable actions. */
    global List<compliancequest.SQX_Extension_Object_Policy_Provider> getAllESigPolicyProviders() {
        return new List<compliancequest.SQX_Extension_Object_Policy_Provider>{
            new compliancequest.SQX_Extension_Object_Policy_Provider(
                Field_Action_Review__c.SObjectType,
                Field_Action_Review_Record_Activity__c.SObjectType,
                Field_Action_Review_Record_Activity__c.Activity_Code__c,
                new Set<String>{ REJECT },      // sending back always needs a comment
                false),
            new compliancequest.SQX_Extension_Object_Policy_Provider(
                Field_Action__c.SObjectType,
                Field_Action_Record_Activity__c.SObjectType,
                Field_Action_Record_Activity__c.Activity_Code__c,
                new Set<String>(),
                false)
        };
    }

    /** When CQ Approvals approves or rejects an approval on a Field Action Review, which signature action applies. */
    global String getApplicableActionForExtensionObject(Id recordId, Boolean isApprove) {
        if (reviewFor(recordId) == null) { return null; }
        return isApprove == true ? APPROVE : REJECT;
    }

    /** Links a signature log row to its record: a field action's row to the field action; a review's row to the review, whether CQ hands us the review, its approval or an approval step. */
    global void setParentByChildRecordId(SObject sobj, Id childRecordId) {
        if (sobj != null && sobj.getSObjectType() == Field_Action_Record_Activity__c.SObjectType) {
            if (childRecordId != null && childRecordId.getSObjectType() == Field_Action__c.SObjectType) {
                sobj.put(Field_Action_Record_Activity__c.Field_Action__c, childRecordId);
            }
            return;
        }
        if (sobj == null || sobj.getSObjectType() != Field_Action_Review_Record_Activity__c.SObjectType) { return; }
        Id review = reviewFor(childRecordId);
        if (review != null) { sobj.put(Field_Action_Review_Record_Activity__c.Field_Action_Review__c, review); }
    }

    /** The Field Action Review behind an id: the review itself, or the main record of a CQ Approval or one of its steps. */
    @TestVisible
    private static Id reviewFor(Id recordId) {
        if (recordId == null) { return null; }
        Schema.SObjectType t = recordId.getSObjectType();
        if (t == Field_Action_Review__c.SObjectType) { return recordId; }
        String main;
        if (t == cqext__CQAPR_Approval_Step__c.SObjectType) {
            for (cqext__CQAPR_Approval_Step__c s : [SELECT cqext__CQAPR_Approval__r.cqext__Main_Record_Id__c FROM cqext__CQAPR_Approval_Step__c WHERE Id = :recordId]) {
                main = s.cqext__CQAPR_Approval__r?.cqext__Main_Record_Id__c;
            }
        } else if (t == cqext__CQAPR_Approval__c.SObjectType) {
            for (cqext__CQAPR_Approval__c a : [SELECT cqext__Main_Record_Id__c FROM cqext__CQAPR_Approval__c WHERE Id = :recordId]) {
                main = a.cqext__Main_Record_Id__c;
            }
        }
        if (String.isBlank(main)) { return null; }
        try {
            Id m = (Id) main;
            return m.getSObjectType() == Field_Action_Review__c.SObjectType ? m : null;
        } catch (Exception e) {
            return null;    // not an id
        }
    }
}

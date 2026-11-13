/**
 * CqTriageDraft: keeps the Triage workspace's work in progress on the Nonconformance,
 * so a triager can leave mid-triage and pick up where they left off. Cleared on Complete triage.
 */
public with sharing class CqTriageDraft {
    @AuraEnabled
    public static String getDraft(Id recordId) {
        return [SELECT Triage_Draft__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId].Triage_Draft__c;
    }

    @AuraEnabled
    public static void saveDraft(Id recordId, String draft) {
        update new compliancequest__SQX_Nonconformance__c(Id = recordId, Triage_Draft__c = String.isBlank(draft) ? null : draft.left(20000));
    }
}

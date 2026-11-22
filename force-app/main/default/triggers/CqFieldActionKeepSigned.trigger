/** A field action with an electronic signature stays: deleting it would delete its signatures with it (docs/esignature.md). */
trigger CqFieldActionKeepSigned on Field_Action__c (before delete) {
    Set<Id> signed = new Set<Id>();
    for (Field_Action_Record_Activity__c a : [SELECT Field_Action__c FROM Field_Action_Record_Activity__c WHERE Field_Action__c IN :Trigger.oldMap.keySet()]) {
        signed.add(a.Field_Action__c);
    }
    for (Field_Action__c fa : Trigger.old) {
        if (signed.contains(fa.Id)) { fa.addError('This field action has an electronic signature, so it cannot be deleted.'); }
    }
}

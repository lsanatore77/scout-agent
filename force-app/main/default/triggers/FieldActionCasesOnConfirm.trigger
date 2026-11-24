/** Confirming the strategy lists the customers and opens a Case for each one. */
trigger FieldActionCasesOnConfirm on Field_Action__c (after update) {
    for (Field_Action__c fa : Trigger.new) {
        if (fa.Strategy_Status__c == 'Confirmed' && Trigger.oldMap.get(fa.Id).Strategy_Status__c != 'Confirmed') { CqFieldActionCases.sync(fa.Id); }
    }
}

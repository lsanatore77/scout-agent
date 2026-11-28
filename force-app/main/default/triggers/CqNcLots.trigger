/** An NC's lot is always one of its lots (CqNcLots): added after save; fixed from Implement on. */
trigger CqNcLots on compliancequest__SQX_Nonconformance__c (before update, after insert, after update) {
    if (Trigger.isBefore) { CqNcLots.beforeUpdate(Trigger.new, Trigger.oldMap); }
    else { CqNcLots.afterSave(Trigger.new, Trigger.oldMap); }
}

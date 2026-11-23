/** CQ NC disposition: once complete, scrapping or returning the whole lot rejects it (CqLotStatus). */
trigger DispositionLotStatus on compliancequest__SQX_Disposition__c (after insert, after update, after delete, after undelete) {
    CqLotStatus.dispositionChanged(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}

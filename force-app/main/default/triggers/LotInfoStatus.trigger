/** Lot Info: a Release Status set by hand becomes Manual Status, then the status is worked out from everything that controls the lot (CqLotStatus). */
trigger LotInfoStatus on compliancequest__SQX_Lot_Info__c (before insert, before update) {
    CqLotStatus.beforeSave(Trigger.new, Trigger.isInsert ? null : Trigger.oldMap);
}

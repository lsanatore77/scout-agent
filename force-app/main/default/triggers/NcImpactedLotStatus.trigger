/** NC Impacted Part / Lot: the lot's Release Status follows what is left to dispose (CqLotStatus). */
trigger NcImpactedLotStatus on compliancequest__SQX_NC_Impacted_Product__c (after insert, after update, after delete, after undelete) {
    CqLotStatus.impactedChanged(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}

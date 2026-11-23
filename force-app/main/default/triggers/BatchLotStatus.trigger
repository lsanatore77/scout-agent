/** CQ batch record: when it is released, voided or reopened, the lots made from it are worked out again (CqLotStatus). */
trigger BatchLotStatus on cqext__CQEBR_Batch__c (after update) {
    CqLotStatus.batchChanged(Trigger.new, Trigger.oldMap);
}

/** Lot Stock: fills Lot Number from the lot record, and keeps Units On Hand and Location on open field actions in step. */
trigger LotStockTrigger on Lot_Stock__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        CqLotStock.onChange(Trigger.new, null, true);
    } else {
        CqLotStock.onChange(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap, false);
    }
}

/** Lot Return: matches the open field action, and keeps its lots' Returned in step with the units received. */
trigger LotReturnTrigger on Lot_Return__c (before insert, before update, after insert, after update, after delete, after undelete) {
    if (Trigger.isBefore) {
        CqLotReturns.onChange(Trigger.new, null, true);
    } else {
        CqLotReturns.onChange(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap, false);
    }
}

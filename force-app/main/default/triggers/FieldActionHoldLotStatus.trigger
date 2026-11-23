/** Field Action Hold: the held lot's Release Status follows the hold (CqLotStatus). */
trigger FieldActionHoldLotStatus on Field_Action_Hold__c (after insert, after update, after delete, after undelete) {
    CqLotStatus.holdsChanged(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}

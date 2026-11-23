/** Field Action Lot (scope): a lot in a recall's scope is Recall Pending, in the approved scope Recalled (CqLotStatus). */
trigger FieldActionLotStatus on Field_Action_Lot__c (after insert, after update, after delete, after undelete) {
    CqLotStatus.scopeChanged(Trigger.isDelete ? null : Trigger.new, Trigger.isInsert || Trigger.isUndelete ? null : Trigger.oldMap);
}

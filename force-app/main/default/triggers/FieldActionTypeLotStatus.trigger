/** Field Action: when it becomes, or stops being, a recall, the lots in its scope are worked out again (CqLotStatus). */
trigger FieldActionTypeLotStatus on Field_Action__c (after update) {
    CqLotStatus.actionTypeChanged(Trigger.new, Trigger.oldMap);
}

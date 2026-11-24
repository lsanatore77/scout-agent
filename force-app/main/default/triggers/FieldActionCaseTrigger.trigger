/** A Case that notifies a customer about a field action: what happens on it is written to the customer's row on the field action. */
trigger FieldActionCaseTrigger on Case (before update, after update) {
    CqFieldActionCases.onCase(Trigger.new, Trigger.oldMap, Trigger.isBefore);
}

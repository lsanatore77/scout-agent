/** Signatures are never changed or deleted once written. */
trigger CqFarSignatureLock on Field_Action_Review_Record_Activity__c (before update, before delete) {
    CqFarAudit.refuseChange(Trigger.isDelete ? Trigger.old : Trigger.new, 'A signature');
}

/** Audit entries are never changed or deleted once written. */
trigger CqFarAuditLock on Field_Action_Review_Audit__c (before update, before delete) {
    CqFarAudit.refuseChange(Trigger.isDelete ? Trigger.old : Trigger.new, 'An audit entry');
}

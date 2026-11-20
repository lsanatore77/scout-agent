/** Field Action Review audit trail: every create, field change and delete; a review with signatures cannot be deleted. */
trigger CqFieldActionReviewAudit on Field_Action_Review__c (before delete, after insert, after update, after delete) {
    if (Trigger.isBefore) { CqFarAudit.keepSigned(Trigger.old); return; }
    if (Trigger.isInsert) { CqFarAudit.log(Trigger.new, null, CqFarAudit.CREATED); }
    else if (Trigger.isUpdate) { CqFarAudit.log(Trigger.new, Trigger.oldMap, CqFarAudit.EDITED); }
    else { CqFarAudit.log(Trigger.old, null, CqFarAudit.DELETED); }
}

/** Every new NC goes straight to Triage and into a queue, with no Submit (CqNcAutoTriage). */
trigger CqNcAutoTriage on compliancequest__SQX_Nonconformance__c (after insert) {
    CqNcAutoTriage.afterInsert(Trigger.new);
}

/**
 * Every new NC goes straight to Triage and into a queue, wherever it was created (Report a Nonconformance, Intake,
 * CQ's wizard, an import): nobody presses Submit. Decided with Lou 25 Nov 2026.
 *
 * CQ's Submit (Activity Code 'submit') is not processed when set from Apex or the API in this org, so the move is made
 * here directly: Record Stage Triage, Submitted By the person who created it, and the owner the queue. That is the same
 * state CQ's Submit leaves (stage Triage, status Draft, owned by the queue), and CQ's own after-save flow still emails
 * the queue when the owner changes in Triage.
 *
 * The queue: the NC's Department's queue when it has one (CQ's Department.Queue Id), then CQ's Default Queue Name
 * setting, then the CQ Nonconformance Default Queue.
 *
 * Left alone: NCs created already past Draft, Quick Log NCs (trend-only, never triaged), and loads by users with CQ's
 * Data Migration permission (CQ's own rule for imports).
 *
 * without sharing: the person reporting may not be able to hand the NC to a queue themselves; routing is the system's job.
 */
public without sharing class CqNcAutoTriage {
    public static final String DRAFT = 'Draft';
    public static final String TRIAGE = 'Triage';
    public static final String DEFAULT_QUEUE = 'CQ Nonconformance Default Queue';

    /** Set by code that adds child records after the insert (Report a Nonconformance); it calls send() itself at the end. */
    public static Boolean deferred = false;

    /** Other classes' tests insert NCs and expect them in Draft; only this class's tests turn the trigger on. */
    @TestVisible static Boolean runInTests = false;

    /** After insert: sends the new Draft NCs to Triage, unless a caller has deferred it. */
    public static void afterInsert(List<compliancequest__SQX_Nonconformance__c> rows) {
        if (Test.isRunningTest() && !runInTests) { return; }
        if (deferred || FeatureManagement.checkPermission('compliancequest__SQXDataMigrationCustomPermission')) { return; }
        Set<Id> ids = new Set<Id>();
        for (compliancequest__SQX_Nonconformance__c n : rows) {
            if (eligible(n)) { ids.add(n.Id); }
        }
        if (!ids.isEmpty()) {
            try {
                send(ids, true);
            } catch (Exception e) {
                // never block creating the NC: it stays in Draft and the triage workspace can still start it
                System.debug(LoggingLevel.WARN, 'CqNcAutoTriage: ' + e.getMessage());
            }
        }
    }

    public static Boolean eligible(compliancequest__SQX_Nonconformance__c n) {
        return (n.compliancequest__Record_Stage__c == null || n.compliancequest__Record_Stage__c == DRAFT) && n.Quick_Log__c != true;
    }

    /**
     * Moves Draft NCs to Triage. toQueue: hand them to their queue (new NCs); false keeps the current owner (someone
     * starting triage on an older Draft NC they own). Returns how many moved.
     */
    public static Integer send(Set<Id> ids, Boolean toQueue) {
        if (ids == null || ids.isEmpty()) { return 0; }
        List<compliancequest__SQX_Nonconformance__c> rows = [SELECT Id, compliancequest__Record_Stage__c, Quick_Log__c,
                compliancequest__SQX_Department__r.compliancequest__Queue_Id__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :ids];
        Id fallback = toQueue ? defaultQueue() : null;
        Set<String> deptQueues = new Set<String>();
        for (compliancequest__SQX_Nonconformance__c n : rows) {
            String q = n.compliancequest__SQX_Department__r?.compliancequest__Queue_Id__c;
            if (String.isNotBlank(q)) { deptQueues.add(q); }
        }
        Set<Id> validQueues = new Set<Id>();
        if (toQueue && !deptQueues.isEmpty()) {
            Set<Id> asIds = new Set<Id>();
            for (String q : deptQueues) { if (isId(q)) { asIds.add(Id.valueOf(q)); } }
            for (QueueSobject qs : [SELECT QueueId FROM QueueSobject WHERE QueueId IN :asIds AND SobjectType = 'compliancequest__SQX_Nonconformance__c']) {
                validQueues.add(qs.QueueId);
            }
        }
        List<compliancequest__SQX_Nonconformance__c> ups = new List<compliancequest__SQX_Nonconformance__c>();
        for (compliancequest__SQX_Nonconformance__c n : rows) {
            if (!eligible(n)) { continue; }
            compliancequest__SQX_Nonconformance__c u = new compliancequest__SQX_Nonconformance__c(Id = n.Id,
                compliancequest__Record_Stage__c = TRIAGE, compliancequest__SQX_Submitted_By__c = UserInfo.getUserId(),
                compliancequest__Activity_Code__c = null);
            if (toQueue) {
                String dq = n.compliancequest__SQX_Department__r?.compliancequest__Queue_Id__c;
                Id q = String.isNotBlank(dq) && isId(dq) && validQueues.contains(Id.valueOf(dq)) ? Id.valueOf(dq) : fallback;
                if (q != null) { u.OwnerId = q; }
            }
            ups.add(u);
        }
        if (!ups.isEmpty()) { update ups; }
        return ups.size();
    }

    /** CQ's Default Queue Name setting when it names an NC queue, else the CQ Nonconformance Default Queue. */
    public static Id defaultQueue() {
        Set<String> names = new Set<String>{ DEFAULT_QUEUE };
        String setting;
        try {
            compliancequest__SQX_Custom_Settings_Public__c s = compliancequest__SQX_Custom_Settings_Public__c.getOrgDefaults();
            setting = s == null ? null : s.compliancequest__Default_Queue_Name__c;
        } catch (Exception e) { setting = null; }
        if (String.isNotBlank(setting)) { names.add(setting); }
        Id fromSetting; Id byName;
        for (QueueSobject qs : [SELECT QueueId, Queue.Name, Queue.DeveloperName FROM QueueSobject
                                WHERE SobjectType = 'compliancequest__SQX_Nonconformance__c'
                                AND (Queue.Name IN :names OR Queue.DeveloperName IN :names)]) {
            if (String.isNotBlank(setting) && (qs.Queue.Name == setting || qs.Queue.DeveloperName == setting)) { fromSetting = qs.QueueId; }
            if (qs.Queue.Name == DEFAULT_QUEUE) { byName = qs.QueueId; }
        }
        return fromSetting != null ? fromSetting : byName;
    }

    private static Boolean isId(String s) {
        try { Id x = Id.valueOf(s); return x != null; } catch (Exception e) { return false; }
    }
}

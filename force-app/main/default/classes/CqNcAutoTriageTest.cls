@IsTest
private class CqNcAutoTriageTest {
    static compliancequest__SQX_Nonconformance__c nc(String title) {
        return new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = title + ' description',
            compliancequest__NC_Title__c = title, compliancequest__Type__c = 'Internal');
    }
    static compliancequest__SQX_Nonconformance__c read(Id i) {
        return [SELECT compliancequest__Record_Stage__c, OwnerId, compliancequest__SQX_Submitted_By__c, Quick_Log__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :i];
    }

    @IsTest
    static void newNcGoesToTriageAndTheQueue() {
        CqNcAutoTriage.runInTests = true;
        compliancequest__SQX_Nonconformance__c n = nc('Auto triage');
        Test.startTest();
        insert n;
        Test.stopTest();
        compliancequest__SQX_Nonconformance__c r = read(n.Id);
        System.assertEquals('Triage', r.compliancequest__Record_Stage__c);
        System.assertEquals(UserInfo.getUserId(), r.compliancequest__SQX_Submitted_By__c);
        Id q = CqNcAutoTriage.defaultQueue();
        if (q != null) { System.assertEquals(q, r.OwnerId, 'the default NC queue owns it'); }
    }

    @IsTest
    static void quickLogAndDeferredStayInDraft() {
        CqNcAutoTriage.runInTests = true;
        compliancequest__SQX_Nonconformance__c quick = nc('Quick log');
        quick.Quick_Log__c = true;
        compliancequest__SQX_Nonconformance__c later = nc('Deferred');
        Test.startTest();
        insert quick;
        CqNcAutoTriage.deferred = true;
        insert later;
        CqNcAutoTriage.deferred = false;
        Test.stopTest();
        System.assertNotEquals('Triage', read(quick.Id).compliancequest__Record_Stage__c, 'Quick Log NCs are not triaged');
        System.assertNotEquals('Triage', read(later.Id).compliancequest__Record_Stage__c, 'a deferred insert waits for send()');
        System.assertEquals(1, CqNcAutoTriage.send(new Set<Id>{ later.Id }, true));
        System.assertEquals('Triage', read(later.Id).compliancequest__Record_Stage__c);
        System.assertEquals(0, CqNcAutoTriage.send(new Set<Id>{ later.Id }, true), 'already in Triage: left alone');
    }

    @IsTest
    static void keepOwnerWhenStartingTriage() {
        compliancequest__SQX_Nonconformance__c n = nc('Keep owner');
        insert n;   // runInTests is off: stays in Draft, as an older NC would
        Test.startTest();
        Integer moved = CqNcAutoTriage.send(new Set<Id>{ n.Id }, false);
        Test.stopTest();
        compliancequest__SQX_Nonconformance__c r = read(n.Id);
        System.assertEquals(1, moved);
        System.assertEquals('Triage', r.compliancequest__Record_Stage__c);
        System.assertEquals(UserInfo.getUserId(), r.OwnerId, 'the person starting triage stays the owner');
    }

    @IsTest
    static void departmentQueueWins() {
        // queues are setup data, visible in tests: use any NC queue other than the default one when there is one
        Id dflt = CqNcAutoTriage.defaultQueue();
        List<QueueSobject> qs = [SELECT QueueId FROM QueueSobject WHERE SobjectType = 'compliancequest__SQX_Nonconformance__c' AND QueueId != :dflt LIMIT 1];
        Id target = qs.isEmpty() ? dflt : qs[0].QueueId;
        if (target == null) { return; }
        compliancequest__SQX_Department__c d = new compliancequest__SQX_Department__c(Name = 'Auto Triage Dept', compliancequest__Queue_Id__c = target);
        insert d;
        CqNcAutoTriage.runInTests = true;
        compliancequest__SQX_Nonconformance__c n = nc('Department queue');
        n.compliancequest__SQX_Department__c = d.Id;
        Test.startTest();
        insert n;
        Test.stopTest();
        System.assertEquals(target, read(n.Id).OwnerId);
    }
}

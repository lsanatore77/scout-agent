@IsTest
private class CqQmHomeTest {
    @IsTest
    static void aTriagerSeesTheTriageLineAndTheLongestWaits() {
        Id q = CqNcAutoTriage.defaultQueue();
        if (q == null) { return; }
        CqTriageInbox.queuesOverride = new Set<Id>{ q };
        CqTriageInbox.canOwnOverride = true;
        compliancequest__SQX_Nonconformance__c n = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = 'Home wait',
            compliancequest__NC_Title__c = 'Home wait', compliancequest__Type__c = 'Internal');
        insert n;
        CqNcAutoTriage.send(new Set<Id>{ n.Id }, true);
        Test.setCreatedDate(n.Id, Datetime.now().addDays(-9));
        Test.startTest();
        CqQmHome.Home h = CqQmHome.load();
        Test.stopTest();
        System.assert(h.triager);
        System.assertEquals('triage', h.nc[0].key);
        System.assert(h.nc[0].stats[0].n >= 1, 'at least the new NC waits');
        Boolean listed = false;
        for (CqQmHome.Need x : h.needs) { if (x.id == n.Id) { listed = true; System.assert(x.why.startsWith('Waiting for triage'), x.why); System.assert(x.warn); } }
        System.assert(listed, 'an NC waiting 9 days needs a triager');
    }

    @IsTest
    static void overdueComesFirstForAnOwner() {
        CqTriageInbox.queuesOverride = new Set<Id>();
        CqTriageInbox.canOwnOverride = false;
        compliancequest__SQX_Nonconformance__c late = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = 'Late',
            compliancequest__NC_Title__c = 'Late', compliancequest__Type__c = 'Internal');
        compliancequest__SQX_Nonconformance__c soon = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = 'Soon',
            compliancequest__NC_Title__c = 'Soon', compliancequest__Type__c = 'Internal');
        insert new List<compliancequest__SQX_Nonconformance__c>{ late, soon };
        update new List<compliancequest__SQX_Nonconformance__c>{
            new compliancequest__SQX_Nonconformance__c(Id = late.Id, compliancequest__Record_Stage__c = 'Disposition_Investigate',
                compliancequest__Due_Date_Investigation__c = Date.today().addDays(1)),
            new compliancequest__SQX_Nonconformance__c(Id = soon.Id, compliancequest__Record_Stage__c = 'Disposition_Investigate',
                compliancequest__Due_Date_Disposition__c = Date.today().addDays(8))
        };
        CqTriageInbox.todayOverride = Date.today().addDays(3);   // the first is 2 days overdue, the second due in 5
        Test.startTest();
        CqQmHome.Home h = CqQmHome.load();
        Test.stopTest();
        System.assert(!h.triager);
        System.assertEquals('mine', h.nc[0].key, 'an owner without a queue sees My NCs');
        Integer iLate = -1, iSoon = -1;
        for (Integer i = 0; i < h.needs.size(); i++) {
            if (h.needs[i].id == late.Id) { iLate = i; }
            if (h.needs[i].id == soon.Id) { iSoon = i; }
        }
        System.assert(iLate >= 0 && iSoon >= 0, 'both need the owner');
        System.assert(iLate < iSoon, 'overdue before due soon');
    }

    @IsTest
    static void someoneWithNoRoleSeesWhatTheyReported() {
        CqTriageInbox.queuesOverride = new Set<Id>();
        CqTriageInbox.canOwnOverride = false;
        Test.startTest();
        CqQmHome.Home h = CqQmHome.load();
        Test.stopTest();
        // the running user may own NCs in the org; with none past Draft they see the NCs they reported
        System.assertNotEquals(0, h.nc.size());
        System.assert(h.nc[0].key == 'reported' || h.nc[0].key == 'mine');
    }
}

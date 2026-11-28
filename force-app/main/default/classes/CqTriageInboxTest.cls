@IsTest
private class CqTriageInboxTest {
    static Id queue() {
        Id q = CqNcAutoTriage.defaultQueue();
        if (q == null) {
            List<QueueSobject> qs = [SELECT QueueId FROM QueueSobject WHERE SobjectType = :CqTriageInbox.NC LIMIT 1];
            q = qs.isEmpty() ? null : qs[0].QueueId;
        }
        return q;
    }
    static compliancequest__SQX_Nonconformance__c waiting(String title, String lot) {
        compliancequest__SQX_Nonconformance__c n = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = title + ' description',
            compliancequest__NC_Title__c = title, compliancequest__Type__c = 'Internal', compliancequest__Lot_Number__c = lot);
        insert n;
        CqNcAutoTriage.send(new Set<Id>{ n.Id }, true);   // Triage, owned by the queue
        return n;
    }
    static Id ownerOf(Id i) { return [SELECT OwnerId FROM compliancequest__SQX_Nonconformance__c WHERE Id = :i].OwnerId; }

    @IsTest
    static void waitingListsTheQueuesNcsWithTheirFlags() {
        Id q = queue();
        if (q == null) { return; }
        CqTriageInbox.queuesOverride = new Set<Id>{ q };
        CqTriageInbox.canOwnOverride = true;
        compliancequest__SQX_Nonconformance__c a = waiting('First on the lot', 'TI-LOT-1');
        compliancequest__SQX_Nonconformance__c b = waiting('Second on the lot', 'TI-LOT-1');
        Test.startTest();
        CqTriageInbox.Inbox x = CqTriageInbox.load();
        Test.stopTest();
        System.assert(x.triager, 'a queue member who can own NCs is a triager');
        Map<Id, CqTriageInbox.Row> byId = new Map<Id, CqTriageInbox.Row>();
        for (CqTriageInbox.Row r : x.waiting) { byId.put(r.id, r); }
        System.assert(byId.containsKey(a.Id) && byId.containsKey(b.Id), 'both wait for triage');
        System.assertEquals('Take Ownership', byId.get(a.Id).primary);
        System.assertEquals('Today', byId.get(a.Id).waiting);
        String bFlags = String.join(byId.get(b.Id).flags, ';');
        System.assert(bFlags.contains('Possible duplicate'), 'the second NC on the lot is a possible duplicate: ' + bFlags);
    }

    @IsTest
    static void takeOwnershipTakesOneAndSaysWhoTookItFirst() {
        Id q = queue();
        if (q == null) { return; }
        CqTriageInbox.queuesOverride = new Set<Id>{ q };
        CqTriageInbox.canOwnOverride = true;
        compliancequest__SQX_Nonconformance__c a = waiting('Take me', null);
        Test.startTest();
        CqTriageInbox.Taken t = CqTriageInbox.takeOwnership(a.Id);
        Test.stopTest();
        System.assert(t.ok, t.message);
        System.assertEquals(UserInfo.getUserId(), ownerOf(a.Id));
        // it now shows under My NCs, still in Triage, with Continue Triage
        Boolean found = false;
        for (CqTriageInbox.Row r : CqTriageInbox.mineRows()) {
            if (r.id == a.Id) { found = true; System.assertEquals('Continue Triage', r.primary); System.assert(r.status.startsWith('In triage'), r.status); }
        }
        System.assert(found, 'the NC is in My NCs');
        // taking it again: already yours
        System.assert(CqTriageInbox.takeOwnership(a.Id).message.contains('already yours'));
    }

    @IsTest
    static void someoneWhoCannotOwnNcsCannotTake() {
        Id q = queue();
        if (q == null) { return; }
        CqTriageInbox.queuesOverride = new Set<Id>{ q };
        CqTriageInbox.canOwnOverride = false;
        compliancequest__SQX_Nonconformance__c a = waiting('Not mine to take', null);
        Boolean refused = false;
        try { CqTriageInbox.takeOwnership(a.Id); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'Can Own NC is required');
        System.assertEquals(q, ownerOf(a.Id), 'the queue still owns it');
    }

    @IsTest
    static void notInYourQueueIsRefused() {
        Id q = queue();
        if (q == null) { return; }
        compliancequest__SQX_Nonconformance__c a = waiting('Other queue', null);
        CqTriageInbox.queuesOverride = new Set<Id>();
        CqTriageInbox.canOwnOverride = true;
        Boolean refused = false;
        try { CqTriageInbox.takeOwnership(a.Id); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'only NCs in your queues can be taken');
    }

    @IsTest
    static void dueDatesShowOverdueFirst() {
        compliancequest__SQX_Nonconformance__c n = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = 'Due test',
            compliancequest__NC_Title__c = 'Due test', compliancequest__Type__c = 'Internal');
        insert n;
        update new compliancequest__SQX_Nonconformance__c(Id = n.Id, compliancequest__Record_Stage__c = 'Disposition_Investigate',
            compliancequest__Due_Date_Investigation__c = Date.today().addDays(3));
        CqTriageInbox.todayOverride = Date.today().addDays(6);   // three days after the due date
        List<CqTriageInbox.Row> rows = CqTriageInbox.mineRows();
        Boolean seen = false;
        for (CqTriageInbox.Row r : rows) {
            if (r.id == n.Id) {
                seen = true;
                System.assertEquals('Investigation overdue 3 days', r.status);
                System.assert(r.statusWarn);
                System.assertEquals('Disposition / Investigate', r.stageLabel);
                System.assertEquals('Continue Investigation', r.primary, 'the investigation is open and due first');
                System.assertEquals('investigation', r.openPart);
            }
        }
        System.assert(seen, 'an owned NC past triage is in My NCs');
    }

    @IsTest
    static void theButtonNamesTheNextStep() {
        Map<String, String> want = new Map<String, String>{ 'Triage' => 'Continue Triage', 'Implement' => 'Continue Implementation',
            'Verification' => 'Continue Verification', 'Closed' => 'Open' };
        for (String st : want.keySet()) {
            CqTriageInbox.Row r = new CqTriageInbox.Row();
            CqTriageInbox.next(r, new compliancequest__SQX_Nonconformance__c(compliancequest__Record_Stage__c = st));
            System.assertEquals(want.get(st), r.primary, st);
            System.assertEquals(null, r.openPart, st);
        }
        // Disposition / Investigate: whichever is still open
        CqTriageInbox.Row r = new CqTriageInbox.Row();
        CqTriageInbox.next(r, new compliancequest__SQX_Nonconformance__c(compliancequest__Record_Stage__c = 'Disposition_Investigate',
            compliancequest__Completion_Date_Investigation__c = Date.today()));
        System.assertEquals('Continue Disposition', r.primary);
        System.assertEquals('disposition', r.openPart);
        r = new CqTriageInbox.Row();
        CqTriageInbox.next(r, new compliancequest__SQX_Nonconformance__c(compliancequest__Record_Stage__c = 'Disposition_Investigate',
            compliancequest__Completion_Date_Disposition__c = Date.today()));
        System.assertEquals('Continue Investigation', r.primary);
        // both open: the one due first, the disposition on a tie
        r = new CqTriageInbox.Row();
        CqTriageInbox.next(r, new compliancequest__SQX_Nonconformance__c(compliancequest__Record_Stage__c = 'Disposition_Investigate',
            compliancequest__Due_Date_Disposition__c = Date.today().addDays(5), compliancequest__Due_Date_Investigation__c = Date.today().addDays(5)));
        System.assertEquals('Continue Disposition', r.primary);
    }

    @IsTest
    static void onlyTheOwnerReassignsToAQueueMember() {
        Id q = queue();
        if (q == null) { return; }
        CqTriageInbox.queuesOverride = new Set<Id>{ q };
        compliancequest__SQX_Nonconformance__c n = new compliancequest__SQX_Nonconformance__c(compliancequest__Description__c = 'Reassign',
            compliancequest__NC_Title__c = 'Reassign', compliancequest__Type__c = 'Internal');
        insert n;   // owned by the running user
        List<CqTriageInbox.Person> people = CqTriageInbox.reassignTo(n.Id);
        for (CqTriageInbox.Person p : people) { System.assertNotEquals(UserInfo.getUserId(), p.id, 'not the current owner'); }
        Boolean refused = false;
        try { CqTriageInbox.reassign(n.Id, UserInfo.getUserId(), null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'only a queue member who can own NCs can receive it');
        if (!people.isEmpty()) {
            CqTriageInbox.reassign(n.Id, people[0].id, 'Out Thursday and Friday.');
            System.assertEquals(people[0].id, ownerOf(n.Id));
        }
    }
}

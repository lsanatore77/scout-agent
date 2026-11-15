@IsTest
private class CqDispositionWorkspaceTest {

    static Id makeNc() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Disposition Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Disposition Part', cqext__Title__c = 'Disposition Part', compliancequest__Part_Number__c = 'DSP-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Seal open', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Seal open', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'DSP-LOT-1',
            compliancequest__Defective_Quantity__c = 4, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        // CQ may add the NC's part and lot as an impacted product itself; if not, add one so there is a lot to dispose
        if ([SELECT COUNT() FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :nc.Id] == 0) {
            insert new compliancequest__SQX_NC_Impacted_Product__c(compliancequest__SQX_Nonconformance__c = nc.Id,
                compliancequest__SQX_Impacted_Part__c = part.Id, compliancequest__Lot_Number__c = 'DSP-LOT-1', compliancequest__Lot_Quantity__c = 4);
        }
        return nc.Id;
    }

    static CqDispositionWorkspace.Past past(String type) {
        CqDispositionWorkspace.Past p = new CqDispositionWorkspace.Past(); p.type = type; return p;
    }

    @IsTest
    static void suggestionRules() {
        CqDispositionWorkspace.View v = new CqDispositionWorkspace.View();
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Scrap', v.suggestType, 'no history: the safe choice');

        v = new CqDispositionWorkspace.View();
        v.risk = 'Low';
        v.history.add(past('Rework')); v.history.add(past('Rework')); v.history.add(past('Scrap'));
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Rework', v.suggestType);
        System.assert(v.suggestWhy.startsWith('2 of the last 3 dispositions on this part were Rework.'), v.suggestWhy);

        v.risk = 'High';
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Scrap', v.suggestType, 'High risk goes to Scrap whatever the history');
    }

    @IsTest
    static void viewAndComplete() {
        Id ncId = makeNc();
        CqTriageNext.createDraftDispositions(ncId, Date.today().addDays(5));
        Test.startTest();
        CqDispositionWorkspace.View v = CqDispositionWorkspace.getView(ncId);
        System.assertEquals(4, v.types.size());
        System.assertNotEquals(null, v.suggestType);
        System.assertEquals(1, v.lots.size());
        CqDispositionWorkspace.Lot l = v.lots[0];
        System.assertNotEquals(null, l.draftId, 'the draft made at triage is picked up');
        // split the lot: Scrap all but one, Rework one
        List<Map<String, Object>> rows = new List<Map<String, Object>>{
            new Map<String, Object>{ 'impactedId' => l.impactedId, 'draftId' => l.draftId, 'type' => 'Scrap', 'qty' => l.left - 1,
                'completedOn' => String.valueOf(Date.today()), 'comment' => 'Scrapped' },
            new Map<String, Object>{ 'impactedId' => l.impactedId, 'type' => 'Rework', 'qty' => 1, 'completedOn' => String.valueOf(Date.today()) } };
        CqDispositionWorkspace.Result r = CqDispositionWorkspace.completeDispositions(ncId, JSON.serialize(rows));
        System.assertEquals(2, r.done.size());
        for (CqDispositionWorkspace.Rec x : r.done) { System.assertEquals('Complete', x.status); }
        System.assertEquals(0, r.remainders.size(), 'nothing left, so no new draft');
        Test.stopTest();
    }

    @IsTest
    static void refusesBadRows() {
        Id ncId = makeNc();
        CqTriageNext.createDraftDispositions(ncId, Date.today().addDays(5));
        CqDispositionWorkspace.View v = CqDispositionWorkspace.getView(ncId);
        Integer refused = 0;
        List<List<Map<String, Object>>> cases = new List<List<Map<String, Object>>>{ new List<Map<String, Object>>() };
        if (!v.lots.isEmpty()) {
            Id ip = v.lots[0].impactedId;
            cases.add(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => ip, 'type' => 'Melt', 'qty' => 1 } });
            cases.add(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => ip, 'type' => 'Scrap', 'qty' => 0 } });
            cases.add(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => ip, 'type' => 'Use As Is', 'qty' => 1 } });
            cases.add(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => ip, 'type' => 'Scrap', 'qty' => v.lots[0].left + 1 } });
        }
        for (List<Map<String, Object>> c : cases) {
            try { CqDispositionWorkspace.completeDispositions(ncId, JSON.serialize(c)); }
            catch (AuraHandledException e) { refused++; }
        }
        System.assertEquals(cases.size(), refused, 'every bad row is refused before anything is saved');
    }
}

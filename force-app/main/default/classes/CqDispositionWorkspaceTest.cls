@IsTest
private class CqDispositionWorkspaceTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Integer signed = 0;
        public CqEsign.Policy signFor(Id recordId, String action) {
            CqEsign.Policy g = new CqEsign.Policy(); g.required = required; g.purpose = 'Completing Disposition'; return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (password != 'right') { throw new AuraHandledException('Signature not accepted'); }
            signed++;
        }
    }
    static FakeEsig esig(Boolean required) { FakeEsig f = new FakeEsig(); f.required = required; CqEsign.gateway = f; return f; }

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
    static CqDispositionWorkspace.Past past(String type, String code, Integer daysAgo) {
        CqDispositionWorkspace.Past p = past(type); p.code = code; p.completedOn = Date.today().addDays(-daysAgo); return p;
    }

    @IsTest
    static void evidenceRules() {
        // a lot under an open field action follows the recall
        CqDispositionWorkspace.View v = new CqDispositionWorkspace.View();
        v.fieldActionName = 'FA-9'; v.fieldActionLots = 'L1';
        v.history.add(past('Use As Is'));
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Scrap', v.suggestType); System.assertEquals('High', v.confidence);
        System.assert(v.suggestWhy.contains('FA-9'), v.suggestWhy);

        // a supplier cause goes back to the supplier
        v = new CqDispositionWorkspace.View(); v.supplierCause = true; v.supplier = 'Acme Tubing';
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Return To Vendor (RTV)', v.suggestType);

        // the defect matters and the investigation is still looking: hold, Scrap if the stock cannot be held
        v = new CqDispositionWorkspace.View(); v.functional = true; v.investigationOpen = true; v.investigationName = 'INV-1';
        v.actual = '14 s'; v.spec = '10 s';
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Hold', v.suggestType); System.assertEquals('Scrap', v.suggestAlt);
        System.assert(v.suggestWhy.contains('INV-1'), v.suggestWhy);

        // same defect counts before the part; Use As Is is never suggested for a functional defect
        v = new CqDispositionWorkspace.View(); v.failureCode = 'Leak'; v.functional = true;
        v.evidence.add(past('Use As Is', 'Leak', 5)); v.evidence.add(past('Use As Is', 'Leak', 6)); v.evidence.add(past('Scrap', 'Leak', 7));
        v.evidence.add(past('Rework', 'Scratch', 3)); v.evidence.add(past('Rework', 'Scratch', 4)); v.evidence.add(past('Rework', 'Scratch', 5));
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Scrap', v.suggestType, 'Use As Is is skipped for a functional defect; other defects do not count');
        System.assert(v.suggestWhy.contains('with this defect'), v.suggestWhy);

        // a Rework that did not hold counts little; newer counts more
        v = new CqDispositionWorkspace.View(); v.failureCode = 'Bond';
        CqDispositionWorkspace.Past back = past('Rework', 'Bond', 10); back.cameBack = true;
        // Rework 0.3 + 1.0 against Scrap 1.0 + 0.6: without the discount for the Rework that came back, Rework would win 2.0 to 1.6
        v.evidence.add(back); v.evidence.add(past('Rework', 'Bond', 20)); v.evidence.add(past('Scrap', 'Bond', 30)); v.evidence.add(past('Scrap', 'Bond', 200));
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Scrap', v.suggestType);
        Boolean said = false;
        for (String f : v.suggestFactors) { if (f.contains('followed by the same defect')) { said = true; } }
        System.assert(said, v.suggestFactors);

        // a known process cause with little history points to Rework
        v = new CqDispositionWorkspace.View(); v.causeKnown = true; v.causeCategory = 'Machine'; v.causeText = 'Fixture worn';
        CqDispositionWorkspace.suggest(v);
        System.assertEquals('Rework', v.suggestType);
    }

    @IsTest
    static void signedForEveryLotAndSplit() {
        Map<Id, CqDispositionWorkspace.Lot> lots = new Map<Id, CqDispositionWorkspace.Lot>();
        Id a = Id.valueOf(compliancequest__SQX_NC_Impacted_Product__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA');
        CqDispositionWorkspace.Lot l = new CqDispositionWorkspace.Lot(); l.lot = 'L26-0908'; lots.put(a, l);
        List<CqDispositionWorkspace.Row> rows = new List<CqDispositionWorkspace.Row>();
        CqDispositionWorkspace.Row r1 = new CqDispositionWorkspace.Row(); r1.impactedId = a; r1.type = 'Rework'; r1.qty = 3; rows.add(r1);
        CqDispositionWorkspace.Row r2 = new CqDispositionWorkspace.Row(); r2.impactedId = a; r2.type = 'Scrap'; r2.qty = 2; rows.add(r2);
        System.assertEquals('Lot L26-0908: 3 Rework, 2 Scrap (5 units)', CqDispositionWorkspace.signedFor(rows, lots));
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
    static void nothingToDispose() {
        Id ncId = makeNc();
        delete [SELECT Id FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :ncId];
        CqDispositionWorkspace.View v = CqDispositionWorkspace.getView(ncId);
        System.assert(v.lots.isEmpty(), 'no lots');
        System.assertEquals(null, v.suggestType, 'nothing to dispose: no suggestion');
        System.assert(v.suggestWhy.contains('nothing to dispose'), v.suggestWhy);
    }

    @IsTest
    static void viewAndComplete() {
        esig(false);
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
            new Map<String, Object>{ 'impactedId' => l.impactedId, 'type' => 'Rework', 'qty' => 1, 'completedOn' => String.valueOf(Date.today()),
                'justification' => 'Re-bond to the work instruction and pressure test each unit' } };
        CqDispositionWorkspace.Result r = CqDispositionWorkspace.completeDispositions(ncId, JSON.serialize(rows), null, null);
        System.assertEquals(2, r.done.size());
        for (CqDispositionWorkspace.Rec x : r.done) { System.assertEquals('Complete', x.status); }
        System.assertEquals(0, r.remainders.size(), 'nothing left, so no new draft');
        Test.stopTest();
    }

    @IsTest
    static void refusesBadRows() {
        esig(false);
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
            // the root cause is not known, so Rework needs a reason
            cases.add(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => ip, 'type' => 'Rework', 'qty' => 1 } });
        }
        for (List<Map<String, Object>> c : cases) {
            try { CqDispositionWorkspace.completeDispositions(ncId, JSON.serialize(c), null, null); }
            catch (AuraHandledException e) { refused++; }
        }
        System.assertEquals(cases.size(), refused, 'every bad row is refused before anything is saved');
    }

    @IsTest
    static void signsBeforeSaving() {
        FakeEsig f = esig(true);
        Id ncId = makeNc();
        CqTriageNext.createDraftDispositions(ncId, Date.today().addDays(5));
        CqDispositionWorkspace.View v = CqDispositionWorkspace.getView(ncId);
        CqDispositionWorkspace.Lot l = v.lots[0];
        String payload = JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'impactedId' => l.impactedId, 'draftId' => l.draftId,
            'type' => 'Scrap', 'qty' => l.left, 'completedOn' => String.valueOf(Date.today()) } });
        Test.startTest();
        String refused;
        try { CqDispositionWorkspace.completeDispositions(ncId, payload, null, null); } catch (AuraHandledException e) { refused = e.getMessage(); }
        System.assertNotEquals(null, refused, 'no password, no disposition');
        try { CqDispositionWorkspace.completeDispositions(ncId, payload, null, 'wrong'); refused = null; } catch (AuraHandledException e) { refused = e.getMessage(); }
        System.assertNotEquals(null, refused, 'a wrong password changes nothing');
        System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Disposition__c WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Status__c = 'Complete']);
        CqDispositionWorkspace.Result r = CqDispositionWorkspace.completeDispositions(ncId, payload, 'Scrapped per SOP', 'right');
        Test.stopTest();
        System.assertEquals(1, f.signed, 'signed once');
        System.assertEquals(1, r.done.size());
    }

    @IsTest
    static void keepsTheSignature() {
        Id ncId = makeNc();
        CqNcSignable.signing = 'Lot DSP-LOT-1: 4 Scrap (4 units)';
        CqNcSignable keeper = new CqNcSignable();
        Integer before = keeper.signatureCount(ncId);
        keeper.record(ncId, 'completedisposition', 'Done', 'Completing Disposition', 'abc');
        System.assertEquals(before + 1, keeper.signatureCount(ncId));
        compliancequest__SQX_NC_Record_Activity__c row = [SELECT compliancequest__Activity_Code2__c, compliancequest__Comment_Long__c
            FROM compliancequest__SQX_NC_Record_Activity__c WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Transaction_Id__c = 'abc'];
        System.assertEquals('completedisposition', row.compliancequest__Activity_Code2__c);
        System.assert(row.compliancequest__Comment_Long__c.contains('4 Scrap'), row.compliancequest__Comment_Long__c);
    }
}

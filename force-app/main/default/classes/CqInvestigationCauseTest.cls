@IsTest
private class CqInvestigationCauseTest {

    /** An NC triaged to investigation, with one past NC whose CAPA closed, and two hypotheses. */
    static Map<String, Id> setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Cause Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Cause Part', cqext__Title__c = 'Cause Part',
            compliancequest__Part_Number__c = 'CAU-PART-1', compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c past = new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Hub bond leak', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = '<p>Leak at the hub bond</p>', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Occurrence_Date__c = Date.today().addDays(-150));
        insert past;
        compliancequest__SQX_CAPA__c capa = new compliancequest__SQX_CAPA__c(compliancequest__Title__c = 'Replace pin', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Issued_Date__c = Date.today().addDays(-140), compliancequest__Target_Due_Date__c = Date.today().addDays(-120));
        insert capa;
        update new compliancequest__SQX_CAPA__c(Id = capa.Id, compliancequest__Status__c = 'Closed', compliancequest__Record_Stage__c = 'Closed');
        update new compliancequest__SQX_Nonconformance__c(Id = past.Id, compliancequest__SQX_CAPA__c = capa.Id);

        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Hub bond leak', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description_RT__c = '<p>Leak at the hub bond again</p>', compliancequest__SQX_Part__c = part.Id,
            compliancequest__Lot_Number__c = 'CAU-LOT-1', compliancequest__Defective_Quantity__c = 4, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = 'submit');
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Investigation_Required__c = true, compliancequest__Activity_Code__c = 'takeownershipandinitiate');
        Id invId = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :nc.Id].compliancequest__SQX_Investigation__c;
        if (invId == null) {
            compliancequest__SQX_Investigation__c inv = new compliancequest__SQX_Investigation__c(compliancequest__SQX_Nonconformance__c = nc.Id);
            insert inv;
            invId = inv.Id;
        }
        Investigation_Hypothesis__c h1 = new Investigation_Hypothesis__c(Investigation__c = invId, Number__c = 1, Title__c = 'Worn locating pin on fixture BF-02, as in X',
            Category__c = 'Machine', Status__c = 'Open', Source_Record_Id__c = past.Id, Source_Name__c = 'NC-PAST');
        Investigation_Hypothesis__c h2 = new Investigation_Hypothesis__c(Investigation__c = invId, Number__c = 2, Title__c = 'Shorter cure time',
            Category__c = 'Method', Status__c = 'Open', Source_Name__c = 'Added by You');
        insert new List<Investigation_Hypothesis__c>{ h1, h2 };
        compliancequest__SQX_Root_Cause_Category__c cat = new compliancequest__SQX_Root_Cause_Category__c(Name = 'Machine');
        insert cat;
        compliancequest__SQX_Root_Cause_Sub_Category__c sub = new compliancequest__SQX_Root_Cause_Sub_Category__c(Name = 'Tooling', compliancequest__SQX_Root_Cause_Category__c = cat.Id);
        insert sub;
        compliancequest__SQX_Root_Cause_Code__c code1 = new compliancequest__SQX_Root_Cause_Code__c(Name = 'Fixture worn or damaged', compliancequest__SQX_Root_Cause_Sub_Category__c = sub.Id);
        compliancequest__SQX_Root_Cause_Code__c code2 = new compliancequest__SQX_Root_Cause_Code__c(Name = 'Preventive maintenance overdue', compliancequest__SQX_Root_Cause_Sub_Category__c = sub.Id);
        insert new List<compliancequest__SQX_Root_Cause_Code__c>{ code1, code2 };
        return new Map<String, Id>{ 'nc' => nc.Id, 'inv' => invId, 'h1' => h1.Id, 'h2' => h2.Id, 'past' => past.Id, 'code1' => code1.Id, 'code2' => code2.Id };
    }

    static CqInvestigationCause.Hyp hyp(CqInvestigationCause.View v, Id id) {
        for (CqInvestigationCause.Hyp h : v.hyps) { if (h.id == id) { return h; } }
        return null;
    }

    @IsTest
    static void evidenceSuggestsAndConfirms() {
        Map<String, Id> ids = setup();
        Id inv = ids.get('inv');
        Test.startTest();
        CqInvestigationCause.View v = CqInvestigationCause.getCause(inv);
        System.assertEquals(2, v.hyps.size());
        System.assert(hyp(v, ids.get('h1')).cameBack, 'its past case had a CAPA that closed');
        System.assertEquals('Needs Evidence', hyp(v, ids.get('h2')).suggest);

        v = CqInvestigationCause.saveIsNot(inv, JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'key' => 'where', 'isText' => 'BF-02', 'isNotText' => 'BF-01' },
            new Map<String, Object>{ 'key' => 'how', 'isText' => 'Thin on one side', 'isNotText' => 'Thin all round' } }));
        System.assertNotEquals(null, v.fiveId);
        v = CqInvestigationCause.saveFit(inv, ids.get('h1'), 'where', 'fits');
        v = CqInvestigationCause.saveFit(inv, ids.get('h1'), 'how', 'fits');
        v = CqInvestigationCause.saveFit(inv, ids.get('h2'), 'where', 'fails');
        System.assertEquals('Unlikely', hyp(v, ids.get('h2')).suggest);
        System.assertEquals('Likely', hyp(v, ids.get('h1')).suggest, hyp(v, ids.get('h1')).suggestWhy);

        Test.stopTest();
    }

    @IsTest
    static void evidenceAndStatus() {
        Map<String, Id> ids = setup();
        Id inv = ids.get('inv');
        Test.startTest();
        CqInvestigationCause.View v;
        v = CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'hypId' => ids.get('h1'), 'kind' => 'Test', 'testType' => 'Measure or Inspect',
            'status' => 'Done', 'detail' => 'Gauged the pin', 'result' => 'Pin 0.12 mm under nominal', 'supports' => 'For' }));
        v = CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'hypId' => ids.get('h1'), 'kind' => 'Test', 'testType' => 'Remove the Cause',
            'status' => 'Planned', 'detail' => 'Bond 20 units with a new pin', 'due' => String.valueOf(Date.today().addDays(5)) }));
        v = CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'hypId' => ids.get('h1'), 'kind' => 'Ask CQ.AI', 'detail' => 'CAPA only replaced the pin.' }));
        v = CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'hypId' => ids.get('h1'), 'kind' => 'CQ Record', 'recordId' => String.valueOf(ids.get('past')), 'recordName' => 'NC-PAST' }));
        CqInvestigationCause.Hyp h1 = hyp(v, ids.get('h1'));
        System.assertEquals(1, h1.testsDone);
        System.assertEquals(1, h1.testsPlanned);
        Boolean tested = false;
        for (CqInvestigationCause.Check c : h1.checks) { if (c.key == 'test') { tested = c.ok; } }
        System.assert(tested);
        try { CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'hypId' => ids.get('h1'), 'kind' => 'Test' })); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
        try { CqInvestigationCause.setStatus(inv, ids.get('h1'), 'Confirmed', ''); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
        v = CqInvestigationCause.setStatus(inv, ids.get('h1'), 'Confirmed', 'Pin measured under nominal');
        v = CqInvestigationCause.setStatus(inv, ids.get('h2'), 'Ruled Out', 'BF-01 passed');
        System.assertEquals('Confirmed', hyp(v, ids.get('h1')).status);
        Id askId;
        for (CqInvestigationCause.Evidence e : hyp(v, ids.get('h1')).evidence) { if (e.kind == 'Ask CQ.AI') { askId = e.id; } }
        v = CqInvestigationCause.deleteEvidence(inv, askId);
        Test.stopTest();
    }

    @IsTest
    static void whyAndRootCauses() {
        Map<String, Id> ids = setup();
        Id inv = ids.get('inv');
        CqInvestigationCause.setStatus(inv, ids.get('h1'), 'Confirmed', 'Pin measured under nominal');
        Test.startTest();
        CqInvestigationCause.View v = CqInvestigationCause.saveWhys(inv, ids.get('h1'), JSON.serialize(new List<Object>{
            new Map<String, Object>{ 'text' => 'Part sat off-axis' },
            new Map<String, Object>{ 'text' => 'Pin is worn' },
            new Map<String, Object>{ 'text' => 'No preventive maintenance check covers the pin', 'isRoot' => true } }));
        CqInvestigationCause.Hyp h1 = hyp(v, ids.get('h1'));
        System.assertEquals(3, h1.whys.size());
        System.assertNotEquals(null, h1.toolId);
        // shorten it: the last why goes, the second becomes root
        List<Object> two = new List<Object>{ new Map<String, Object>{ 'id' => h1.whys[0].id, 'text' => 'Part sat off-axis' },
            new Map<String, Object>{ 'id' => h1.whys[1].id, 'text' => 'No pin check in maintenance', 'isRoot' => true } };
        v = CqInvestigationCause.saveWhys(inv, ids.get('h1'), JSON.serialize(two));
        h1 = hyp(v, ids.get('h1'));
        System.assertEquals(2, h1.whys.size());
        System.assertEquals(2, v.roots.size(), 'the root why and the confirmed hypothesis');
        System.assertEquals('Primary', v.roots[0].role);
        System.assertEquals('Contributing', v.roots[1].role);
        System.assertEquals(ids.get('code2'), v.roots[0].codeId, 'maintenance suggests the maintenance code');
        // a test on the why makes it verified
        v = CqInvestigationCause.saveEvidence(inv, JSON.serialize(new Map<String, Object>{ 'whyId' => h1.whys[1].id, 'kind' => 'Test', 'testType' => 'Check Records',
            'status' => 'Done', 'detail' => 'Read the maintenance plan', 'result' => 'No pin check in the plan', 'supports' => 'For' }));
        System.assert(v.roots[0].verified);
        List<Object> rows = new List<Object>();
        for (CqInvestigationCause.RootRow r : v.roots) {
            rows.add(new Map<String, Object>{ 'key' => r.key, 'id' => r.id, 'hypId' => r.hypId, 'whyId' => r.whyId, 'text' => r.text, 'role' => r.role,
                'category' => r.category, 'codeId' => r.codeId, 'evidence' => r.evidence, 'verified' => r.verified });
        }
        v = CqInvestigationCause.saveRootCauses(inv, JSON.serialize(rows));
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :inv]);
        System.assertEquals(1, [SELECT COUNT() FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :inv AND Cause_Role__c = 'Primary']);
        System.assertNotEquals(null, [SELECT Root_Cause__c FROM Investigation_Hypothesis__c WHERE Id = :ids.get('h1')].Root_Cause__c);
        for (CqInvestigationCause.RootRow r : v.roots) { System.assert(r.saved); }
        // no Primary is refused
        for (Object o : rows) { ((Map<String, Object>) o).put('role', 'Contributing'); }
        try { CqInvestigationCause.saveRootCauses(inv, JSON.serialize(rows)); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest
    static void textHelpers() {
        List<String> p = CqInvestigationCause.split(CqInvestigationCause.join('BF-02 & line 2', 'BF-01'));
        System.assertEquals('BF-02 & line 2', p[0]);
        System.assertEquals('BF-01', p[1]);
        System.assertEquals('Plain text', CqInvestigationCause.split('<p>Plain text</p>')[0]);
        System.assertEquals(null, CqInvestigationCause.join(' ', null));
        System.assertEquals(0, CqInvestigationCause.findRecords('x').size());
        System.assertNotEquals(null, CqInvestigationCause.findRecords('NC-0001'));
    }
}

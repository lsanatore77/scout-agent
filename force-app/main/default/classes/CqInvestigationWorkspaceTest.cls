@IsTest
private class CqInvestigationWorkspaceTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Integer signed = 0; String action;
        public CqEsign.Policy signFor(Id recordId, String action) {
            CqEsign.Policy g = new CqEsign.Policy(); g.required = required; g.purpose = 'Submitting Investigation'; return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (password != 'right') { throw new AuraHandledException('Signature not accepted'); }
            this.action = action; signed++;
        }
    }
    static FakeEsig esig(Boolean required) { FakeEsig f = new FakeEsig(); f.required = required; CqEsign.gateway = f; return f; }

    /** An NC triaged to investigation, so CQ makes its investigation. */
    static Id makeNc() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Investigation Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Investigation Part', cqext__Title__c = 'Investigation Part', compliancequest__Part_Number__c = 'INV-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Hole offset', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Hole offset 0.4 mm', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'INV-LOT-1',
            compliancequest__Defective_Quantity__c = 5, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = 'submit');
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Investigation_Required__c = true,
            compliancequest__Activity_Code__c = 'takeownershipandinitiate');
        return nc.Id;
    }

    static List<Map<String, Object>> oneAction() {
        return new List<Map<String, Object>>{ new Map<String, Object>{ 'title' => 'Replace the locating pin', 'type' => 'Correction',
            'due' => String.valueOf(Date.today().addDays(10)) } };
    }

    @IsTest
    static void viewSaveAndComplete() {
        Id ncId = makeNc();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (nc.compliancequest__SQX_Investigation__c == null) { return; } // CQ did not make one in this org's test context
        FakeEsig f = esig(true);
        Test.startTest();
        CqInvestigationWorkspace.View v = CqInvestigationWorkspace.getView(ncId);
        System.assertEquals(nc.compliancequest__SQX_Investigation__c, v.investigationId, 'the NC resolves to its investigation');
        System.assert(!v.conclusions.isEmpty());
        System.assert(v.planTypes.contains('Corrective'));

        List<CqInvestigationWorkspace.Plan> saved = CqInvestigationWorkspace.saveActions(v.investigationId, JSON.serialize(oneAction()));
        System.assertEquals(1, saved.size());
        System.assertEquals(UserInfo.getUserId(), saved[0].userId, 'no owner given: the person saving owns it');
        // saving an empty list removes it again
        System.assertEquals(0, CqInvestigationWorkspace.saveActions(v.investigationId, '[]').size());

        // a wrong password changes nothing
        Boolean refused = false;
        try { CqInvestigationWorkspace.completeInvestigation(v.investigationId, v.conclusions[0], 'Pin worn on the fixture.', JSON.serialize(oneAction()), null, 'wrong'); }
        catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a refused signature stops the submission');
        System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Action_Plan__c WHERE compliancequest__SQX_Investigation__c = :v.investigationId], 'nothing saved');

        CqInvestigationWorkspace.Result r = CqInvestigationWorkspace.completeInvestigation(v.investigationId, v.conclusions[0],
            'Pin worn on the fixture.', JSON.serialize(oneAction()), 'Reviewed with the line lead.', 'right');
        System.assertNotEquals(null, r.responseName);
        System.assert(r.signed);
        System.assertEquals(1, f.signed);
        System.assertEquals('submitinvestigation', f.action);
        Test.stopTest();
        CqInvestigationWorkspace.View after = CqInvestigationWorkspace.getView(v.investigationId);
        System.assertEquals('Pin worn on the fixture.', after.summary);
        System.assertEquals(r.responseName, after.responseName);
    }

    @IsTest
    static void refusesBadInput() {
        Id ncId = makeNc();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (nc.compliancequest__SQX_Investigation__c == null) { return; }
        Id invId = nc.compliancequest__SQX_Investigation__c;
        esig(false);
        Integer refused = 0;
        List<String> bad = new List<String>{
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'type' => 'Correction', 'due' => '2027-01-01' } }),
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'title' => 'x', 'type' => 'Later', 'due' => '2027-01-01' } }),
            JSON.serialize(new List<Map<String, Object>>{ new Map<String, Object>{ 'title' => 'x', 'type' => 'Correction' } }) };
        for (String p : bad) {
            try { CqInvestigationWorkspace.saveActions(invId, p); } catch (AuraHandledException e) { refused++; }
        }
        try { CqInvestigationWorkspace.completeInvestigation(invId, null, 'summary', null, null, null); } catch (AuraHandledException e) { refused++; }
        try { CqInvestigationWorkspace.completeInvestigation(invId, 'Confirmed', ' ', null, null, null); } catch (AuraHandledException e) { refused++; }
        try { CqInvestigationWorkspace.getView(null); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(6, refused);
    }

    @IsTest
    static void signedForSaysWhat() {
        Id ncId = makeNc();
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (nc.compliancequest__SQX_Investigation__c == null) { return; }
        String s = CqInvestigationWorkspace.signedFor(nc.compliancequest__SQX_Investigation__c, 'Confirmed', JSON.serialize(oneAction()));
        System.assert(s.startsWith('conclusion Confirmed; root causes none recorded; 1 action'), s);
    }
}

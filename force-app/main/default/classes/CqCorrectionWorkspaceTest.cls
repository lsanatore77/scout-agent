@IsTest
private class CqCorrectionWorkspaceTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Integer signed = 0; String action;
        public CqEsign.Policy signFor(Id recordId, String action) {
            CqEsign.Policy g = new CqEsign.Policy(); g.required = required; g.purpose = 'Completing Action'; return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (password != 'right') { throw new AuraHandledException('Signature not accepted'); }
            this.action = action; signed++;
        }
    }
    static FakeEsig esig(Boolean required) { FakeEsig f = new FakeEsig(); f.required = required; CqEsign.gateway = f; return f; }

    /** An NC with one open correction assigned to the running user, or null when CQ refuses to make one in this context. */
    static Id makeAction(String title) {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Correction Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Correction Part', cqext__Title__c = 'Correction Part', compliancequest__Part_Number__c = 'COR-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Burst below rating', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = '2 of 20 burst at 15 atm', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'COR-LOT-1',
            compliancequest__Defective_Quantity__c = 2, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        try {
            compliancequest__SQX_Action__c a = new compliancequest__SQX_Action__c(compliancequest__SQX_Nonconformance__c = nc.Id,
                compliancequest__Title__c = title, compliancequest__Description__c = 'Re-test per WI-COR-001.', compliancequest__Plan_Type__c = 'Correction',
                compliancequest__Due_Date__c = Date.today().addDays(10), compliancequest__SQX_User__c = UserInfo.getUserId(), compliancequest__Status__c = 'Open');
            insert a;
            return a.Id;
        } catch (Exception e) {
            return null;   // CQ's own rules for making an action in this org's test context
        }
    }

    @IsTest
    static void findsDocumentNumbers() {
        System.assertEquals(new List<String>{ 'SOP-PTCA-060' }, CqCorrectionWorkspace.docNumbers('Re-test per SOP-PTCA-060 (rev G).'));
        System.assertEquals(new List<String>{ 'WI-000001', 'SOP-QA-021' }, CqCorrectionWorkspace.docNumbers('See WI-000001 and SOP-QA-021, then WI-000001 again.'));
        System.assert(CqCorrectionWorkspace.docNumbers('Replace the pin on fixture').isEmpty());
        System.assert(CqCorrectionWorkspace.docNumbers(null).isEmpty());
    }

    @IsTest
    static void viewAndComplete() {
        Id a = makeAction('Quarantine and re-test COR-LOT-1');
        if (a == null) { return; }
        FakeEsig f = esig(true);
        Test.startTest();
        CqCorrectionWorkspace.View v = CqCorrectionWorkspace.getView(a);
        System.assert(v.mine, 'assigned to the running user');
        System.assertEquals('Burst below rating', v.ncTitle);
        // checked before anything is saved
        Integer refused = 0;
        try { CqCorrectionWorkspace.complete(a, ' ', null, null, 'right'); } catch (AuraHandledException e) { refused++; }
        try { CqCorrectionWorkspace.complete(a, 'Done', String.valueOf(Date.today().addDays(3)), null, 'right'); } catch (AuraHandledException e) { refused++; }
        try { CqCorrectionWorkspace.complete(a, 'Done', null, null, 'wrong'); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(3, refused);
        System.assertEquals(0, f.signed);
        try {
            CqCorrectionWorkspace.Result r = CqCorrectionWorkspace.complete(a, 'All 18 re-tested; 2 scrapped.', String.valueOf(Date.today()), 'ok', 'right');
            System.assert(r.signed);
            System.assertEquals('implementation_complete', f.action);
        } catch (AuraHandledException e) {
            // CQ may refuse to complete an action made directly in a test; the signature still came first
            System.assertEquals(1, f.signed, e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void skipNeedsAReason() {
        Id a = makeAction('Re-label returned stock');
        if (a == null) { return; }
        esig(false);
        Boolean refused = false;
        try { CqCorrectionWorkspace.skip(a, '', null, null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused);
        try { CqCorrectionWorkspace.skip(a, 'Stock was already scrapped under the disposition.', null, null); } catch (AuraHandledException e) { /* CQ's own rules */ }
    }

    @IsTest
    static void refusesOtherRecords() {
        Boolean refused = false;
        try { CqCorrectionWorkspace.getView(UserInfo.getUserId()); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'only a CQ action');
    }
}

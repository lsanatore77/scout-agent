@IsTest
private class CqTriageNextTest {

    static Id makeNc(Decimal defective) {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Next Steps Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Next Steps Part', cqext__Title__c = 'Next Steps Part', compliancequest__Part_Number__c = 'NS-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Seal open', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Seal open', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'NS-LOT-1',
            compliancequest__Defective_Quantity__c = defective, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        return nc.Id;
    }

    @IsTest
    static void suggestsAndDefaults() {
        Id ncId = makeNc(4);
        Test.startTest();
        CqTriageNext.Next n = CqTriageNext.getNext(ncId);
        Test.stopTest();
        System.assertEquals('req', n.dispSuggest);
        System.assert(n.dispWhy.startsWith('4 units are defective'), n.dispWhy);
        System.assertNotEquals(null, n.invSuggest);
        System.assertEquals(Date.today().addDays(5), n.containmentDue);
        System.assertEquals(Date.today().addDays(5), n.dispDue);
        System.assertEquals(Date.today().addDays(60), n.invDue);
    }

    @IsTest
    static void noDispositionWhenNothingDefective() {
        Id ncId = makeNc(0);
        CqTriageNext.Next n = CqTriageNext.getNext(ncId);
        System.assertEquals('no', n.dispSuggest);
    }

    @IsTest
    static void completeSavesTriage() {
        Id ncId = makeNc(4);
        String payload = JSON.serialize(new Map<String, Object>{
            'risk' => 'Low', 'notes' => 'Containment: No action', 'severity' => 2,
            'containment' => false, 'containmentTitles' => new List<String>(), 'containmentDue' => String.valueOf(Date.today().addDays(5)),
            'disposition' => true, 'dispositionDue' => String.valueOf(Date.today().addDays(5)), 'dispositionApproval' => false,
            'investigate' => false, 'investigationApproval' => false });
        Test.startTest();
        CqTriageNext.Done d = CqTriageNext.completeTriage(ncId, payload);
        Test.stopTest();
        System.assertEquals('Log Only', d.path);
        compliancequest__SQX_Nonconformance__c nc = [SELECT Triage_Risk__c, Triage_Path__c, Triage_Draft__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        System.assertEquals('Low', nc.Triage_Risk__c);
        System.assertEquals(null, nc.Triage_Draft__c);
    }

    @IsTest
    static void approvalNeedsMatrix() {
        Id ncId = makeNc(4);
        String payload = JSON.serialize(new Map<String, Object>{
            'risk' => 'High', 'disposition' => true, 'dispositionDue' => String.valueOf(Date.today()), 'dispositionApproval' => true,
            'investigate' => false });
        try {
            CqTriageNext.completeTriage(ncId, payload);
            System.assert(false, 'expected a refusal');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        System.assertNotEquals(null, CqTriageNext.matrices());
    }

    @IsTest
    static void startTriageMovesDraftOnly() {
        Id ncId = makeNc(4);
        Test.startTest();
        CqTriageNext.Started s = CqTriageNext.startTriage(ncId);
        CqTriageNext.Started again = CqTriageNext.startTriage(ncId);
        Test.stopTest();
        System.assert(s.moved || s.warning != null, 'either moved or told why not');
        if (s.moved) {
            System.assertEquals('Triage', s.stage);
            System.assertEquals(false, again.moved, 'a second start leaves the NC where it is');
        }
    }

    @IsTest
    static void completeLeavesFlagsToCompleteTriage() {
        Id ncId = makeNc(4);
        String payload = JSON.serialize(new Map<String, Object>{
            'risk' => 'Medium', 'notes' => 'x', 'severity' => 3,
            'containment' => false, 'containmentTitles' => new List<String>(),
            'disposition' => true, 'dispositionDue' => String.valueOf(Date.today().addDays(5)), 'dispositionApproval' => false,
            'investigate' => true, 'investigationDue' => String.valueOf(Date.today().addDays(60)), 'investigationApproval' => false });
        CqTriageNext.Done d = CqTriageNext.completeTriage(ncId, payload);
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__Disposition_Required__c, Triage_Draft__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        System.assertEquals(false, nc.compliancequest__Disposition_Required__c, 'CQ flag stays off; we create the dispositions');
        System.assertEquals(null, nc.Triage_Draft__c);
        Integer lots = [SELECT COUNT() FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Quantity_Left_To_Dispose__c > 0];
        System.assertEquals(lots, [SELECT COUNT() FROM compliancequest__SQX_Disposition__c WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Status__c = 'Draft']);
        // a second call adds nothing for lots that already have an open disposition
        System.assertEquals(0, CqTriageNext.createDraftDispositions(ncId, Date.today()).size());
    }
}

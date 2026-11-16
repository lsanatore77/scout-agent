@IsTest
private class CqInvestigationChangesTest {

    /** An NC on a part, triaged to investigation, with one change of each kind CQ holds. */
    static Id setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Changes Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Changes Part', cqext__Title__c = 'Changes Part', compliancequest__Part_Number__c = 'CHG-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Leak', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Leak at the hub', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'CHG-LOT-1',
            compliancequest__Defective_Quantity__c = 3, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Activity_Code__c = 'submit');
        update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__Investigation_Required__c = true,
            compliancequest__Activity_Code__c = 'takeownershipandinitiate');

        compliancequest__SQX_Change_Order__c co = new compliancequest__SQX_Change_Order__c(compliancequest__Title__c = 'Move fixture', compliancequest__SQX_Product__c = part.Id);
        insert co;
        update new compliancequest__SQX_Change_Order__c(Id = co.Id, compliancequest__Target_Completion_Date__c = Date.today().addDays(-5));
        compliancequest__SQX_Controlled_Document__c doc = new compliancequest__SQX_Controlled_Document__c(compliancequest__Title__c = 'Bonding WI',
            compliancequest__Document_Number__c = 'WI-T1', compliancequest__Revision__c = 'B', compliancequest__SQX_Part__c = part.Id);
        insert doc;
        update new compliancequest__SQX_Controlled_Document__c(Id = doc.Id, compliancequest__Date_Issued__c = Date.today().addDays(-20));
        insert new compliancequest__SQX_Lot_Info__c(Name = 'CHG-LOT-1', compliancequest__Part_Number__c = 'CHG-PART-1', compliancequest__Manufacturing_Date__c = Date.today().addDays(-2));
        // optional extras: a supplier deviation in effect, and the NC's equipment with a calibration (skipped if CQ refuses them)
        try { insert new compliancequest__SQX_Supplier_Deviation__c(compliancequest__SQX_Part__c = part.Id); } catch (Exception e) { System.debug(e.getMessage()); }
        try {
            compliancequest__SQX_Equipment__c eq = new compliancequest__SQX_Equipment__c(Name = 'FX-1', compliancequest__Equipment_Description__c = 'Fixture',
                compliancequest__Equipment_Type__c = 'Machine', compliancequest__Requires_Periodic_Calibration__c = true,
                compliancequest__Next_Calibration_Date__c = Date.today().addDays(30), compliancequest__Calibration_Interval__c = 180);
            insert eq;
            update new compliancequest__SQX_Equipment__c(Id = eq.Id, compliancequest__Equipment_Status__c = 'Active');
            insert new compliancequest__SQX_Calibration__c(compliancequest__SQX_Equipment__c = eq.Id, compliancequest__Calibration_Date__c = Date.today().addDays(-150),
                compliancequest__Next_Calibration_Date__c = Date.today().addDays(-1), compliancequest__Performed_By__c = 'Tester');
            update new compliancequest__SQX_Nonconformance__c(Id = nc.Id, compliancequest__SQX_Equipment__c = eq.Id);
        } catch (Exception e) { System.debug(e.getMessage()); }
        return nc.Id;
    }

    @IsTest
    static void gathersRatesAndAdds() {
        Id ncId = setup();
        Test.startTest();
        CqInvestigationChanges.View v = CqInvestigationChanges.getChanges(ncId, 30);
        System.assertEquals(Date.today(), v.startDate);
        System.assertEquals('Occurrence Date', v.startFrom);
        System.assertEquals(Date.today().addDays(-30), v.windowStart);
        Map<String, CqInvestigationChanges.Item> byKind = new Map<String, CqInvestigationChanges.Item>();
        for (CqInvestigationChanges.Item it : v.items) { byKind.put(it.kind, it); }
        System.assertEquals(CqInvestigationChanges.COULD, byKind.get('change').rating, '5 days before: could explain it');
        System.assertEquals(CqInvestigationChanges.WORTH, byKind.get('document').rating, '20 days before: worth a look');
        System.assertEquals(CqInvestigationChanges.AFFECTED, byKind.get('lot').rating);
        System.assert(!v.categories.isEmpty());

        Id changeId = CqInvestigationChanges.addChange(ncId, JSON.serialize(new Map<String, Object>{
            'whatChanged' => 'Pin not checked after the move', 'changeDate' => String.valueOf(Date.today().addDays(-3)), 'category' => 'Machine',
            'whereFound' => 'Maintenance log' }));
        System.assertEquals(1, CqInvestigationChanges.addHypothesis(ncId, JSON.serialize(new Map<String, Object>{
            'title' => 'Fixture not realigned', 'category' => 'Machine', 'sourceId' => byKind.get('change').recordId, 'sourceName' => byKind.get('change').name })));
        System.assertEquals(2, CqInvestigationChanges.addHypothesis(ncId, JSON.serialize(new Map<String, Object>{
            'title' => 'Pin worn', 'category' => 'Machine', 'sourceId' => changeId, 'sourceName' => 'IC' })));
        Test.stopTest();

        v = CqInvestigationChanges.getChanges(ncId, 14);
        System.assertEquals(2, v.hypotheses.size());
        Integer linked = 0;
        for (CqInvestigationChanges.Item it : v.items) {
            if (it.kind == 'document') { System.assert(false, 'the document is outside a 14 day window'); }
            if (it.hypothesis != null) { linked++; }
            if (it.kind == 'manual') { System.assertEquals(CqInvestigationChanges.COULD, it.rating); System.assert(it.byHand); }
        }
        System.assertEquals(2, linked, 'both changes show the hypothesis made from them');
    }

    @IsTest
    static void refusesIncompleteInput() {
        Id ncId = setup();
        Integer refused = 0;
        List<Map<String, Object>> bad = new List<Map<String, Object>>{
            new Map<String, Object>{ 'changeDate' => '2026-10-01', 'category' => 'Machine' },
            new Map<String, Object>{ 'whatChanged' => 'x', 'category' => 'Machine' },
            new Map<String, Object>{ 'whatChanged' => 'x', 'changeDate' => '2026-10-01' } };
        for (Map<String, Object> m : bad) { try { CqInvestigationChanges.addChange(ncId, JSON.serialize(m)); } catch (AuraHandledException e) { refused++; } }
        try { CqInvestigationChanges.addHypothesis(ncId, JSON.serialize(new Map<String, Object>{ 'category' => 'Machine' })); } catch (AuraHandledException e) { refused++; }
        try { CqInvestigationChanges.addHypothesis(ncId, JSON.serialize(new Map<String, Object>{ 'title' => 'x' })); } catch (AuraHandledException e) { refused++; }
        System.assertEquals(5, refused);
    }
}

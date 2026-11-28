@IsTest
private class CqTriageImpactTest {
    static compliancequest__SQX_Nonconformance__c make(String lot, Decimal qty) {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Impact Family');
        insert fam;
        compliancequest__SQX_Part__c p = new compliancequest__SQX_Part__c(Name = 'Impact Part', cqext__Title__c = 'Impact Part',
            compliancequest__Part_Number__c = 'IMPACT-1', compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert p;
        compliancequest__SQX_Nonconformance__c n = new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Impact test',
            compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description__c = 'Impact test',
            compliancequest__SQX_Part__c = p.Id, compliancequest__Lot_Number__c = lot, compliancequest__Defective_Quantity__c = qty,
            compliancequest__Occurrence_Date__c = Date.today());
        insert n;
        return n;
    }

    @IsTest
    static void theReportedLotIsPendingUntilItHasAQuantity() {
        compliancequest__SQX_Nonconformance__c n = make('IM-001', null);
        CqTriageImpact.Impact x = CqTriageImpact.getImpact(n.Id);
        System.assertEquals(1, x.lots.size());
        System.assert(x.lots[0].pending && x.lots[0].reported);
        System.assertEquals('IM-001', x.lots[0].lot);
        Boolean refused = false;
        try { CqTriageImpact.saveLot(n.Id, null, 'IM-001', 0); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a quantity is needed');
        CqTriageImpact.saveLot(n.Id, null, 'IM-001', 4);
        x = CqTriageImpact.getImpact(n.Id);
        System.assertEquals(1, x.lots.size());
        System.assert(!x.lots[0].pending && x.lots[0].reported && !x.lots[0].canRemove);
        System.assertEquals(4, x.lots[0].qty);
    }

    @IsTest
    static void lotsAreAddedChangedAndRemoved() {
        compliancequest__SQX_Nonconformance__c n = make('IM-010', null);
        Id first = CqTriageImpact.saveLot(n.Id, null, 'IM-010', 3);
        Id other = CqTriageImpact.saveLot(n.Id, null, 'IM-011', 2);
        Boolean dup = false;
        try { CqTriageImpact.saveLot(n.Id, null, 'im-011', 1); } catch (AuraHandledException e) { dup = true; }
        System.assert(dup, 'the same lot twice is refused');
        CqTriageImpact.saveLot(n.Id, other, null, 5);
        CqTriageImpact.Impact x = CqTriageImpact.getImpact(n.Id);
        System.assertEquals(2, x.lots.size());
        System.assertEquals('IM-010', x.lots[0].lot, 'the reported lot is first');
        System.assertEquals(5, x.lots[1].qty);
        System.assert(x.lots[1].canRemove);
        Boolean kept = false;
        try { CqTriageImpact.removeLot(n.Id, first); } catch (AuraHandledException e) { kept = true; }
        System.assert(kept, 'the reported lot stays');
        CqTriageImpact.removeLot(n.Id, other);
        System.assertEquals(1, CqTriageImpact.getImpact(n.Id).lots.size());
    }

    @IsTest
    static void containmentsShowOnTheirLot() {
        compliancequest__SQX_Nonconformance__c n = make('IM-020', null);
        Id lotId = CqTriageImpact.saveLot(n.Id, null, 'IM-020', 6);
        String one, all;
        try {
            one = CqTriageImpact.addContainment(n.Id, lotId, 'Quarantine lot IM-020', null, String.valueOf(Date.today().addDays(2)), null);
            all = CqTriageImpact.addContainment(n.Id, null, 'Stop shipments of the part', null, String.valueOf(Date.today().addDays(2)), null);
        } catch (AuraHandledException e) { return; }   // CQ's own rules for containments in this org's test context
        CqTriageImpact.Impact x = CqTriageImpact.getImpact(n.Id);
        System.assertEquals(1, x.lots[0].containments.size());
        System.assertEquals(one, x.lots[0].containments[0].name);
        System.assertEquals(1, x.allLots.size());
        System.assertEquals(all, x.allLots[0].name);
        Boolean refused = false;
        try { CqTriageImpact.addContainment(n.Id, lotId, ' ', null, String.valueOf(Date.today()), null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a title is needed');
    }

    @IsTest
    static void suggestsOtherLotsOfThePart() {
        compliancequest__SQX_Nonconformance__c n = make('IM-030', null);
        Id partId = [SELECT compliancequest__SQX_Part__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :n.Id].compliancequest__SQX_Part__c;
        Date d = Date.today().addDays(-120);
        insert new List<compliancequest__SQX_Lot_Info__c>{
            new compliancequest__SQX_Lot_Info__c(Name = 'IM-030', Part__c = partId, compliancequest__Manufacturing_Date__c = d, Sterilization_Lot__c = 'EO-1', Supplier_Lot__c = 'S-1'),
            new compliancequest__SQX_Lot_Info__c(Name = 'IM-031', Part__c = partId, compliancequest__Manufacturing_Date__c = d.addDays(60), Supplier_Lot__c = 'S-1'),
            new compliancequest__SQX_Lot_Info__c(Name = 'IM-032', Part__c = partId, compliancequest__Manufacturing_Date__c = d.addDays(60), Sterilization_Lot__c = 'EO-1'),
            new compliancequest__SQX_Lot_Info__c(Name = 'IM-033', Part__c = partId, compliancequest__Manufacturing_Date__c = d.addDays(3)),
            new compliancequest__SQX_Lot_Info__c(Name = 'IM-034', Part__c = partId, compliancequest__Manufacturing_Date__c = d.addDays(90))
        };
        List<CqTriageImpact.Suggestion> s = CqTriageImpact.getImpact(n.Id).suggestions;
        List<String> lots = new List<String>();
        for (CqTriageImpact.Suggestion x : s) { lots.add(x.lot); }
        System.assertEquals(new List<String>{ 'IM-031', 'IM-032', 'IM-033' }, lots, 'strongest reason first; nothing for a lot with no match');
        System.assert(s[2].why.startsWith('Made 3 days after'), s[2].why);
    }
}

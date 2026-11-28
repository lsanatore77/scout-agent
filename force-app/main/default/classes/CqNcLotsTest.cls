@IsTest
private class CqNcLotsTest {
    static Id part() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Lots Family');
        insert fam;
        compliancequest__SQX_Part__c p = new compliancequest__SQX_Part__c(Name = 'Lots Part', cqext__Title__c = 'Lots Part',
            compliancequest__Part_Number__c = 'LOTS-PART-1', compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert p;
        return p.Id;
    }
    static compliancequest__SQX_Nonconformance__c nc(Id partId, String lot, Decimal qty) {
        return new compliancequest__SQX_Nonconformance__c(compliancequest__NC_Title__c = 'Lots test', compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description__c = 'Lots test', compliancequest__SQX_Part__c = partId,
            compliancequest__Lot_Number__c = lot, compliancequest__Defective_Quantity__c = qty, compliancequest__Occurrence_Date__c = Date.today());
    }
    static List<String> lots(Id ncId) {
        List<String> out = new List<String>();
        for (compliancequest__SQX_NC_Impacted_Product__c l : [SELECT compliancequest__Lot_Number__c, compliancequest__Lot_Quantity__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :ncId ORDER BY CreatedDate, Name]) {
            out.add(l.compliancequest__Lot_Number__c + '=' + l.compliancequest__Lot_Quantity__c.intValue());
        }
        return out;
    }

    @IsTest
    static void theNcLotBecomesOneOfItsLots() {
        CqNcLots.runInTests = true;
        compliancequest__SQX_Nonconformance__c n = nc(part(), 'LT-001', 5);
        insert n;
        System.assertEquals(new List<String>{ 'LT-001=5' }, lots(n.Id));
        // saving again adds nothing; the same lot in other case is the same lot
        update new compliancequest__SQX_Nonconformance__c(Id = n.Id, compliancequest__Lot_Number__c = 'lt-001 ');
        System.assertEquals(1, lots(n.Id).size());
        // a new lot on the NC is added too; the old one stays (it was impacted)
        update new compliancequest__SQX_Nonconformance__c(Id = n.Id, compliancequest__Lot_Number__c = 'LT-002');
        System.assertEquals(new List<String>{ 'LT-001=5', 'LT-002=5' }, lots(n.Id));
    }

    @IsTest
    static void noQuantityLeavesItForTheImpactStep() {
        CqNcLots.runInTests = true;
        compliancequest__SQX_Nonconformance__c n = nc(part(), 'LT-010', null);
        insert n;
        System.assertEquals(0, lots(n.Id).size());
        update new compliancequest__SQX_Nonconformance__c(Id = n.Id, compliancequest__Defective_Quantity__c = 3);
        System.assertEquals(new List<String>{ 'LT-010=3' }, lots(n.Id));
    }

    @IsTest
    static void theLotIsFixedFromImplementOn() {
        CqNcLots.runInTests = true;
        compliancequest__SQX_Nonconformance__c n = nc(part(), 'LT-020', 2);
        insert n;
        compliancequest__SQX_Nonconformance__c o = n.clone(true);
        o.compliancequest__Record_Stage__c = 'Implement';
        compliancequest__SQX_Nonconformance__c changed = n.clone(true);
        changed.compliancequest__Lot_Number__c = 'LT-021';
        CqNcLots.beforeUpdate(new List<compliancequest__SQX_Nonconformance__c>{ changed }, new Map<Id, compliancequest__SQX_Nonconformance__c>{ n.Id => o });
        System.assert(changed.hasErrors(), 'the lot is fixed in Implement');
        System.assertEquals(CqNcLots.LOT_FIXED, changed.getErrors()[0].getMessage());
        // in Triage it may change
        o.compliancequest__Record_Stage__c = 'Triage';
        compliancequest__SQX_Nonconformance__c ok = n.clone(true);
        ok.compliancequest__Lot_Number__c = 'LT-022';
        CqNcLots.beforeUpdate(new List<compliancequest__SQX_Nonconformance__c>{ ok }, new Map<Id, compliancequest__SQX_Nonconformance__c>{ n.Id => o });
        System.assert(!ok.hasErrors());
    }

    @IsTest
    static void offInOtherTests() {
        compliancequest__SQX_Nonconformance__c n = nc(part(), 'LT-030', 4);
        insert n;
        System.assertEquals(0, lots(n.Id).size(), 'other tests add their own lots');
        System.assert(CqNcLots.same(' ab ', 'AB'));
    }
}

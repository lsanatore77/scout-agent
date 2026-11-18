@IsTest
private class CqEventLotsTest {
    @IsTest
    static void lotsForPart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Lots Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Lots Part', cqext__Title__c = 'Lots Part', compliancequest__Part_Number__c = 'LOTS-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        System.assertEquals(0, CqEventLots.getLots(null).size(), 'no part, no lots');
        System.assertNotEquals(null, CqEventLots.getLots(part.Id), 'a part with no lots gives an empty list');
    }

    @IsTest
    static void searchFindsTheLotAndItsPart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Lots Family 2');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Lots Part 2', cqext__Title__c = 'Lots Part 2', compliancequest__Part_Number__c = 'LOTS-PART-2',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        insert new compliancequest__SQX_Lot_Info__c(Name = 'ZQLOT-0001', compliancequest__Part_Number__c = 'LOTS-PART-2');

        List<CqEventLots.Lot> found = CqEventLots.searchLots('ZQLOT', null);
        System.assertEquals(1, found.size(), 'the lot is found by its number');
        System.assertEquals('ZQLOT-0001', found[0].lot);
        System.assertEquals(part.Id, found[0].partId, 'the lot carries its part');
        System.assertEquals('Lots Part 2', found[0].partName);

        System.assertEquals(1, CqEventLots.searchLots('', part.Id).size(), 'a part lists its lots');
        System.assertEquals(1, CqEventLots.searchLots('zqlot', part.Id).size(), 'search within a part');
        System.assertEquals(0, CqEventLots.searchLots('NO-SUCH-LOT', null).size(), 'no match, no lots');
        System.assertNotEquals(null, CqEventLots.searchLots(null, null), 'a blank term gives the newest lots');
        System.assertEquals(1, CqEventLots.getLots(part.Id).size());
    }
}

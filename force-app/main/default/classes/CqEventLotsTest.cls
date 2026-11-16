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
}

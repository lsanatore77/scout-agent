@IsTest
private class CqEventLotLinkTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'LotLink Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(Name = 'LotLink Part', cqext__Title__c = 'LotLink Part',
            compliancequest__Part_Number__c = 'LL-PART-1', compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert new compliancequest__SQX_Lot_Info__c(Name = 'L26-0908', compliancequest__Part_Number__c = 'LL-PART-1');
    }

    static Id partId() { return [SELECT Id FROM compliancequest__SQX_Part__c WHERE compliancequest__Part_Number__c = 'LL-PART-1'].Id; }

    @IsTest
    static void partialLotResolvesToPart() {
        CqEventLotLink.LotMatch m = CqEventLotLink.resolve('0908');
        System.assertEquals(1, m.matches, 'the one lot that contains 0908');
        System.assertEquals('L26-0908', m.lotName, 'shorthand completed to the full lot');
        System.assertEquals(partId(), m.partId, 'resolved to its part');
    }

    @IsTest
    static void unknownLotResolvesToNothing() {
        CqEventLotLink.LotMatch m = CqEventLotLink.resolve('NOPE-9999');
        System.assertEquals(0, m.matches);
        System.assertEquals(null, m.partId);
    }

    @IsTest
    static void triggerLinksPartAndCompletesLotOnInsert() {
        Quality_Event__c ev = new Quality_Event__c(Title__c = 'Lot link test', Problem_Statement__c = 'test',
            Event_Type__c = 'Report', Status__c = 'Waiting for Review', Lot_Number__c = '0908');
        insert ev;
        ev = [SELECT Part__c, Lot_Number__c FROM Quality_Event__c WHERE Id = :ev.Id];
        System.assertEquals(partId(), ev.Part__c, 'before-insert linked the part from the lot');
        System.assertEquals('L26-0908', ev.Lot_Number__c, 'before-insert completed the lot number');
    }

    @IsTest
    static void triggerKeepsAChosenPart() {
        Quality_Event__c ev = new Quality_Event__c(Title__c = 'Chosen part', Problem_Statement__c = 'test',
            Event_Type__c = 'Report', Status__c = 'Waiting for Review', Lot_Number__c = '0908', Part__c = partId());
        insert ev;
        ev = [SELECT Part__c, Lot_Number__c FROM Quality_Event__c WHERE Id = :ev.Id];
        System.assertEquals(partId(), ev.Part__c);
        System.assertEquals('0908', ev.Lot_Number__c, 'a chosen part is left alone; the lot is not rewritten');
    }
}

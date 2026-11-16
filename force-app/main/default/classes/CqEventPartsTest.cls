@IsTest
private class CqEventPartsTest {
    @IsTest
    static void suggestsAndSearches() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Picker Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Picker Part', cqext__Title__c = 'Picker Part', compliancequest__Part_Number__c = 'PICK-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        insert new Quality_Event__c(Title__c = 'T', Problem_Statement__c = 'P', Event_Type__c = 'Report', Status__c = 'Waiting for Review', Part__c = part.Id);
        List<CqEventParts.Part> s = CqEventParts.suggested();
        System.assertEquals(1, s.size(), 'the part on the event is suggested');
        System.assertEquals('PICK-PART-1', s[0].partNumber);
        System.assertEquals(1, CqEventParts.search('PICK-PART').size(), 'search by number');
        System.assertEquals(1, CqEventParts.search('picker part').size(), 'search by name');
        System.assertEquals(0, CqEventParts.search('P').size(), 'one letter is too short');
    }
}

@IsTest
private class PhrLeadReportRenameTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Rename Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(
            Name = 'Rename Product', cqext__Title__c = 'Rename Product', compliancequest__Part_Number__c = 'RNM-OWN',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
    }

    @IsTest static void titlesAreTheNewNameAndTheOldOne() {
        Assert.areEqual('Interim Report', PhrLeadReportAction.FILE_TITLE);
        Assert.areEqual('Product History Lead Report', PhrLeadReportAction.OLD_FILE_TITLE);
    }

    @IsTest static void fileWithTheOldTitleIsFoundAndRolledForward() {
        compliancequest__SQX_Complaint__c cmp = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Rename complaint',
            compliancequest__Description__c = 'Rename complaint description',
            compliancequest__SQX_Part__c = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = 'LOT-RNM');
        insert cmp;
        ContentVersion old = new ContentVersion(
            Title = PhrLeadReportAction.OLD_FILE_TITLE, PathOnClient = 'old.pdf',
            VersionData = Blob.valueOf('old'), FirstPublishLocationId = cmp.Id);
        insert old;
        Id oldDoc = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :old.Id].ContentDocumentId;

        Assert.areEqual(oldDoc, PhrLeadReportAction.findExistingDocument(cmp.Id));
        Assert.areEqual(2, PhrLeadReportAction.nextVersion(oldDoc));

        PhrLeadReportAction.Request req = new PhrLeadReportAction.Request();
        req.recordId = cmp.Id;
        PhrLeadReportAction.Response r = PhrLeadReportAction.run(new List<PhrLeadReportAction.Request>{ req })[0];
        Assert.isTrue(r.success == true, r.message);
        Assert.areEqual(2, r.version);
        Assert.areEqual(oldDoc, r.contentDocumentId);
        Assert.areEqual('Interim Report', [SELECT Title FROM ContentDocument WHERE Id = :oldDoc].Title);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :cmp.Id
            AND ContentDocument.Title IN ('Interim Report', 'Product History Lead Report')]);
    }
}

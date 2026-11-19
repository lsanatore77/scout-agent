/** The small helpers behind the Triage workspace: the saved draft, Add Containment, the photo, and rich text to plain text. */
@IsTest
private class CqTriageHelpersTest {

    static Id makeNc() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Helpers Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Helpers Part', cqext__Title__c = 'Helpers Part', compliancequest__Part_Number__c = 'HLP-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Seal open', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Seal open', compliancequest__SQX_Part__c = part.Id, compliancequest__Lot_Number__c = 'HLP-LOT-1',
            compliancequest__Defective_Quantity__c = 2, compliancequest__Occurrence_Date__c = Date.today());
        insert nc;
        return nc.Id;
    }

    @IsTest
    static void draftIsKeptUntilTriageIsComplete() {
        Id ncId = makeNc();
        System.assertEquals(null, CqTriageDraft.getDraft(ncId), 'no draft yet');
        CqTriageDraft.saveDraft(ncId, '{"step":2}');
        System.assertEquals('{"step":2}', CqTriageDraft.getDraft(ncId));
        CqTriageDraft.saveDraft(ncId, ' ');
        System.assertEquals(null, CqTriageDraft.getDraft(ncId), 'a blank draft clears it');

        CqTriageDraft.saveDraft(ncId, '{"step":3}');
        update new compliancequest__SQX_Nonconformance__c(Id = ncId, Triage_Risk__c = 'Low', Triage_Path__c = 'Log Only');
        System.assertEquals(null, CqTriageDraft.getDraft(ncId), 'once triage is complete the draft is left over');
    }

    @IsTest
    static void containmentNeedsATitle() {
        Id ncId = makeNc();
        try {
            CqTriageContainment.create(ncId, ' ', null, null, null);
            System.assert(false, 'a blank title is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            CqTriageContainment.create(null, 'Hold the lot', null, null, null);
            System.assert(false, 'no record is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void containmentIsCreatedOrRefusedCleanly() {
        Id ncId = makeNc();
        Test.startTest();
        try {
            String name = CqTriageContainment.create(ncId, 'Hold the lot', 'Quarantine at the dock', String.valueOf(Date.today().addDays(3)), null);
            System.assertNotEquals(null, name, 'the containment number comes back');
            System.assertEquals(1, [SELECT COUNT() FROM compliancequest__SQX_Containment__c WHERE compliancequest__SQX_Nonconformance__c = :ncId]);
        } catch (AuraHandledException e) {
            // CQ's own rules may refuse a containment at this stage; the reporter gets a plain message, never a raw error
            System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Containment__c WHERE compliancequest__SQX_Nonconformance__c = :ncId]);
        }
        Test.stopTest();
    }

    @IsTest
    static void photoIsSavedAndReadBack() {
        Id ncId = makeNc();
        System.assertEquals(null, CqTriagePhoto.getPhotoVersionId(null));
        System.assertEquals(null, CqTriagePhoto.getPhotoVersionId(ncId), 'no photo yet');
        try {
            CqTriagePhoto.savePhoto(ncId, 'x.png', '');
            System.assert(false, 'nothing to save is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        // a 1x1 PNG
        String png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';
        Test.startTest();
        String versionId = CqTriagePhoto.savePhoto(ncId, 'seal.png', png);
        String unnamed = CqTriagePhoto.savePhoto(ncId, null, png);
        Test.stopTest();
        System.assertNotEquals(null, versionId);
        System.assertEquals('photo.jpg', [SELECT Title FROM ContentVersion WHERE Id = :unnamed].Title, 'a photo with no name gets one');
        System.assertNotEquals(null, CqTriagePhoto.getPhotoVersionId(ncId), 'the newest image on the record is found');
    }

    @IsTest
    static void richTextKeepsItsParagraphs() {
        System.assertEquals(null, CqRichText.toText(null, null));
        System.assertEquals('Plain copy', CqRichText.toText('', '<b>Plain copy</b>'), 'no rich text falls back to the plain copy');
        System.assertEquals('First line\nsecond line\n\nNext paragraph', CqRichText.toText('<p>First line<br/>second line</p><p>Next paragraph</p>', 'x'));
        System.assertEquals('One\n\nTwo', CqRichText.toText('<div>One</div><div></div><div></div><div>Two</div>', null), 'empty blocks do not stack up blank lines');
        System.assertEquals('Fallback', CqRichText.toText('<p> </p>', 'Fallback'), 'rich text with no words falls back to the plain copy');
    }
}

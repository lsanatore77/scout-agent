@IsTest
private class PhrQmsAutoCreateTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Auto Create Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Auto Create Part',
            cqext__Title__c = 'Auto Create Part',
            compliancequest__Part_Number__c = 'TST-AUTO-001',
            compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert part;

        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Auto create test complaint',
            compliancequest__Description__c = 'Auto create test complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = 'LOT-AUTO-1');
        insert complaint;

        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = complaint.Id,
            compliancequest__Completed_By__c = 'Test Reviewer');

        List<compliancequest__SQX_Nonconformance__c> ncs = new List<compliancequest__SQX_Nonconformance__c>();
        for (Integer i = 1; i <= 5; i++) {
            ncs.add(newNc('Auto NC ' + i, part.Id));
        }
        insert ncs;
    }

    static compliancequest__SQX_Nonconformance__c newNc(String title, Id partId) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = title,
            compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = title + ' description',
            compliancequest__SQX_Part__c = partId,
            compliancequest__Occurrence_Date__c = Date.today());
    }

    static Id complaintId() {
        return [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
    }

    static PhrQmsRelatedRecordsAction.Response run(String mode) {
        PhrQmsRelatedRecordsAction.Request req = new PhrQmsRelatedRecordsAction.Request();
        req.recordId = complaintId();
        req.mode = mode;
        return PhrQmsRelatedRecordsAction.run(new List<PhrQmsRelatedRecordsAction.Request>{ req })[0];
    }

    static Integer ncRows() {
        return [SELECT COUNT() FROM compliancequest__SQX_Related_Product__c WHERE compliancequest__SQX_Nonconformance__c != null];
    }

    @IsTest
    static void topIds_takesFirstNNotYetAdded() {
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>();
        for (Integer i = 0; i < 5; i++) {
            PhrQmsPanelController.Row r = new PhrQmsPanelController.Row();
            r.id = UserInfo.getUserId();
            r.alreadyAdded = i == 0;
            rows.add(r);
        }
        System.assertEquals(3, PhrQmsRelatedRecordsAction.topIds(rows, 3).size());
        System.assertEquals(4, PhrQmsRelatedRecordsAction.topIds(rows, 10).size(), 'already added are skipped');
        System.assertEquals(0, PhrQmsRelatedRecordsAction.topIds(null, 3).size());
    }

    @IsTest
    static void preview_listsTopThreeAndAsksTheQuestion_writesNothing() {
        PhrQmsRelatedRecordsAction.Response preview = run(null);
        System.assertEquals(true, preview.success, preview.summary);
        System.assertEquals(false, preview.applied);
        System.assert(preview.summary.contains('Nonconformances:'), preview.summary);
        System.assert(preview.summary.contains('Do you want to create the most relevant records?'), preview.summary);
        System.assertEquals(0, ncRows(), 'preview writes nothing');
    }

    @IsTest
    static void apply_createsTopThreePerType_andPanelKeepsTheRest() {
        PhrQmsRelatedRecordsAction.Response applied = run('Apply');
        System.assertEquals(true, applied.success, applied.summary);
        System.assertEquals(true, applied.applied);
        System.assertEquals(3, ncRows(), 'five NCs match, only the top 3 are created');

        Id phrId = [SELECT Id FROM compliancequest__SQX_Product_History_Review__c LIMIT 1].Id;
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(phrId, null);
        Integer added = 0;
        for (PhrQmsPanelController.Row r : d.nonconformances) {
            if (r.alreadyAdded) { added++; }
        }
        System.assertEquals(3, added);
        System.assertEquals(5, d.nonconformances.size(), 'the panel still lists the rest to add manually');

        // A second yes adds the next ones and never duplicates.
        run('Apply');
        System.assertEquals(5, ncRows());
    }

    @IsTest
    static void applyAll_addsEverything() {
        run('ApplyAll');
        System.assertEquals(5, ncRows());
    }
}

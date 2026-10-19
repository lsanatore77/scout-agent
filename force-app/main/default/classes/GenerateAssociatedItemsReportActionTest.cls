@isTest
private class GenerateAssociatedItemsReportActionTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Test Family');
        insert fam;

        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Test Primary Part',
            cqext__Title__c = 'Test Primary Part',
            compliancequest__Part_Number__c = 'TST-PRIMARY-001',
            compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual'
        );
        insert part;
    }

    private static compliancequest__SQX_Complaint__c makeComplaint() {
        compliancequest__SQX_Part__c part = [
            SELECT Id FROM compliancequest__SQX_Part__c
            WHERE compliancequest__Part_Number__c = 'TST-PRIMARY-001' LIMIT 1
        ];
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Test complaint',
            compliancequest__Description__c = 'Test complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today()
        );
        insert complaint;
        return complaint;
    }

    private static String errorText(GenerateAssociatedItemsReportAction.Response r) {
        return 'Action error: ' + r.errorMessage;
    }

    @isTest
    static void generateReport_attachesPdfToComplaint() {
        compliancequest__SQX_Complaint__c complaint = makeComplaint();

        GenerateAssociatedItemsReportAction.Request req = new GenerateAssociatedItemsReportAction.Request();
        req.targetRecordId = complaint.Id;
        req.reportTitle = 'Test Report';

        Test.startTest();
        List<GenerateAssociatedItemsReportAction.Response> results =
            GenerateAssociatedItemsReportAction.generateReport(
                new List<GenerateAssociatedItemsReportAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One response per request');
        System.assertEquals(true, results[0].success, errorText(results[0]));
        System.assertNotEquals(null, results[0].contentDocumentId, 'A ContentDocument was created');

        List<ContentDocumentLink> links = [
            SELECT Id FROM ContentDocumentLink
            WHERE LinkedEntityId = :complaint.Id
            AND ContentDocumentId = :results[0].contentDocumentId
        ];
        System.assertEquals(1, links.size(), 'The file is linked to the complaint');
    }

    @isTest
    static void generateReport_acceptsDateRangeAndLegacyIdLists() {
        compliancequest__SQX_Complaint__c complaint = makeComplaint();

        GenerateAssociatedItemsReportAction.Request req = new GenerateAssociatedItemsReportAction.Request();
        req.targetRecordId = complaint.Id;
        req.startDate = Date.today().addDays(-30);
        req.endDate = Date.today();
        // Inputs the existing Flow still passes; accepted and ignored.
        req.nonconformanceIds = new List<Id>();
        req.capaIds = new List<Id>();
        req.changeOrderIds = new List<Id>();
        req.inspectionIds = new List<Id>();

        Test.startTest();
        List<GenerateAssociatedItemsReportAction.Response> results =
            GenerateAssociatedItemsReportAction.generateReport(
                new List<GenerateAssociatedItemsReportAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(true, results[0].success, errorText(results[0]));
    }

    @isTest
    static void generateReport_withoutTargetRecord_returnsError() {
        GenerateAssociatedItemsReportAction.Request req = new GenerateAssociatedItemsReportAction.Request();

        Test.startTest();
        List<GenerateAssociatedItemsReportAction.Response> results =
            GenerateAssociatedItemsReportAction.generateReport(
                new List<GenerateAssociatedItemsReportAction.Request>{ req }
            );
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Missing target record is an error');
        System.assertNotEquals(null, results[0].errorMessage, 'An error message is returned');
    }
}

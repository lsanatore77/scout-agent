@isTest
private class AssociatedItemsReportActionTest {

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

    private static compliancequest__SQX_Part__c getPart() {
        return [SELECT Id FROM compliancequest__SQX_Part__c WHERE compliancequest__Part_Number__c = 'TST-PRIMARY-001' LIMIT 1];
    }

    // System.assertEquals throws if the message argument is null, so always
    // build a non-null message from the report's error text.
    private static String msg(AssociatedItemsReportData r) {
        return 'Report error: ' + r.errorMessage;
    }

    private static compliancequest__SQX_Complaint__c makeComplaint(Id partId, String lot) {
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Test complaint',
            compliancequest__Description__c = 'Test complaint description',
            compliancequest__SQX_Part__c = partId,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = lot
        );
        insert complaint;
        return complaint;
    }

    @isTest
    static void primaryPartIdOnly_returnsPartAndEmptyRelatedLists() {
        compliancequest__SQX_Part__c part = getPart();

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.primaryPartId = part.Id;
        req.reportTitle = 'Custom Title';

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, out.size());
        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertEquals('Custom Title', r.reportTitle);
        System.assertEquals(true, r.hasPrimaryPart);
        System.assertEquals(part.Id, r.primaryPart.id);
        System.assertEquals(0, r.nonconformances.size());
        System.assertEquals(0, r.capas.size());
        System.assertEquals(0, r.changeOrders.size());
        System.assertEquals(0, r.inspections.size());
    }

    @isTest
    static void targetRecordId_resolvesRelatedRecordsWithoutIdLists() {
        compliancequest__SQX_Part__c part = getPart();

        // Complaint pointing at the primary Part. The action must resolve
        // Nonconformances, CAPAs, Change Orders and Inspections itself --
        // none of the ID lists are supplied on the request.
        compliancequest__SQX_Complaint__c complaint = makeComplaint(part.Id, null);

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.targetRecordId = complaint.Id;

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertEquals('Associated Items Summary Report', r.reportTitle);
        System.assertEquals(true, r.hasPrimaryPart);
        System.assertEquals(part.Id, r.primaryPart.id);
        System.assertNotEquals(null, r.inspections);
        System.assertNotEquals(null, r.capas);
        System.assertNotEquals(null, r.changeOrders);
    }

    @isTest
    static void noPartResolved_returnsSuccessWithoutPrimaryPart() {
        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertEquals(false, r.hasPrimaryPart);
    }

    @isTest
    static void explicitIdLists_areUsedWhenNoTargetRecord() {
        // With no Target Record Id the supplied ID lists are the fallback.
        // Unknown/empty lists must not throw.
        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.nonconformanceIds = new List<Id>();
        req.capaIds = new List<Id>();
        req.changeOrderIds = new List<Id>();
        req.inspectionIds = new List<Id>();

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        System.assertEquals(true, out[0].report.success, msg(out[0].report));
    }

    @isTest
    static void complaintLotNumber_isEchoedInReport() {
        compliancequest__SQX_Part__c part = getPart();
        compliancequest__SQX_Complaint__c complaint = makeComplaint(part.Id, 'TEST-LOT-001');

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.targetRecordId = complaint.Id;

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertEquals('TEST-LOT-001', r.lotNumber, 'Lot Number should come from the Complaint');
        System.assertEquals(null, r.dateRangeLabel, 'No date range was supplied');
        System.assertNotEquals(null, r.nonconformances);
        System.assertNotEquals(null, r.inspections);
    }

    @isTest
    static void dateRange_isAppliedAndLabelled() {
        compliancequest__SQX_Part__c part = getPart();
        compliancequest__SQX_Complaint__c complaint = makeComplaint(part.Id, 'TEST-LOT-002');

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.targetRecordId = complaint.Id;
        req.startDate = Date.today().addDays(-30);
        req.endDate = Date.today().addDays(1);

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertNotEquals(null, r.dateRangeLabel, 'Range label should be set');
        System.assert(r.dateRangeLabel.contains(' to '), 'Both ends supplied: ' + r.dateRangeLabel);
    }

    @isTest
    static void reversedDateRange_isSwappedNotRejected() {
        compliancequest__SQX_Part__c part = getPart();

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.primaryPartId = part.Id;
        req.startDate = Date.today();
        req.endDate = Date.today().addDays(-10);

        Test.startTest();
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        Test.stopTest();

        AssociatedItemsReportData r = out[0].report;
        System.assertEquals(true, r.success, msg(r));
        System.assertNotEquals(null, r.dateRangeLabel, 'Range label should be set');
    }

    @isTest
    static void matchedBy_labelsPartLotAndBoth() {
        System.assertEquals('Part', AssociatedItemsReportAction.matchedBy(true, false), 'part only');
        System.assertEquals('Lot', AssociatedItemsReportAction.matchedBy(false, true), 'lot only');
        System.assertEquals('Part and Lot', AssociatedItemsReportAction.matchedBy(true, true), 'both');
        System.assertEquals(null, AssociatedItemsReportAction.matchedBy(false, false), 'neither');
    }

    @isTest
    static void dateBoundsAndLabels_handleOpenEndedRanges() {
        Date d = Date.newInstance(2026, 3, 15);

        System.assertEquals(Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)),
            AssociatedItemsReportAction.rangeStart(d), 'start is midnight of Start Date');
        System.assertEquals(Datetime.newInstance(d.addDays(1), Time.newInstance(0, 0, 0, 0)),
            AssociatedItemsReportAction.rangeEnd(d), 'end is exclusive midnight after End Date');
        System.assert(AssociatedItemsReportAction.rangeStart(null) < Datetime.newInstance(2000, 1, 1), 'open start');
        System.assert(AssociatedItemsReportAction.rangeEnd(null) > Datetime.newInstance(3000, 1, 1), 'open end');

        System.assertEquals(null, AssociatedItemsReportAction.buildDateRangeLabel(null, null), 'no range');
        System.assert(AssociatedItemsReportAction.buildDateRangeLabel(d, null).startsWith('On or after'), 'start only');
        System.assert(AssociatedItemsReportAction.buildDateRangeLabel(null, d).startsWith('On or before'), 'end only');
    }

    @isTest
    static void lotMatchLabel_describesCounts() {
        System.assertEquals('None', AssociatedItemsReportAction.lotMatchLabel(0, 0), 'no records');
        System.assertEquals('None', AssociatedItemsReportAction.lotMatchLabel(null, null), 'null counts');
        System.assertEquals('Lot · 1 NC', AssociatedItemsReportAction.lotMatchLabel(1, 0), 'one NC');
        System.assertEquals('Lot · 2 NCs, 1 inspection', AssociatedItemsReportAction.lotMatchLabel(2, 1), 'mixed');
        System.assertEquals('Lot · 3 inspections', AssociatedItemsReportAction.lotMatchLabel(0, 3), 'inspections only');
    }

    @isTest
    static void isOwnInvestigation_matchesComplaintOrSourceId() {
        Id complaintId = '001000000000001AAA';
        Id otherId = '001000000000002AAA';
        System.assertEquals(true, AssociatedItemsReportAction.isOwnInvestigation(complaintId, complaintId, null), 'complaint lookup');
        System.assertEquals(true, AssociatedItemsReportAction.isOwnInvestigation(complaintId, null, '001000000000001'), '15 char source id');
        System.assertEquals(true, AssociatedItemsReportAction.isOwnInvestigation(complaintId, null, String.valueOf(complaintId)), '18 char source id');
        System.assertEquals(false, AssociatedItemsReportAction.isOwnInvestigation(complaintId, otherId, '001000000000002'), 'other complaint');
        System.assertEquals(false, AssociatedItemsReportAction.isOwnInvestigation(null, otherId, null), 'no complaint');
    }
}

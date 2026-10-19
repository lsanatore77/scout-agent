@isTest
private class ComplaintReportPDFControllerTest {

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

    private static compliancequest__SQX_Complaint__c makeComplaint(String lot, String summary) {
        compliancequest__SQX_Part__c part = [
            SELECT Id FROM compliancequest__SQX_Part__c
            WHERE compliancequest__Part_Number__c = 'TST-PRIMARY-001' LIMIT 1
        ];
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Valve leaking',
            compliancequest__Description__c = 'Valve housing leaking at the inlet port',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = lot,
            Draft_Investigation_Summaries__c = summary
        );
        insert complaint;
        return complaint;
    }

    private static ComplaintReportPDFController build(Map<String, String> params) {
        PageReference ref = Page.ComplaintInvestigationReportPDF;
        for (String key : params.keySet()) {
            ref.getParameters().put(key, params.get(key));
        }
        Test.setCurrentPage(ref);
        return new ComplaintReportPDFController();
    }

    private static String errorText(ComplaintReportPDFController c) {
        return 'Controller error: ' + c.errorMessage;
    }

    @isTest
    static void noId_showsErrorAndNoComplaint() {
        ComplaintReportPDFController c = build(new Map<String, String>());
        System.assertEquals(false, c.hasComplaint, 'No complaint without an id');
        System.assertEquals(true, c.getHasError(), 'An error message is shown');
        System.assertEquals('pdf', c.renderAs, 'Default render is PDF');
    }

    @isTest
    static void formatHtml_rendersWithoutPdf() {
        ComplaintReportPDFController c = build(new Map<String, String>{ 'format' => 'html' });
        System.assertEquals(null, c.renderAs, 'HTML preview has no renderAs');
    }

    @isTest
    static void complaint_loadsSummaryLotRangeAndPart() {
        compliancequest__SQX_Complaint__c complaint = makeComplaint(
            'TEST-LOT-1',
            '<p>Complaint COM-0000000001 was reviewed.</p><ul><li>See NC-000067 and CAPA-000000.</li></ul>'
        );

        ComplaintReportPDFController c = build(new Map<String, String>{
            'id' => String.valueOf(complaint.Id),
            'startDate' => String.valueOf(Date.today().addDays(-30)),
            'endDate' => String.valueOf(Date.today().addDays(1))
        });

        System.assertEquals(true, c.hasComplaint, errorText(c));
        System.assertEquals(false, c.getHasError(), errorText(c));
        System.assertEquals(true, c.hasSummary, 'Saved summary should be loaded');
        System.assertEquals(1, c.summaryParagraphs.size(), 'Rich text is rendered as one block');
        System.assert(c.summaryParagraphs[0].contains('<ul><li>'), 'List formatting is kept');
        System.assertEquals('TEST-LOT-1', c.lotNumber, 'Lot comes from the complaint');
        System.assertEquals(true, c.getHasLot(), 'Lot flag');
        System.assertEquals(true, c.getHasDateRange(), 'Range label should be set');
        System.assertEquals(true, c.hasPrimaryPart, 'Primary part resolved');
        System.assertEquals('TST-PRIMARY-001', c.partNumber, 'Part number');
        System.assertEquals(false, c.getHasRelevantNcs(), 'No NCs, so no relevant NCs');
        System.assertNotEquals(null, c.taskSummary, 'Task summary is always populated');
        System.assertEquals(false, c.getHasTasks(), 'No CQ Tasks on the test complaint');
        System.assertEquals(false, c.getHasOverdueTasks(), 'No overdue tasks');
        System.assertEquals(false, c.getHasInvestigations(), 'No related investigations');
        System.assertEquals(true, c.getHasLotMatchColumn(), 'Lot match column shows when the complaint has a lot');
    }

    @isTest
    static void complaintWithoutSummary_hasNoSummary() {
        compliancequest__SQX_Complaint__c complaint = makeComplaint(null, null);
        ComplaintReportPDFController c = build(new Map<String, String>{ 'id' => String.valueOf(complaint.Id) });
        System.assertEquals(true, c.hasComplaint, errorText(c));
        System.assertEquals(false, c.hasSummary, 'No saved summary');
        System.assertEquals(false, c.getHasLot(), 'No lot');
    }

    @isTest
    static void summaryToHtml_splitsParagraphsEscapesAndBoldsRecordNumbers() {
        List<String> out = ComplaintReportPDFController.summaryToHtml(
            'First <b>para</b> about COM-0000000001.\nSecond line of it.\n\nSecond para: NC-000067, CAPA-000000, CHG-000000, PHR-000001, INS-0000000001.'
        );
        System.assertEquals(2, out.size(), 'Blank line splits paragraphs');
        System.assert(out[0].contains('&lt;b&gt;'), 'HTML is escaped: ' + out[0]);
        System.assert(!out[0].contains('<b>'), 'No raw tags: ' + out[0]);
        System.assert(out[0].contains('<strong>COM-0000000001</strong>'), 'Complaint number bold: ' + out[0]);
        System.assert(out[0].contains('<br/>'), 'Single newline kept as a break: ' + out[0]);
        for (String num : new List<String>{ 'NC-000067', 'CAPA-000000', 'CHG-000000', 'PHR-000001', 'INS-0000000001' }) {
            System.assert(out[1].contains('<strong>' + num + '</strong>'), num + ' bold: ' + out[1]);
        }
        System.assertEquals(0, ComplaintReportPDFController.summaryToHtml(null).size(), 'Null summary');
        System.assertEquals(0, ComplaintReportPDFController.summaryToHtml('  ').size(), 'Blank summary');
    }

    @isTest
    static void parseHelpers_toleratesBadInput() {
        System.assertEquals(null, ComplaintReportPDFController.parseId('not-an-id'), 'bad id');
        System.assertEquals(null, ComplaintReportPDFController.parseId(null), 'null id');
        System.assertEquals(null, ComplaintReportPDFController.parseDate('13/45/2026'), 'bad date');
        System.assertEquals(Date.newInstance(2026, 3, 15), ComplaintReportPDFController.parseDate('2026-03-15'), 'good date');
    }

    @isTest
    static void termsAndScoring_rankRealSignals() {
        Set<String> complaint = ComplaintReportPDFController.tokens('Valve housing leaking at the inlet port');
        Set<String> nc = ComplaintReportPDFController.tokens('Thread damage on Valve Housing inlet port');
        List<String> shared = ComplaintReportPDFController.sharedTerms(complaint, nc);
        System.assert(shared.contains('valve'), 'shared valve: ' + shared);
        System.assert(shared.contains('inlet'), 'shared inlet: ' + shared);
        System.assertEquals(0, ComplaintReportPDFController.tokens(null).size(), 'null text');

        System.assertEquals(4 + 3 + 2 + 1 + 1, ComplaintReportPDFController.score(true, true, 5, true, true), 'all signals, shared capped at 2');
        System.assertEquals(2, ComplaintReportPDFController.score(false, false, 0, true, true), 'open + primary only');
        System.assertEquals(3, ComplaintReportPDFController.score(false, true, 0, false, false), 'named only');

        String why = ComplaintReportPDFController.buildWhy(true, true, shared, 'Open', true);
        System.assert(why.contains('Lot number matches the complaint'), why);
        System.assert(why.contains('Named in the investigation summary'), why);
        System.assert(why.contains('Shares terms with the complaint'), why);
        System.assert(why.contains('Open'), why);
        System.assert(why.contains('Filed against the primary part'), why);
    }

    @isTest
    static void ncRows_sortByScoreThenSummaryOrderThenNewest() {
        ComplaintReportPDFController.NcRow a = new ComplaintReportPDFController.NcRow();
        a.name = 'NC-000001'; a.score = 5; a.mentionPos = 10;
        ComplaintReportPDFController.NcRow b = new ComplaintReportPDFController.NcRow();
        b.name = 'NC-000002'; b.score = 5; b.mentionPos = 3;
        ComplaintReportPDFController.NcRow c = new ComplaintReportPDFController.NcRow();
        c.name = 'NC-000003'; c.score = 2; c.mentionPos = -1;
        ComplaintReportPDFController.NcRow d = new ComplaintReportPDFController.NcRow();
        d.name = 'NC-000004'; d.score = 2; d.mentionPos = -1;

        List<ComplaintReportPDFController.NcRow> rows = new List<ComplaintReportPDFController.NcRow>{ c, a, d, b };
        rows.sort();
        System.assertEquals('NC-000002', rows[0].name, 'Higher score, earlier in summary');
        System.assertEquals('NC-000001', rows[1].name, 'Same score, later in summary');
        System.assertEquals('NC-000004', rows[2].name, 'Tie goes to the newer NC');
        System.assertEquals('NC-000003', rows[3].name, 'Lowest');
    }

    @isTest
    static void richSummaryToHtml_sanitizesAndHandlesBlank() {
        System.assertEquals(0, ComplaintReportPDFController.richSummaryToHtml(null).size());
        System.assertEquals(0, ComplaintReportPDFController.richSummaryToHtml('<p> </p>').size());
        List<String> out = ComplaintReportPDFController.richSummaryToHtml('<p onclick="x()">A&nbsp;<b>B</b></p><script>x</script>');
        System.assertEquals(1, out.size());
        System.assertEquals('<p>A&#160;<b>B</b></p>', out[0]);
    }
}

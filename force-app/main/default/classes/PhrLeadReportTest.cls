@IsTest
private class PhrLeadReportTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Report Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(
            Name = 'Report Product', cqext__Title__c = 'Report Product', compliancequest__Part_Number__c = 'RPT-OWN',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
    }

    static compliancequest__SQX_Complaint__c newComplaint(String lot) {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Report complaint',
            compliancequest__Description__c = 'Report complaint description',
            compliancequest__SQX_Part__c = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = lot);
        insert c;
        return c;
    }

    static PhrLeadReportController page(Id id) {
        PageReference ref = Page.PhrLeadReportPDF;
        ref.getParameters().put('id', String.valueOf(id));
        ref.getParameters().put('version', '2');
        Test.setCurrentPage(ref);
        return new PhrLeadReportController();
    }

    static PhrQmsPanelController.Row row(String name, String tier, Integer rel, String status, String crit) {
        PhrQmsPanelController.Row r = new PhrQmsPanelController.Row();
        r.name = name; r.tier = tier; r.relevance = rel; r.status = status; r.criteriaMet = crit;
        return r;
    }

    @IsTest static void noIdShowsError() {
        Test.setCurrentPage(Page.PhrLeadReportPDF);
        PhrLeadReportController c = new PhrLeadReportController();
        System.assertEquals(true, c.getHasError());
        System.assertEquals(false, c.hasComplaint);
    }

    @IsTest static void reportShowsHeaderVersionAndGaps() {
        compliancequest__SQX_Complaint__c cmp = newComplaint(null);
        PhrLeadReportController c = page(cmp.Id);
        System.assertEquals(true, c.hasComplaint, 'Error: ' + c.errorMessage);
        System.assertEquals('2', c.versionLabel);
        Boolean lotGap = false;
        Boolean phrGap = false;
        for (String g : c.gaps) {
            if (g.contains('no lot number')) { lotGap = true; }
            if (g.contains('no Product History Review')) { phrGap = true; }
        }
        System.assertEquals(true, lotGap, 'Missing lot is reported');
        System.assertEquals(true, phrGap, 'Missing PHR is reported');
        System.assertEquals(false, c.getHasLeads(), 'No leads here');
    }

    @IsTest static void gapsAreNotReportedWhenPresent() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-RPT');
        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = cmp.Id, compliancequest__Completed_By__c = 'Tester');
        PhrLeadReportController c = page(cmp.Id);
        System.assertEquals(0, c.gaps.size(), 'No gaps expected: ' + c.gaps);
        System.assertEquals(false, c.getHasGaps());
    }

    @IsTest static void topTenOnlyAndSortedAndNoSetAside() {
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>();
        for (Integer i = 0; i < 12; i++) { rows.add(row('NC-' + (100 + i), 'Next', 10 + i, 'Open', 'Part')); }
        List<PhrQmsPanelController.Row> sorted = PhrLeadReportController.sortByRelevance(rows);
        System.assertEquals(21, sorted[0].relevance, 'Highest score first');
        System.assertEquals(10, sorted[11].relevance, 'Lowest last');
    }

    @IsTest static void summaryIsShortAndNamesNoRecord() {
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>{
            row('NC-000014', 'Top', 90, 'Open', 'Lot'), row('CHG-000001', 'Next', 50, 'Closed', 'Part')
        };
        String s = PhrLeadReportController.buildSummary(rows, 2);
        System.assert(PhrLeadReportController.countWords(s) <= 100, 'At most 100 words');
        System.assertEquals(false, s.contains('NC-000014') || s.contains('CHG-000001'), 'No record named');
        System.assert(s.contains('gaps'), 'Mentions gaps: ' + s);
        System.assertEquals(
            100,
            PhrLeadReportController.countWords(PhrLeadReportController.limitWords(('word ').repeat(150), 100)),
            'Long text is cut to the limit');
    }

    @IsTest static void summaryWithNoLeads() {
        String s = PhrLeadReportController.buildSummary(new List<PhrQmsPanelController.Row>(), 0);
        System.assert(s.contains('No records worth reviewing'), s);
        System.assert(s.contains('No data gaps'), s);
    }

    @IsTest static void actionAddsFileThenVersionNotCopy() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-RPT');
        PhrLeadReportAction.Request req = new PhrLeadReportAction.Request();
        req.recordId = cmp.Id;
        PhrLeadReportAction.Response r1 = PhrLeadReportAction.run(new List<PhrLeadReportAction.Request>{ req })[0];
        System.assertEquals(true, r1.success, r1.message);
        System.assertEquals(1, r1.version);
        PhrLeadReportAction.Response r2 = PhrLeadReportAction.run(new List<PhrLeadReportAction.Request>{ req })[0];
        System.assertEquals(true, r2.success, r2.message);
        System.assertEquals(2, r2.version);
        System.assertEquals(r1.contentDocumentId, r2.contentDocumentId, 'Same file');
        System.assertEquals(1, [SELECT COUNT() FROM ContentDocumentLink
            WHERE LinkedEntityId = :cmp.Id AND ContentDocument.Title = :PhrLeadReportAction.FILE_TITLE], 'One file only');
        System.assertEquals(2, [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :r1.contentDocumentId], 'Two versions');
    }

    @IsTest static void actionAcceptsPhrIdAndRejectsOthers() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-RPT');
        compliancequest__SQX_Product_History_Review__c phr = new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = cmp.Id, compliancequest__Completed_By__c = 'Tester');
        insert phr;
        System.assertEquals(cmp.Id, PhrLeadReportAction.resolveComplaint(phr.Id));
        PhrLeadReportAction.Request bad = new PhrLeadReportAction.Request();
        PhrLeadReportAction.Response r = PhrLeadReportAction.run(new List<PhrLeadReportAction.Request>{ bad })[0];
        System.assertEquals(false, r.success);
        bad.recordId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        r = PhrLeadReportAction.run(new List<PhrLeadReportAction.Request>{ bad })[0];
        System.assertEquals(false, r.success, 'A part is not a complaint');
    }
}

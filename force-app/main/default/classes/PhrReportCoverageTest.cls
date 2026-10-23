/**
 * Covers the parts of the PDF report and the PHR Summary generator that need data the other
 * tests do not create: rows for every table, task progress, an Id-style template setting,
 * saving straight from the generator, and all summary sections turned off.
 */
@IsTest
private class PhrReportCoverageTest {

    static compliancequest__SQX_Complaint_Task__c task(String name, String status, Date due, Date done) {
        compliancequest__SQX_Complaint_Task__c t = new compliancequest__SQX_Complaint_Task__c(
            Name = name, compliancequest__Step__c = 1, compliancequest__Status__c = status,
            compliancequest__Start_Date__c = Date.today().addDays(-10),
            compliancequest__Due_Date__c = due, compliancequest__Completion_Date__c = done);
        return t;
    }

    /** Report data with every table filled, without touching the database. */
    static PhrReportData fullData() {
        PhrReportData d = new PhrReportData();
        d.hasComplaint = true;
        d.complaintName = 'COM-TEST';
        d.phrName = 'PHR-TEST';
        d.partLabel = 'Valve (V-1)';
        d.lotNumber = 'LOT-1';
        d.reportedDate = 'Oct 1, 2026';
        d.overallScore = 72;
        d.overallRating = 'High';
        d.reasons = new List<String>{ 'The complaint lot appears on 2 other records', '3 records are still open' };
        d.summaryText = 'Review the 2 most relevant records first.';
        d.summaryWords = 8;
        d.draftSummaryHtml = '<p>Summary text</p>';
        for (Integer i = 0; i < 2; i++) {
            PhrReportData.LeadRow r = new PhrReportData.LeadRow();
            r.colour = 'Red'; r.colourClass = 'c-red'; r.score = 80 - i; r.recordType = 'Nonconformance';
            r.name = 'NC-00' + i; r.title = 'Leak ' + i; r.status = 'Open'; r.createdDate = 'Oct 1, 2026'; r.matchedOn = 'Lot';
            d.leadRows.add(r);
        }
        d.totalLeads = 12;
        PhrReportData.InvRow inv = new PhrReportData.InvRow();
        inv.name = 'INV-001'; inv.status = 'Open'; inv.matchedBy = 'Linked'; inv.createdDate = 'Oct 2, 2026';
        d.investigationRows.add(inv);
        d.taskSummary = ComplaintTaskProgress.summarize(new List<compliancequest__SQX_Complaint_Task__c>{
            task('Triage', 'Complete', Date.today().addDays(-5), Date.today().addDays(-6)),
            task('Investigate', 'Open', Date.today().addDays(-2), null),
            task('Review', 'Draft', Date.today().addDays(5), null)
        }, Date.today());
        d.gaps.add('The Product History Review is a draft and Completed By is empty.');
        return d;
    }

    static final String ALL_BLOCKS = '<html xmlns="http://www.w3.org/1999/xhtml"><body>'
        + '<h1>{{reportTitle}}</h1><div>{{reasonRows}}</div><div>{{leadBlock}}</div><div>{{progressBlock}}</div>'
        + '<div>{{investigationBlock}}</div><div>{{gapBlock}}</div><div>{{draftSummaryBlock}}</div>'
        + '<div>{{errorBlock}}</div></body></html>';

    @IsTest static void everyTableIsFilled() {
        String out = PhrReportRenderer.fill(ALL_BLOCKS, fullData(), false);
        System.assertNotEquals(null, out);
        System.assert(out.contains('NC-001'), out);
        System.assert(out.contains('Showing the top 2 of 12 records worth reviewing.'), out);
        System.assert(out.contains('Tasks on this complaint (3)'), out);
        System.assert(out.contains('overdue'), out);
        System.assert(out.contains('INV-001'), out);
        System.assert(out.contains('Scored without:'), out);
        System.assert(out.contains('3 records are still open'), out);
        System.assert(!out.toLowerCase().contains('lead'), out);
    }

    @IsTest static void emptyTablesSaySo() {
        PhrReportData d = new PhrReportData();
        d.hasComplaint = true;
        d.taskSummary = ComplaintTaskProgress.summarize(new List<compliancequest__SQX_Complaint_Task__c>(), Date.today());
        String out = PhrReportRenderer.fill(ALL_BLOCKS, d, false);
        System.assert(out.contains('No records worth reviewing were found.'), out);
        System.assert(out.contains('No CQ Tasks are recorded on this complaint.'), out);
        System.assert(out.contains('No data gaps were found.'), out);
        System.assert(out.contains('No records worth reviewing to base a rating on.'), out);
        System.assert(out.contains('No PHR Summary has been saved yet.'), out);
    }

    @IsTest static void allRowsFitShowsTheCount() {
        PhrReportData d = fullData();
        d.leadRows.remove(1);
        d.totalLeads = 1;
        String out = PhrReportRenderer.fill(ALL_BLOCKS, d, false);
        System.assert(out.contains('Showing 1 record worth reviewing.'), out);
    }

    @IsTest static void withoutAComplaintOnlyTheErrorShows() {
        PhrReportData d = fullData();
        d.hasComplaint = false;
        d.errorMessage = 'No complaint was specified for this report.';
        String out = PhrReportRenderer.fill(ALL_BLOCKS, d, false);
        System.assert(out.contains('No complaint was specified'), out);
        System.assert(!out.contains('NC-001'), out);
    }

    @IsTest static void plainDraftAndFullPdf() {
        PhrReportData d = fullData();
        String plain = PhrReportRenderer.fill(ALL_BLOCKS, d, true);
        System.assert(plain.contains('Summary text'), plain);
        System.assert(!plain.contains('<p>Summary text</p>'), plain);
        PhrReportRenderer.Result r = PhrReportRenderer.render(d);
        System.assertNotEquals(null, r.pdf);
    }

    @IsTest static void aTemplateSetByRecordIdIsLookedUpById() {
        String fakeId = compliancequest__SQX_Controlled_Document__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000';
        System.assertEquals(true, PhrReportRenderer.isControlledDocumentId(fakeId));
        PhrReportSettings.Values v = new PhrReportSettings.Values();
        v.templateDocument = fakeId;
        PhrReportSettings.testValues = v;
        PhrReportRenderer.TemplateLookup lk = PhrReportRenderer.findControlledTemplate();
        System.assertEquals(null, lk.text);
        System.assert(lk.problem != null && lk.problem.contains(fakeId), lk.problem);
    }

    // ---------- GenerateDraftInvestigationSummary ----------

    static compliancequest__SQX_Complaint__c complaint() {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Hub separated from shaft',
            compliancequest__Description_As_Reported__c = 'Hub separated from shaft',
            compliancequest__Country_of_Origin__c = 'US');
        insert c;
        return c;
    }

    @IsTest static void generatingCanSaveStraightAway() {
        compliancequest__SQX_Complaint__c c = complaint();
        GenerateDraftInvestigationSummary.mockResponse = '### Complaint Overview\nHub separated.';
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = c.Id;
        req.saveToRecord = true;
        Test.startTest();
        GenerateDraftInvestigationSummary.Result r = GenerateDraftInvestigationSummary.generate(
            new List<GenerateDraftInvestigationSummary.Request>{ req })[0];
        Test.stopTest();
        System.assertEquals(true, r.saved, r.message);
        String saved = [SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :c.Id]
            .Draft_Investigation_Summaries__c;
        System.assert(saved != null && saved.contains('Hub separated'), saved);
    }

    @IsTest static void noSectionsTurnedOnGivesNoSummary() {
        compliancequest__SQX_Complaint__c c = complaint();
        PhrReportSettings.Values v = new PhrReportSettings.Values();
        v.summaryOverview = false;
        v.summaryAssociatedItems = false;
        v.summaryAnalysis = false;
        PhrReportSettings.testValues = v;
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = c.Id;
        GenerateDraftInvestigationSummary.Result r = GenerateDraftInvestigationSummary.generate(
            new List<GenerateDraftInvestigationSummary.Request>{ req })[0];
        System.assertEquals(null, r.summary);
        System.assert(r.message.contains('No summary sections are turned on'), r.message);
    }
}

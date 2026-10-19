@IsTest
private class PhrWindowAndSectionsTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Win Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Win Part', cqext__Title__c = 'Win Part', compliancequest__Part_Number__c = 'WIN-001',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        insert new compliancequest__SQX_Lot_Info__c(
            Name = 'LOT-WIN-1', compliancequest__Part_Number__c = 'WIN-001',
            compliancequest__Manufacturing_Date__c = Date.today());
        insert new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Window complaint',
            compliancequest__Description__c = 'Window complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = 'LOT-WIN-1');
        insert new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'No lot info complaint',
            compliancequest__Description__c = 'No lot info complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today());
        List<compliancequest__SQX_Nonconformance__c> ncs = new List<compliancequest__SQX_Nonconformance__c>{
            newNc('Recent window NC', part.Id), newNc('Old window NC', part.Id)
        };
        insert ncs;
        Test.setCreatedDate(ncs[1].Id, Datetime.now().addDays(-400));
    }

    static compliancequest__SQX_Nonconformance__c newNc(String title, Id partId) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = title, compliancequest__Type__c = 'Internal',
            compliancequest__Type_Of_Issue__c = 'Product', compliancequest__Description__c = title + ' description',
            compliancequest__SQX_Part__c = partId, compliancequest__Occurrence_Date__c = Date.today());
    }

    static compliancequest__SQX_Complaint__c withLotInfo() {
        return [SELECT Id FROM compliancequest__SQX_Complaint__c WHERE compliancequest__Lot_Number__c = 'LOT-WIN-1' LIMIT 1];
    }

    static compliancequest__SQX_Complaint__c withoutLotInfo() {
        return [SELECT Id FROM compliancequest__SQX_Complaint__c WHERE compliancequest__Lot_Number__c = null LIMIT 1];
    }

    static void linkLotInfo() {
        compliancequest__SQX_Complaint__c c = withLotInfo();
        c.compliancequest__SQX_Lot_Info__c = [SELECT Id FROM compliancequest__SQX_Lot_Info__c LIMIT 1].Id;
        update c;
    }

    static Integer ncCount(PhrQmsPanelController.PanelData d) {
        Integer n = d.nonconformances.size();
        for (PhrQmsPanelController.Row r : d.setAside) { if (r.recordType == 'Nonconformance') { n++; } }
        return n;
    }

    static PhrReportSettings.Values window(Boolean enabled, Integer after, Integer before) {
        PhrReportSettings.Values v = new PhrReportSettings.Values();
        v.useWindow = enabled; v.daysAfter = after; v.daysBefore = before;
        return v;
    }

    // ---------- Settings ----------

    @IsTest static void defaultsApplyWhenNothingIsConfigured() {
        PhrReportSettings.Values v = PhrReportSettings.get();
        System.assertEquals(false, v.useWindow);
        System.assertEquals(90, v.daysAfter);
        System.assertEquals(30, v.daysBefore);
        System.assertEquals(true, v.summaryOverview);
        System.assertEquals(true, v.summaryAssociatedItems);
        System.assertEquals(true, v.summaryAnalysis);
    }

    @IsTest static void windowBoundsUseTheDaysAndStayWideWhenOff() {
        Date mfg = Date.newInstance(2026, 6, 15);
        PhrReportSettings.Values winOn = window(true, 90, 30);
        System.assertEquals(Datetime.newInstance(Date.newInstance(2026, 5, 16), Time.newInstance(0, 0, 0, 0)), PhrReportSettings.windowStart(winOn, mfg));
        System.assertEquals(Datetime.newInstance(Date.newInstance(2026, 9, 14), Time.newInstance(0, 0, 0, 0)), PhrReportSettings.windowEnd(winOn, mfg));
        PhrReportSettings.Values winOff = window(false, 90, 30);
        System.assertEquals(Datetime.newInstance(1900, 1, 1), PhrReportSettings.windowStart(winOff, mfg));
        System.assertEquals(Datetime.newInstance(2999, 1, 1), PhrReportSettings.windowEnd(winOff, mfg));
        System.assertEquals(Datetime.newInstance(1900, 1, 1), PhrReportSettings.windowStart(winOn, null), 'No date: no window');
    }

    // ---------- Date window in the relevance package ----------

    @IsTest static void windowOffKeepsOldAndRecentRecords() {
        linkLotInfo();
        PhrReportSettings.testValues = window(false, 90, 30);
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(withLotInfo().Id, null);
        System.assertEquals(true, d.success, 'Error: ' + d.errorMessage);
        System.assertEquals(2, ncCount(d), 'Both nonconformances are considered');
        System.assertEquals(null, d.windowNote);
    }

    @IsTest static void windowOnDropsRecordsOutsideTheWindow() {
        linkLotInfo();
        PhrReportSettings.testValues = window(true, 90, 30);
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(withLotInfo().Id, null);
        System.assertEquals(true, d.success, 'Error: ' + d.errorMessage);
        System.assertEquals(1, ncCount(d), 'Only the recent nonconformance is inside the window');
        System.assert(d.windowNote != null && d.windowNote.contains('Only records created from'), 'Note: ' + d.windowNote);
    }

    @IsTest static void windowOnWithoutLotInfoIsSkippedWithANote() {
        PhrReportSettings.testValues = window(true, 90, 30);
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(withoutLotInfo().Id, null);
        System.assertEquals(true, d.success, 'Error: ' + d.errorMessage);
        System.assertEquals(2, ncCount(d), 'No window without a manufactured date');
        System.assert(d.windowNote.contains('was not applied'), 'Note: ' + d.windowNote);
    }

    @IsTest static void typedLotSkipsTheWindow() {
        linkLotInfo();
        PhrReportSettings.testValues = window(true, 90, 30);
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(withLotInfo().Id, 'SOME-OTHER-LOT');
        System.assertEquals(true, d.success, 'Error: ' + d.errorMessage);
        System.assertEquals(2, ncCount(d), 'A typed lot ignores the complaint manufactured date');
        System.assert(d.windowNote.contains('different lot'), 'Note: ' + d.windowNote);
    }

    @IsTest static void reportShowsAGapWhenTheWindowCannotApply() {
        PhrReportSettings.testValues = window(true, 90, 30);
        PhrReportData data = PhrReportData.build(withoutLotInfo().Id, '1');
        Boolean found = false;
        for (String g : data.gaps) { if (g.contains('was not applied')) { found = true; } }
        System.assertEquals(true, found, 'Gaps: ' + data.gaps);
    }

    @IsTest static void missingDataCheckMentionsTheWindowOnlyWhenOn() {
        linkLotInfo();
        PhrReportSettings.testValues = window(false, 90, 30);
        PhrMissingDataResult off = PhrMissingDataAction.check(withLotInfo().Id);
        for (PhrMissingCheck k : off.checks) { System.assertNotEquals('Manufacture date window', k.label); }

        PhrReportSettings.testValues = window(true, 90, 30);
        PhrMissingDataResult okRes = PhrMissingDataAction.check(withLotInfo().Id);
        PhrMissingDataResult warnRes = PhrMissingDataAction.check(withoutLotInfo().Id);
        String okStatus; String warnStatus;
        for (PhrMissingCheck k : okRes.checks) { if (k.label == 'Manufacture date window') { okStatus = k.status; } }
        for (PhrMissingCheck k : warnRes.checks) { if (k.label == 'Manufacture date window') { warnStatus = k.status; } }
        System.assertEquals('ok', okStatus);
        System.assertEquals('warn', warnStatus);
    }

    // ---------- Summary sections ----------

    static final String MD = '## Complaint Overview\nOverview text.\n\n## Associated Items\nItems text.\n\n## Analysis and Next Steps\nNext text.';
    static final String HTML = '<h3><strong>Complaint Overview</strong></h3><p>Overview text.</p>'
        + '<p><strong>Associated Items</strong> Items text.</p><h3>Analysis and Next Steps</h3><p>Next text.</p>';

    static PhrReportSettings.Values sections(Boolean overview, Boolean items, Boolean analysis) {
        PhrReportSettings.Values v = new PhrReportSettings.Values();
        v.summaryOverview = overview; v.summaryAssociatedItems = items; v.summaryAnalysis = analysis;
        return v;
    }

    @IsTest static void allSectionsOnLeavesTheSummaryUnchanged() {
        System.assertEquals(MD, PhrSummarySections.apply(MD, sections(true, true, true)));
        System.assertEquals(HTML, PhrSummarySections.apply(HTML, sections(true, true, true)));
    }

    @IsTest static void markdownSectionsAreRemoved() {
        String out = PhrSummarySections.apply(MD, sections(false, true, true));
        System.assert(!out.contains('Complaint Overview') && !out.contains('Overview text'), out);
        System.assert(out.contains('Associated Items') && out.contains('Next text'), out);
        out = PhrSummarySections.apply(MD, sections(true, false, true));
        System.assert(!out.contains('Items text') && out.contains('Overview text') && out.contains('Next text'), out);
        out = PhrSummarySections.apply(MD, sections(true, true, false));
        System.assert(!out.contains('Analysis and Next Steps') && out.contains('Items text'), out);
    }

    @IsTest static void htmlSectionsAreRemoved() {
        String out = PhrSummarySections.apply(HTML, sections(true, false, true));
        System.assert(!out.contains('Items text') && !out.contains('Associated Items'), out);
        System.assert(out.contains('Overview text') && out.contains('Next text'), out);
        out = PhrSummarySections.apply(HTML, sections(false, true, false));
        System.assert(out.contains('Items text') && !out.contains('Overview text') && !out.contains('Next text'), out);
    }

    @IsTest static void productHistoryReviewHeadingFollowsTheSameCheckbox() {
        String s = '## Complaint Overview\nA.\n\n## Product History Review\nB.';
        System.assert(!PhrSummarySections.apply(s, sections(true, false, true)).contains('B.'));
        System.assert(PhrSummarySections.apply(s, sections(true, true, true)).contains('B.'));
    }

    @IsTest static void textWithoutKnownHeadingsIsUnchanged() {
        String s = 'Just a paragraph about the complaint overview in a sentence.';
        System.assertEquals(s, PhrSummarySections.apply(s, sections(false, false, true)));
        System.assertEquals(null, PhrSummarySections.apply(null, sections(false, false, false)));
        System.assertEquals(false, PhrSummarySections.anySectionOn(sections(false, false, false)));
        System.assertEquals(true, PhrSummarySections.anySectionOn(sections(false, true, false)));
    }

    @IsTest static void generateAppliesTheSectionSettings() {
        GenerateDraftInvestigationSummary.mockResponse = MD;
        PhrReportSettings.testValues = sections(false, true, true);
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = withLotInfo().Id;
        req.saveToRecord = false;
        List<GenerateDraftInvestigationSummary.Result> res =
            GenerateDraftInvestigationSummary.generate(new List<GenerateDraftInvestigationSummary.Request>{ req });
        System.assert(!res[0].summary.contains('Overview text'), res[0].summary);
        System.assert(res[0].summary.contains('Items text'), res[0].summary);
    }

    @IsTest static void generateWithEverySectionOffExplainsWhy() {
        GenerateDraftInvestigationSummary.mockResponse = MD;
        PhrReportSettings.testValues = sections(false, false, false);
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = withLotInfo().Id;
        req.saveToRecord = true;
        List<GenerateDraftInvestigationSummary.Result> res =
            GenerateDraftInvestigationSummary.generate(new List<GenerateDraftInvestigationSummary.Request>{ req });
        System.assertEquals(null, res[0].summary);
        System.assertEquals(false, res[0].saved);
        System.assert(res[0].message.contains('No summary sections'), res[0].message);
    }
}

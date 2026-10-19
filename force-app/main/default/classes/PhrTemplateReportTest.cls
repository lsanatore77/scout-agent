@IsTest
private class PhrTemplateReportTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Tmpl Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(
            Name = 'Tmpl Product', cqext__Title__c = 'Tmpl Product', compliancequest__Part_Number__c = 'TMPL-OWN',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
    }

    static compliancequest__SQX_Complaint__c newComplaint(String lot) {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Template complaint',
            compliancequest__Description__c = 'Template complaint description',
            compliancequest__SQX_Part__c = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = lot);
        insert c;
        return c;
    }

    @IsTest static void dataReportsGapsForBareComplaint() {
        compliancequest__SQX_Complaint__c cmp = newComplaint(null);
        PhrReportData d = PhrReportData.build(cmp.Id, '3');
        System.assertEquals(true, d.hasComplaint, 'Error: ' + d.errorMessage);
        System.assertEquals('3', d.versionLabel);
        Boolean lotGap = false;
        for (String g : d.gaps) { if (g.contains('no lot number')) { lotGap = true; } }
        System.assertEquals(true, lotGap);
        System.assertEquals(0, d.leadRows.size());
    }

    @IsTest static void dataWithoutIdGivesError() {
        PhrReportData d = PhrReportData.build(null, '1');
        System.assertEquals(false, d.hasComplaint);
        System.assertNotEquals(null, d.errorMessage);
    }

    @IsTest static void rendersWithDefaultTemplate() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-T1');
        PhrReportData d = PhrReportData.build(cmp.Id, '1');
        PhrReportRenderer.Result r = PhrReportRenderer.render(d);
        System.assertNotEquals(null, r.pdf);
        System.assertEquals('Built-in default template', r.source);
    }

    @IsTest static void fillEscapesAndRemovesUnknownPlaceholders() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-T2');
        PhrReportData d = PhrReportData.build(cmp.Id, '1');
        d.complaintName = 'A&B <x>';
        String out = PhrReportRenderer.fill('<html xmlns="http://www.w3.org/1999/xhtml"><body><p>{{complaintName}}</p><p>{{nope}}</p></body></html>', d, false);
        System.assertNotEquals(null, out);
        System.assert(out.contains('A&amp;B &lt;x&gt;'), out);
        System.assert(!out.contains('{{'), out);
    }

    @IsTest static void badTemplateIsRejected() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-T3');
        PhrReportData d = PhrReportData.build(cmp.Id, '1');
        System.assertEquals(null, PhrReportRenderer.fill('<html><body><p>{{complaintName}}</body></html>', d, false));
        System.assertEquals(false, PhrReportRenderer.isWellFormed('<a><b></a>'));
        System.assertEquals(true, PhrReportRenderer.isWellFormed('<a><b/></a>'));
    }

    @IsTest static void brokenDraftFallsBackToPlainText() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-T4');
        PhrReportData d = PhrReportData.build(cmp.Id, '1');
        d.draftSummaryHtml = '<p>Open <b>tag</p>';
        String tpl = '<html xmlns="http://www.w3.org/1999/xhtml"><body>{{draftSummaryBlock}}</body></html>';
        System.assertEquals(null, PhrReportRenderer.fill(tpl, d, false));
        System.assertNotEquals(null, PhrReportRenderer.fill(tpl, d, true));
    }

    @IsTest static void cleanForXmlWritesNumericEntities() {
        System.assertEquals('a&#160;b<br/>', PhrReportData.cleanForXml('a&nbsp;b<br>'));
    }

    @IsTest static void summaryAndReasonsHelpers() {
        PhrQmsPanelController.Row r = new PhrQmsPanelController.Row();
        r.name = 'NC-1'; r.tier = 'Top'; r.relevance = 80; r.status = 'Open'; r.criteriaMet = 'Lot';
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>{ r };
        String s = PhrReportData.buildSummary(rows, 2);
        System.assert(s.contains('Review the 1 top lead first.'), s);
        System.assert(s.contains('2 data gaps'), s);
        System.assert(!s.contains('NC-1'), 'Summary never names a record');
        System.assertEquals(true, PhrReportData.buildReasons(rows).size() > 0);
        System.assertEquals(0, PhrReportData.countWords(null));
        System.assertEquals(2, PhrReportData.limitWords('a b c d', 2).split(' ').size());
    }

    @IsTest static void actionAttachesFileThenAddsVersion() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-T5');
        PhrTemplateReportAction.Request req = new PhrTemplateReportAction.Request();
        req.recordId = cmp.Id;
        PhrTemplateReportAction.Response r1 = PhrTemplateReportAction.run(new List<PhrTemplateReportAction.Request>{ req })[0];
        System.assertEquals(true, r1.success, r1.message);
        System.assertEquals(1, r1.version);
        PhrTemplateReportAction.Response r2 = PhrTemplateReportAction.run(new List<PhrTemplateReportAction.Request>{ req })[0];
        System.assertEquals(true, r2.success, r2.message);
        System.assertEquals(2, r2.version);
        System.assertEquals(r1.contentDocumentId, r2.contentDocumentId, 'Same file, new version');
        System.assertEquals('Product History Review Report', [SELECT Title FROM ContentDocument WHERE Id = :r1.contentDocumentId].Title);
    }

    @IsTest static void actionHandlesMissingAndUnsupportedIds() {
        PhrTemplateReportAction.Request req = new PhrTemplateReportAction.Request();
        PhrTemplateReportAction.Response r = PhrTemplateReportAction.run(new List<PhrTemplateReportAction.Request>{ req })[0];
        System.assertEquals(false, r.success);
        req.recordId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        r = PhrTemplateReportAction.run(new List<PhrTemplateReportAction.Request>{ req })[0];
        System.assertEquals(false, r.success);
    }

    @IsTest static void noControlledTemplateIsNotAnError() {
        PhrReportRenderer.TemplateLookup lk = PhrReportRenderer.findControlledTemplate();
        System.assertEquals(null, lk.text);
        System.assertEquals(null, lk.problem);
    }
}

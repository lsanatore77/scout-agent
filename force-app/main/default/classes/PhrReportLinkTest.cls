@IsTest
private class PhrReportLinkTest {

    static compliancequest__SQX_Complaint__c makeComplaint() {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Hub separated from shaft during preparation',
            compliancequest__Description_As_Reported__c = 'Hub separated from shaft during preparation',
            compliancequest__Country_of_Origin__c = 'US');
        insert c;
        return c;
    }

    static Id attachReport(Id complaintId) {
        ContentVersion cv = new ContentVersion(
            Title = PhrReportLink.REPORT_TITLE,
            PathOnClient = 'Product_History_Review_Report.pdf',
            VersionData = Blob.valueOf('%PDF-1.4 test'),
            FirstPublishLocationId = complaintId);
        insert cv;
        return [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
    }

    @IsTest
    static void noReportLeavesTheSummaryAlone() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Assert.areEqual('<p>Summary</p>', PhrReportLink.withReportLink(c.Id, '<p>Summary</p>'));
        Assert.areEqual('', PhrReportLink.shareWithInvestigations(c.Id));
    }

    @IsTest
    static void reportLinkIsAddedOnceAndRefreshed() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Id docId = attachReport(c.Id);
        String once = PhrReportLink.withReportLink(c.Id, '<p>Summary</p>');
        Assert.isTrue(once.startsWith('<p>Summary</p>'), once);
        Assert.isTrue(once.contains('/lightning/r/ContentDocument/' + docId + '/view'), once);
        Assert.isTrue(PhrReportLink.hasLink(once));

        String twice = PhrReportLink.withReportLink(c.Id, once);
        Assert.areEqual(once, twice, 'The link line must not be duplicated');
    }

    @IsTest
    static void stripRemovesOnlyTheReportLine() {
        String html = '<p>Keep me</p>' + PhrReportLink.line('069000000000001AAA');
        Assert.areEqual('<p>Keep me</p>', PhrReportLink.stripLink(html));
        Assert.isNull(PhrReportLink.stripLink(null));
        Assert.isFalse(PhrReportLink.hasLink('<p>No link</p>'));
    }

    @IsTest
    static void afterReportAddsTheLinkToTheDraftSummary() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        c.Draft_Investigation_Summaries__c = '<p>Existing draft</p>';
        update c;
        attachReport(c.Id);
        PhrReportLink.afterReportGenerated(c.Id);
        String draft = [SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :c.Id].Draft_Investigation_Summaries__c;
        Assert.isTrue(PhrReportLink.hasLink(draft), draft);
    }

    @IsTest
    static void investigationIdsIsEmptyWithoutInvestigations() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Assert.isTrue(PhrReportLink.investigationIds(c.Id).isEmpty());
    }

    static Id makeLinkedInvestigation(Id complaintId, String summary) {
        compliancequest__SQX_Investigation__c inv = new compliancequest__SQX_Investigation__c(
            compliancequest__Investigation_Summary__c = summary);
        Schema.RecordTypeInfo rt = compliancequest__SQX_Investigation__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Complaint_Investigation');
        if (rt != null) { inv.RecordTypeId = rt.getRecordTypeId(); }
        insert inv;
        insert new compliancequest__SQX_Linked_Investigation__c(
            compliancequest__SQX_Complaint__c = complaintId,
            compliancequest__SQX_Investigation__c = inv.Id);
        return inv.Id;
    }

    @IsTest
    static void reportIsSharedWithTheInvestigationOnce() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Id docId = attachReport(c.Id);
        Id invId = makeLinkedInvestigation(c.Id, null);
        Test.startTest();
        String first = PhrReportLink.shareWithInvestigations(c.Id);
        String second = PhrReportLink.shareWithInvestigations(c.Id);
        Test.stopTest();
        Assert.isTrue(first.contains('shared with 1 investigation'), first);
        Assert.isTrue(second.contains('already shared'), second);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :docId AND LinkedEntityId = :invId]);
    }

    @IsTest
    static void afterReportAddsTheLinkToTheInvestigationSummary() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        attachReport(c.Id);
        Id invId = makeLinkedInvestigation(c.Id, '<p>Investigation summary</p>');
        Test.startTest();
        String msg = PhrReportLink.afterReportGenerated(c.Id);
        Test.stopTest();
        String summary = [SELECT compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c
                          WHERE Id = :invId].compliancequest__Investigation_Summary__c;
        Assert.isTrue(PhrReportLink.hasLink(summary), msg + ' | ' + summary);
    }

    @IsTest
    static void savingTheSummaryCopiesItAndSharesTheReport() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Id docId = attachReport(c.Id);
        Id invId = makeLinkedInvestigation(c.Id, null);
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = c.Id;
        req.summary = 'Approved summary';
        Test.startTest();
        SaveDraftInvestigationSummary.Result r = SaveDraftInvestigationSummary.save(
            new List<SaveDraftInvestigationSummary.Request>{ req })[0];
        Test.stopTest();
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.message.contains('also updated on 1 investigation'), r.message);
        String summary = [SELECT compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c
                          WHERE Id = :invId].compliancequest__Investigation_Summary__c;
        Assert.isTrue(summary.contains('Approved summary'), summary);
        Assert.isTrue(PhrReportLink.hasLink(summary), summary);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :docId AND LinkedEntityId = :invId]);
    }

    @IsTest
    static void problemsAreReportedAsText() {
        Assert.areEqual('', PhrReportLink.shareWithInvestigations(null));
        Assert.isNull(PhrReportLink.reportDocumentId(null));
    }
}

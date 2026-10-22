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
}

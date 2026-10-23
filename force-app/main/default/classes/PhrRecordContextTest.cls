@IsTest
private class PhrRecordContextTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Hub separated from shaft during preparation',
            compliancequest__Description_As_Reported__c = 'Hub separated from shaft during preparation',
            compliancequest__Country_of_Origin__c = 'US');
        insert c;
        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = c.Id,
            compliancequest__Completed_By__c = 'Test Reviewer');
    }

    static compliancequest__SQX_Complaint__c complaint() {
        return [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1];
    }

    static compliancequest__SQX_Product_History_Review__c phr() {
        return [SELECT Id, Name FROM compliancequest__SQX_Product_History_Review__c LIMIT 1];
    }

    @IsTest
    static void complaintAndPhrIdsBothGiveTheComplaint() {
        Id cId = complaint().Id;
        Id pId = phr().Id;
        Assert.areEqual(cId, PhrRecordContext.complaintIdFor(cId));
        Assert.areEqual(cId, PhrRecordContext.complaintIdFor(pId));
        Assert.areEqual(cId, PhrRecordContext.complaintIdFor(String.valueOf(pId)));
        Assert.areEqual(pId, PhrRecordContext.phrIdFor(cId));
        Assert.areEqual(pId, PhrRecordContext.phrIdFor(pId));
        Assert.isTrue(PhrRecordContext.isPhr(pId));
        Assert.isFalse(PhrRecordContext.isInvestigation(pId));
    }

    @IsTest
    static void aTaskOnTheComplaintGivesTheComplaint() {
        Id cId = complaint().Id;
        Task t = new Task(Subject = 'Triage', WhatId = cId);
        insert t;
        Assert.areEqual(cId, PhrRecordContext.complaintIdFor(t.Id));
    }

    @IsTest
    static void aLinkedInvestigationGivesTheComplaint() {
        Id cId = complaint().Id;
        compliancequest__SQX_Investigation__c inv = new compliancequest__SQX_Investigation__c();
        Schema.RecordTypeInfo rt = compliancequest__SQX_Investigation__c.SObjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName().get('Complaint_Investigation');
        if (rt != null) { inv.RecordTypeId = rt.getRecordTypeId(); }
        insert inv;
        insert new compliancequest__SQX_Linked_Investigation__c(
            compliancequest__SQX_Complaint__c = cId, compliancequest__SQX_Investigation__c = inv.Id);
        Assert.isTrue(PhrRecordContext.isInvestigation(inv.Id));
        Assert.areEqual(cId, PhrRecordContext.complaintIdFor(inv.Id));
    }

    @IsTest
    static void unknownIdsGiveNull() {
        Assert.isNull(PhrRecordContext.complaintIdFor((Id) null));
        Assert.isNull(PhrRecordContext.complaintIdFor(''));
        Assert.isNull(PhrRecordContext.complaintIdFor('not-an-id'));
        Assert.isNull(PhrRecordContext.complaintIdFor(UserInfo.getUserId()));
        Assert.isNull(PhrRecordContext.phrIdFor(null));
        Assert.areEqual('', PhrRecordContext.objectOf(null));
    }

    @IsTest
    static void savingFromThePhrSavesToTheComplaintAndThePhr() {
        Id cId = complaint().Id;
        compliancequest__SQX_Product_History_Review__c p = phr();
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = p.Id;
        req.summary = '## Complaint Overview\nHub separated.\n\nThis is an AI-generated draft that requires investigator review.';
        Test.startTest();
        SaveDraftInvestigationSummary.Result r = SaveDraftInvestigationSummary.save(
            new List<SaveDraftInvestigationSummary.Request>{ req })[0];
        Test.stopTest();
        Assert.isTrue(r.success, r.message);
        Assert.isTrue(r.message.contains('Summary on the Product History Review (' + p.Name + ')'), r.message);
        String onComplaint = [SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c
                              WHERE Id = :cId].Draft_Investigation_Summaries__c;
        String onPhr = [SELECT compliancequest__Product_History_Review_Summary__c FROM compliancequest__SQX_Product_History_Review__c
                        WHERE Id = :p.Id].compliancequest__Product_History_Review_Summary__c;
        Assert.isTrue(onComplaint.contains('Hub separated'), onComplaint);
        Assert.isFalse(onComplaint.contains('AI-generated'), onComplaint);
        Assert.areEqual(onComplaint, onPhr);
    }

    @IsTest
    static void generatingFromThePhrFindsTheComplaint() {
        GenerateDraftInvestigationSummary.mockResponse = '### Complaint Overview\nDraft text.\nThis is an AI-generated draft that requires investigator review.';
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = phr().Id;
        req.saveToRecord = false;
        Test.startTest();
        GenerateDraftInvestigationSummary.Result r = GenerateDraftInvestigationSummary.generate(
            new List<GenerateDraftInvestigationSummary.Request>{ req })[0];
        Test.stopTest();
        Assert.isNotNull(r.summary, r.message);
        Assert.isTrue(r.summary.contains('Draft text'), r.summary);
        Assert.isFalse(r.summary.contains('AI-generated'), r.summary);
    }

    @IsTest
    static void generatingForAnUnknownRecordSaysSo() {
        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = UserInfo.getUserId();
        GenerateDraftInvestigationSummary.Result r = GenerateDraftInvestigationSummary.generate(
            new List<GenerateDraftInvestigationSummary.Request>{ req })[0];
        Assert.isTrue(r.message.contains('could not find the complaint'), r.message);
    }

    @IsTest
    static void saveNeedsAComplaintAndText() {
        SaveDraftInvestigationSummary.Request a = new SaveDraftInvestigationSummary.Request();
        a.complaintId = UserInfo.getUserId();
        a.summary = 'Text';
        SaveDraftInvestigationSummary.Request b = new SaveDraftInvestigationSummary.Request();
        b.complaintId = complaint().Id;
        b.summary = 'This is an AI-generated draft that requires investigator review.';
        List<SaveDraftInvestigationSummary.Result> rs = SaveDraftInvestigationSummary.save(
            new List<SaveDraftInvestigationSummary.Request>{ a, b });
        Assert.isFalse(rs[0].success);
        Assert.isFalse(rs[1].success);
        Assert.isTrue(rs[1].message.contains('no summary text'), rs[1].message);
    }

    @IsTest
    static void disclaimerIsRemovedFromTextAndHtml() {
        Assert.areEqual('<p>Keep.</p>', PhrSummaryText.stripDisclaimer(
            '<p>Keep.</p><p><em>This is an AI-generated draft that requires investigator review.</em></p>'));
        Assert.areEqual('<p>Keep.</p>', PhrSummaryText.stripDisclaimer(
            '<p>Keep. This is an AI-generated draft that requires investigator review.</p>'));
        Assert.areEqual('Keep.', PhrSummaryText.stripDisclaimer(
            'Keep.\n\n*This is an AI-generated draft that requires investigator review.*'));
        Assert.isNull(PhrSummaryText.stripDisclaimer(null));
    }
}

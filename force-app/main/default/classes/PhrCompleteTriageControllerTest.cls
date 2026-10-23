@IsTest
private class PhrCompleteTriageControllerTest {

    static compliancequest__SQX_Complaint__c makeComplaint() {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Hub separated from shaft during preparation',
            compliancequest__Description_As_Reported__c = 'Hub separated from shaft during preparation',
            compliancequest__Country_of_Origin__c = 'US');
        insert c;
        return c;
    }

    @IsTest
    static void loadReturnsTheComplaintAndItsDraftSteps() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        PhrCompleteTriageController.TriageData d = PhrCompleteTriageController.load(c.Id);
        Assert.areEqual(c.Id, d.complaintId);
        Assert.isNotNull(d.steps);
        Assert.isNotNull(d.templates);
        Assert.isFalse(d.hasDraft);
    }

    @IsTest
    static void loadRejectsAnUnknownRecord() {
        try {
            PhrCompleteTriageController.load('not-an-id');
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            Assert.isTrue(true);
        }
    }

    @IsTest
    static void saveStepsWithNothingToDoSucceeds() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        PhrCompleteTriageController.Outcome o = PhrCompleteTriageController.saveSteps(c.Id, '[]');
        Assert.isTrue(o.success, o.message);
        Assert.isTrue(o.message.contains('0 updated, 0 added'), o.message);
    }

    @IsTest
    static void activityCodeDependsOnTheOwner() {
        Group q = new Group(Name = 'PHR Test Queue', Type = 'Queue');
        insert q;
        Assert.areEqual('takeownershipandinitiate', PhrCompleteTriageController.activityCodeFor(q.Id));
        Assert.areEqual('initiate', PhrCompleteTriageController.activityCodeFor(UserInfo.getUserId()));
    }

    @IsTest
    static void newStepCopiesTheTemplate() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        compliancequest__SQX_Task__c t = new compliancequest__SQX_Task__c(
            Name = 'Product History Review',
            compliancequest__Step__c = 1,
            compliancequest__Allowed_Days__c = 5);
        compliancequest__SQX_Complaint_Task__c s = PhrCompleteTriageController.newStep(c.Id, t, UserInfo.getUserId());
        Assert.areEqual('Draft', s.compliancequest__Status__c);
        Assert.areEqual(UserInfo.getUserId(), s.compliancequest__SQX_User__c);
        Assert.areEqual(5, s.compliancequest__Allowed_Days__c);
    }

    @IsTest
    static void completeTriageReportsTheOutcome() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        PhrCompleteTriageController.Outcome o = PhrCompleteTriageController.completeTriage(c.Id, 'Test');
        // CQ decides whether this complaint can be initiated; either way a message comes back.
        Assert.isNotNull(o.message);
    }

    @IsTest
    static void generateDraftReturnsFormattedTextWithoutSaving() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        GenerateDraftInvestigationSummary.mockResponse = '### Complaint Overview\nDraft text for NC-000074.';
        Test.startTest();
        PhrCompleteTriageController.DraftOutcome o = PhrCompleteTriageController.generateDraft(c.Id);
        Test.stopTest();
        Assert.isTrue(o.success, o.message);
        Assert.isTrue(o.html.contains('<strong>'), o.html);
        Assert.isTrue(o.html.contains('NC-000074'), o.html);
        Assert.isNull([SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :c.Id]
            .Draft_Investigation_Summaries__c, 'Generating must not save');
    }

    @IsTest
    static void generateDraftRejectsAnUnknownRecord() {
        PhrCompleteTriageController.DraftOutcome o = PhrCompleteTriageController.generateDraft('not-an-id');
        Assert.isFalse(o.success);
    }

    @IsTest
    static void saveDraftSavesOnce() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Test.startTest();
        PhrCompleteTriageController.Outcome o = PhrCompleteTriageController.saveDraft(c.Id, '<p>Edited draft</p>');
        Test.stopTest();
        Assert.isTrue(o.success, o.message);
        String saved = [SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :c.Id]
            .Draft_Investigation_Summaries__c;
        Assert.isTrue(saved.contains('Edited draft'), saved);
        PhrCompleteTriageController.TriageData d = PhrCompleteTriageController.load(c.Id);
        Assert.isTrue(d.hasDraft);
        Assert.isTrue(d.draftHtml.contains('Edited draft'));
    }

    @IsTest
    static void saveDraftNeedsText() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Assert.isFalse(PhrCompleteTriageController.saveDraft(c.Id, '').success);
        Assert.isFalse(PhrCompleteTriageController.saveDraft('', '<p>x</p>').success);
    }
}

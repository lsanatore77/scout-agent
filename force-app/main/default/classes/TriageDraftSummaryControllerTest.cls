@IsTest
private class TriageDraftSummaryControllerTest {

    static compliancequest__SQX_Complaint__c makeComplaint() {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Caliper piston seized during fleet use',
            compliancequest__Description_As_Reported__c = 'Caliper piston seized during fleet use',
            compliancequest__Country_of_Origin__c = 'US');
        insert c;
        return c;
    }

    @IsTest
    static void noDraftReportsNothingIncluded() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Assert.isFalse(TriageDraftSummaryController.hasDraft(c.Id));
        TriageDraftSummaryController.Outcome o = TriageDraftSummaryController.includeDraftSummary(c.Id);
        Assert.isTrue(o.success);
        Assert.isFalse(o.hasDraft);
        Assert.isTrue(o.message.contains('no draft summary'), o.message);
    }

    @IsTest
    static void existingDraftIsSavedThroughTheSharedSaveLogic() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        c.Draft_Investigation_Summaries__c = '<p>Existing draft</p>';
        update c;
        Assert.isTrue(TriageDraftSummaryController.hasDraft(c.Id));
        TriageDraftSummaryController.Outcome o = TriageDraftSummaryController.includeDraftSummary(c.Id);
        Assert.isTrue(o.success, o.message);
        Assert.isTrue(o.hasDraft);
        Assert.isTrue(o.message.contains('saved to the complaint'), o.message);
    }

    @IsTest
    static void badOrBlankIdsReturnAFriendlyMessage() {
        Assert.isFalse(TriageDraftSummaryController.hasDraft(null));
        Assert.isFalse(TriageDraftSummaryController.hasDraft('not-an-id'));
        TriageDraftSummaryController.Outcome o = TriageDraftSummaryController.includeDraftSummary('');
        Assert.isFalse(o.success);
        Assert.isTrue(o.message.contains('could not be found'), o.message);
    }

    @IsTest
    static void resolvesTheComplaintFromAComplaintId() {
        compliancequest__SQX_Complaint__c c = makeComplaint();
        Assert.areEqual(c.Id, TriageDraftSummaryController.resolveComplaintId(c.Id));
    }
}

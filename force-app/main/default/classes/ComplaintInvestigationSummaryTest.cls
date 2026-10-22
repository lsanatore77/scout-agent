@IsTest
private class ComplaintInvestigationSummaryTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Caliper piston seized during fleet use',
            compliancequest__Description_As_Reported__c = 'Caliper piston seized during fleet use',
            compliancequest__Country_of_Origin__c = 'US');
        insert complaint;

        compliancequest__SQX_Product_History_Review__c review = new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = complaint.Id,
            compliancequest__Completed_By__c = 'Test Reviewer');
        insert review;

        insert new compliancequest__SQX_Product_History_Answer__c(
            compliancequest__SQX_Product_History_Review__c = review.Id,
            compliancequest__Answer__c = 'No',
            compliancequest__Notes__c = 'Scrap rate within limits');
    }

    static compliancequest__SQX_Complaint__c getComplaint() {
        return [SELECT Id, Name FROM compliancequest__SQX_Complaint__c LIMIT 1];
    }

    static compliancequest__SQX_Part__c createPart(String name, String partNumber) {
        compliancequest__SQX_Part_Family__c family = new compliancequest__SQX_Part_Family__c(Name = name + ' Family');
        insert family;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = name,
            cqext__Title__c = name,
            compliancequest__Part_Number__c = partNumber,
            compliancequest__Part_Family__c = family.Id,
            compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert part;
        return part;
    }

    @IsTest
    static void groundingIncludesComplaintReviewsAndChecklist() {
        Id complaintId = getComplaint().Id;

        Test.startTest();
        String text = ComplaintInvestigationGrounding.buildGroundingText(complaintId);
        Test.stopTest();

        Assert.isTrue(text.contains('## COMPLAINT'), 'Complaint section missing');
        Assert.isTrue(text.contains('Caliper piston seized during fleet use'), 'Complaint field value missing');
        Assert.isTrue(text.contains('## PRODUCT HISTORY REVIEWS (1)'), 'Review count missing');
        Assert.isTrue(text.contains('Test Reviewer'), 'Review field value missing');
        Assert.isTrue(text.contains('#### Checklist Items (1)'), 'Checklist section missing');
        Assert.isTrue(text.contains('Scrap rate within limits'), 'Checklist field value missing');
    }

    @IsTest
    static void groundingHandlesComplaintWithoutReviews() {
        compliancequest__SQX_Complaint__c other = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'No reviews yet',
            compliancequest__Country_of_Origin__c = 'US');
        insert other;

        String text = ComplaintInvestigationGrounding.buildGroundingText(other.Id);

        Assert.isTrue(text.contains('## PRODUCT HISTORY REVIEWS (0)'), 'Zero-review header missing');
        Assert.isTrue(text.contains('No Product History Review records are linked'), 'Empty-review note missing');
    }

    @IsTest
    static void groundingIncludesTasksSection() {
        Id complaintId = getComplaint().Id;

        String text = ComplaintInvestigationGrounding.buildGroundingText(complaintId);

        Assert.isTrue(text.contains('## CQ TASKS ('), 'CQ Tasks section missing: ' + text);
    }

    @IsTest
    static void tasksTextReportsNoneWhenComplaintHasNoTasks() {
        compliancequest__SQX_Complaint__c other = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'No tasks',
            compliancequest__Country_of_Origin__c = 'US');
        insert other;

        String text = ComplaintInvestigationGrounding.buildTasksText(other.Id);

        Assert.isTrue(text.contains('## CQ TASKS (0)'), 'Zero-task header missing: ' + text);
        Assert.isTrue(text.contains('No CQ Tasks are recorded on this complaint.'), 'Empty-task note missing: ' + text);
    }

    @IsTest
    static void associatedItemsNotesMissingPrimaryPart() {
        Id complaintId = getComplaint().Id;

        Test.startTest();
        String text = ComplaintInvestigationGrounding.buildGroundingText(complaintId);
        Test.stopTest();

        Assert.isTrue(text.contains('## ASSOCIATED ITEMS'), 'Associated items section missing');
        Assert.isTrue(text.contains('No primary Part is set on this complaint'), 'Missing-part note missing');
    }

    @IsTest
    static void associatedItemsIncludePrimaryPartAndCounts() {
        compliancequest__SQX_Part__c part = createPart('Summary Test Part', 'TST-SUMMARY-001');
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Complaint with a part',
            compliancequest__Description_As_Reported__c = 'Complaint with a part',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US');
        insert complaint;

        Test.startTest();
        String text = ComplaintInvestigationGrounding.buildAssociatedItemsText(complaint.Id);
        Test.stopTest();

        Assert.isTrue(text.contains('### Primary Part'), 'Primary part section missing: ' + text);
        Assert.isTrue(text.contains('TST-SUMMARY-001'), 'Primary part fields missing: ' + text);
        Assert.isTrue(text.contains('### Assemblies ('), 'Assemblies section missing: ' + text);
        Assert.isTrue(text.contains('### Nonconformances (0)'), 'Nonconformance section missing: ' + text);
        Assert.isTrue(text.contains('### Inspections (0)'), 'Inspection section missing: ' + text);
        Assert.isTrue(text.contains('### Related Investigations (0)'), 'Investigation section missing: ' + text);
        Assert.isTrue(text.contains('### Counts by Part'), 'Counts section missing: ' + text);
        Assert.isTrue(text.contains('No Nonconformances, CAPAs, Change Orders, Inspections or Investigations.'),
            'Empty counts note missing: ' + text);
    }

    // Covers the record index, full record details and per-part counts that are
    // only written when the Associated Items Report returns quality records.
    @IsTest
    static void associatedItemsListAndCountQualityRecords() {
        compliancequest__SQX_Part__c part = createPart('Summary Count Part', 'TST-SUMMARY-002');
        compliancequest__SQX_Complaint__c complaint = new compliancequest__SQX_Complaint__c(
            compliancequest__Description__c = 'Complaint with related records',
            compliancequest__Description_As_Reported__c = 'Complaint with related records',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US');
        insert complaint;

        insert new List<compliancequest__SQX_Nonconformance__c>{
            new compliancequest__SQX_Nonconformance__c(
                compliancequest__NC_Title__c = 'Summary test NC one',
                compliancequest__Type__c = 'Internal',
                compliancequest__Type_Of_Issue__c = 'Product',
                compliancequest__Description__c = 'First nonconformance for the summary test',
                compliancequest__SQX_Part__c = part.Id,
                compliancequest__Occurrence_Date__c = Date.today()),
            new compliancequest__SQX_Nonconformance__c(
                compliancequest__NC_Title__c = 'Summary test NC two',
                compliancequest__Type__c = 'Internal',
                compliancequest__Type_Of_Issue__c = 'Product',
                compliancequest__Description__c = 'Second nonconformance for the summary test',
                compliancequest__SQX_Part__c = part.Id,
                compliancequest__Occurrence_Date__c = Date.today())
        };

        Test.startTest();
        String text = ComplaintInvestigationGrounding.buildAssociatedItemsText(complaint.Id);
        Test.stopTest();

        Assert.isTrue(text.contains('### Nonconformances (2)'), 'Nonconformance count missing: ' + text);
        Assert.isTrue(text.contains('Record index'), 'Record index missing: ' + text);
        Assert.isTrue(text.contains('Summary test NC one'), 'NC title missing from index: ' + text);
        Assert.isTrue(text.contains('Full record details:'), 'Full details missing: ' + text);
        Assert.isTrue(text.contains('- Nonconformance 1'), 'NC detail entry missing: ' + text);
        Assert.isTrue(text.contains('- Summary Count Part: Nonconformances 2'),
            'Per-part count missing: ' + text);
    }

    @IsTest
    static void generateReturnsDraftWithoutSaving() {
        Id complaintId = getComplaint().Id;
        GenerateDraftInvestigationSummary.mockResponse = 'DRAFT INVESTIGATION SUMMARY - test';

        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.saveToRecord = false;

        Test.startTest();
        List<GenerateDraftInvestigationSummary.Result> results =
            GenerateDraftInvestigationSummary.generate(new List<GenerateDraftInvestigationSummary.Request>{ req });
        Test.stopTest();

        Assert.areEqual('DRAFT INVESTIGATION SUMMARY - test', results[0].summary);
        Assert.isFalse(results[0].saved);
        compliancequest__SQX_Complaint__c after = [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId];
        Assert.isNull(after.Draft_Investigation_Summaries__c, 'Draft should not be saved');
    }

    @IsTest
    static void generateCanSaveDraft() {
        Id complaintId = getComplaint().Id;
        GenerateDraftInvestigationSummary.mockResponse = 'Saved draft text';

        GenerateDraftInvestigationSummary.Request req = new GenerateDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.saveToRecord = true;

        Test.startTest();
        List<GenerateDraftInvestigationSummary.Result> results =
            GenerateDraftInvestigationSummary.generate(new List<GenerateDraftInvestigationSummary.Request>{ req });
        Test.stopTest();

        Assert.isTrue(results[0].saved, results[0].message);
        compliancequest__SQX_Complaint__c after = [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId];
        Assert.areEqual('<p>Saved draft text</p>', after.Draft_Investigation_Summaries__c);
    }

    @IsTest
    static void saveWritesApprovedText() {
        Id complaintId = getComplaint().Id;
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.summary = '  Approved summary  ';

        Test.startTest();
        List<SaveDraftInvestigationSummary.Result> results =
            SaveDraftInvestigationSummary.save(new List<SaveDraftInvestigationSummary.Request>{ req });
        Test.stopTest();

        Assert.isTrue(results[0].success, results[0].message);
        compliancequest__SQX_Complaint__c after = [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId];
        Assert.areEqual('<p>Approved summary</p>', after.Draft_Investigation_Summaries__c);
    }

    @IsTest
    static void saveAlsoUpdatesTheLinkedInvestigations() {
        Id complaintId = getComplaint().Id;
        SaveDraftInvestigationSummary.Request req = new SaveDraftInvestigationSummary.Request();
        req.complaintId = complaintId;
        req.summary = 'Approved summary';

        Test.startTest();
        List<SaveDraftInvestigationSummary.Result> results =
            SaveDraftInvestigationSummary.save(new List<SaveDraftInvestigationSummary.Request>{ req });
        Test.stopTest();

        Assert.isTrue(results[0].success, results[0].message);
        Set<Id> invIds = new Set<Id>();
        for (compliancequest__SQX_Linked_Investigation__c li : [
            SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Linked_Investigation__c
            WHERE compliancequest__SQX_Complaint__c = :complaintId]) {
            invIds.add(li.compliancequest__SQX_Investigation__c);
        }
        for (compliancequest__SQX_Complaint__c c : [
            SELECT compliancequest__SQX_Primary_Investigation__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId]) {
            if (c.compliancequest__SQX_Primary_Investigation__c != null) { invIds.add(c.compliancequest__SQX_Primary_Investigation__c); }
        }
        if (invIds.isEmpty()) {
            Assert.isTrue(results[0].message.contains('No investigation is linked'), results[0].message);
        } else {
            for (compliancequest__SQX_Investigation__c inv : [
                SELECT compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c WHERE Id IN :invIds]) {
                Assert.areEqual('<p>Approved summary</p>', inv.compliancequest__Investigation_Summary__c);
            }
            Assert.isTrue(results[0].message.contains('also updated'), results[0].message);
        }
    }

    @IsTest
    static void findMatchesComplaintNumberCaseInsensitively() {
        compliancequest__SQX_Complaint__c complaint = getComplaint();

        FindComplaintForSummary.Request hit = new FindComplaintForSummary.Request();
        hit.complaintNumber = ' ' + complaint.Name.toLowerCase() + ' ';
        FindComplaintForSummary.Request miss = new FindComplaintForSummary.Request();
        miss.complaintNumber = 'NOT-A-COMPLAINT';

        Test.startTest();
        List<FindComplaintForSummary.Result> results =
            FindComplaintForSummary.find(new List<FindComplaintForSummary.Request>{ hit, miss });
        Test.stopTest();

        Assert.isTrue(results[0].found);
        Assert.areEqual(complaint.Id, results[0].complaintId);
        Assert.areEqual(complaint.Name, results[0].complaintNumber);
        Assert.isFalse(results[1].found);
        Assert.isNull(results[1].complaintId);
    }
}

@IsTest
private class PhrChecklistActionTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Checklist Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Checklist Product', cqext__Title__c = 'Checklist Product', compliancequest__Part_Number__c = 'CHK-OWN',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Checklist complaint',
            compliancequest__Description__c = 'Checklist complaint description',
            compliancequest__SQX_Part__c = part.Id,
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = 'LOT-CHK');
        insert c;
        compliancequest__SQX_Product_History_Review__c phr = new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = c.Id, compliancequest__Completed_By__c = 'Tester');
        insert phr;
        insert new List<compliancequest__SQX_Product_History_Answer__c>{
            answer(phr.Id, 'Was there a high scrap rate?'),
            answer(phr.Id, 'Were there any related nonconformances?'),
            answer(phr.Id, 'Was the lot inspected and passed?'),
            answer(phr.Id, 'Is the label legible?')
        };
    }

    static compliancequest__SQX_Product_History_Answer__c answer(Id phrId, String q) {
        return new compliancequest__SQX_Product_History_Answer__c(
            compliancequest__SQX_Product_History_Review__c = phrId, compliancequest__Question__c = q);
    }

    static Id phrId() {
        return [SELECT Id FROM compliancequest__SQX_Product_History_Review__c LIMIT 1].Id;
    }

    static PhrChecklistItem item(PhrChecklistResult r, String startsWith) {
        for (PhrChecklistItem i : r.items) { if (i.question.startsWith(startsWith)) { return i; } }
        return null;
    }

    @IsTest static void suggestsWithoutSaving() {
        PhrChecklistAction.Request req = new PhrChecklistAction.Request();
        req.recordId = phrId();
        Test.startTest();
        PhrChecklistResult r = PhrChecklistAction.run(new List<PhrChecklistAction.Request>{ req })[0].result;
        Test.stopTest();
        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(4, r.items.size());
        PhrChecklistItem scrap = item(r, 'Was there a high scrap rate');
        System.assertEquals(true, scrap.sure);
        System.assertEquals('No', scrap.suggestedAnswer, 'No nonconformances in the test, so the rate is 0');
        System.assert(scrap.basis.contains('The scrap rate calculated = 0.00'), scrap.basis);
        System.assertEquals(false, item(r, 'Was the lot inspected').sure, 'A pass/fail question cannot be answered from a count');
        System.assertEquals(false, item(r, 'Is the label legible').sure);
        System.assertEquals(2, r.unsureCount);
        System.assert(r.intro.contains('not sure'), r.intro);
        System.assert(r.unsureQuestions.contains('Is the label legible?'), r.unsureQuestions);
        System.assertEquals(false, r.saved);
        System.assertEquals(0, [SELECT COUNT() FROM compliancequest__SQX_Product_History_Answer__c WHERE compliancequest__Answer__c != null]);
    }

    @IsTest static void savesOnlyTheAnswersItIsSureAbout() {
        Id complaintId = [SELECT Id FROM compliancequest__SQX_Complaint__c LIMIT 1].Id;
        Test.startTest();
        PhrChecklistResult r = PhrChecklistAction.answer(complaintId, true);
        Test.stopTest();
        System.assertEquals(true, r.success, r.errorMessage);
        System.assertEquals(true, r.saved);
        System.assertEquals(r.sureCount, r.savedCount);
        compliancequest__SQX_Product_History_Answer__c scrap = [
            SELECT compliancequest__Answer__c, compliancequest__Answer_Value__c, compliancequest__Notes__c
            FROM compliancequest__SQX_Product_History_Answer__c WHERE compliancequest__Question__c LIKE '%scrap%' LIMIT 1];
        System.assertEquals('No', scrap.compliancequest__Answer__c);
        System.assertEquals('No', scrap.compliancequest__Answer_Value__c);
        System.assert(scrap.compliancequest__Notes__c.contains('scrap rate'), scrap.compliancequest__Notes__c);
        System.assertEquals(null, [SELECT compliancequest__Answer__c FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__Question__c LIKE 'Is the label%' LIMIT 1].compliancequest__Answer__c);
        System.assertEquals('saved', item(r, 'Was there a high scrap rate').status);
        System.assert(r.intro.startsWith('I saved'), r.intro);
    }

    @IsTest static void noReviewMeansNoChecklist() {
        Id partId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        PhrChecklistResult r = PhrChecklistAction.answer(partId, false);
        System.assertEquals(false, r.success);
        System.assertEquals(false, PhrChecklistAction.answer(null, false).success);
    }

    @IsTest static void rulesAndValues() {
        System.assertEquals('nc', PhrChecklistAction.kindOf('Any non-conformances?'));
        System.assertEquals('capa', PhrChecklistAction.kindOf('Is there an open CAPA?'));
        System.assertEquals('change', PhrChecklistAction.kindOf('Was there a design change?'));
        System.assertEquals('inspection', PhrChecklistAction.kindOf('Any failed inspections?'));
        System.assertEquals('investigation', PhrChecklistAction.kindOf('Are other investigations open?'));
        System.assertEquals(null, PhrChecklistAction.kindOf('Is the label legible?'));
        System.assertEquals('Yes', PhrChecklistAction.matchValue('yes', new List<String>{ 'Yes', 'No' }));
        System.assertEquals(null, PhrChecklistAction.matchValue('Yes', new List<String>{ 'Pass', 'Fail' }));
        System.assertEquals('No', PhrChecklistAction.matchValue('No', null));
    }
}

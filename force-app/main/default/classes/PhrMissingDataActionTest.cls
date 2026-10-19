@IsTest
private class PhrMissingDataActionTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Missing Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(
            Name = 'Missing Product', cqext__Title__c = 'Missing Product', compliancequest__Part_Number__c = 'MIS-OWN',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
    }

    static compliancequest__SQX_Complaint__c newComplaint(String lot, Boolean withPart) {
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Missing data complaint',
            compliancequest__Description__c = 'Missing data complaint description',
            compliancequest__Country_of_Origin__c = 'US',
            compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(),
            compliancequest__Reported_Date__c = Date.today(),
            compliancequest__Lot_Number__c = lot);
        if (withPart) {
            c.compliancequest__SQX_Part__c = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        }
        insert c;
        return c;
    }

    static PhrMissingCheck find(PhrMissingDataResult r, String label) {
        for (PhrMissingCheck c : r.checks) {
            if (c.label == label) { return c; }
        }
        return null;
    }

    @IsTest static void everyGapIsReportedWhenPresent() {
        compliancequest__SQX_Complaint__c cmp = newComplaint(null, false);
        PhrMissingDataResult r = PhrMissingDataAction.check(cmp.Id);
        System.assertEquals(true, r.success, 'Error: ' + r.errorMessage);
        System.assertEquals(6, r.checks.size(), 'Six checks');
        System.assertEquals('warn', find(r, 'Lot number').status);
        System.assertEquals('warn', find(r, 'Part').status);
        System.assertEquals('warn', find(r, 'Product History Review').status);
        System.assert(r.intro.contains('gap'), r.intro);
    }

    @IsTest static void draftReviewWithoutCompletedByIsAWarning() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-MIS', true);
        insert new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = cmp.Id, compliancequest__Status__c = 'Draft');
        PhrMissingDataResult r = PhrMissingDataAction.check(cmp.Id);
        System.assertEquals('ok', find(r, 'Lot number').status);
        System.assertEquals('ok', find(r, 'Part').status);
        System.assertEquals('ok', find(r, 'Product History Review').status);
        System.assertEquals('warn', find(r, 'Review status').status);
    }

    @IsTest static void noGapsWhenEverythingIsPresent() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-MIS', true);
        compliancequest__SQX_Product_History_Review__c phr = new compliancequest__SQX_Product_History_Review__c(
            compliancequest__SQX_Complaint__c = cmp.Id, compliancequest__Status__c = 'Draft',
            compliancequest__Completed_By__c = 'Tester');
        insert phr;
        PhrMissingDataResult r = PhrMissingDataAction.check(phr.Id);
        System.assertEquals('ok', find(r, 'Lot number').status);
        System.assertEquals('ok', find(r, 'Part').status);
        System.assertEquals('ok', find(r, 'Product History Review').status);
        System.assertEquals('ok', find(r, 'Review status').status, 'Completed By is filled in');
        System.assertEquals('ok', find(r, 'Investigation summaries').status);
    }

    @IsTest static void missingOrWrongRecordFailsPlainly() {
        System.assertEquals(false, PhrMissingDataAction.check(null).success);
        Id partId = [SELECT Id FROM compliancequest__SQX_Part__c LIMIT 1].Id;
        System.assertEquals(false, PhrMissingDataAction.check(partId).success);
    }

    @IsTest static void invocableReturnsOneResultPerRequest() {
        compliancequest__SQX_Complaint__c cmp = newComplaint('LOT-MIS', true);
        PhrMissingDataAction.Request req = new PhrMissingDataAction.Request();
        req.recordId = cmp.Id;
        List<PhrMissingDataAction.ActionResponse> out = PhrMissingDataAction.run(new List<PhrMissingDataAction.Request>{ req });
        System.assertEquals(1, out.size());
        System.assertEquals(true, out[0].result.success);
    }
}

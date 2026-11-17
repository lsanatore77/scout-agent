@IsTest
private class CqEventReviewTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Review Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(Name = 'Review Part', cqext__Title__c = 'Review Part',
            compliancequest__Part_Number__c = 'RV-PART-1', compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');
        insert part;

        Quality_Event__c ev = new Quality_Event__c(Title__c = 'Balloon slow to deflate', Problem_Statement__c = 'Slow at final test',
            Event_Type__c = 'Report', Status__c = 'Waiting for Review', Part__c = part.Id, Lot_Number__c = 'L26-0911',
            Units_Affected__c = 8, Where_Found__c = 'At a Customer', Product_Affected__c = 'Yes', Safety_Risk__c = 'Not Known',
            Injury__c = 'No', Urgent__c = true);
        insert ev;
        insert new Event_Answer__c(Quality_Event__c = ev.Id, Question_Text__c = 'Where did this happen?',
            Answer__c = 'At a Customer', Role__c = 'Where Found', Order__c = 1);

        insert new Quality_Event__c(Title__c = 'Earlier deflate', Problem_Statement__c = 'same part earlier',
            Event_Type__c = 'Report', Status__c = 'Waiting for Review', Part__c = part.Id);
    }

    @IsTest
    static void buildsTheReview() {
        Quality_Event__c ev = [SELECT Id FROM Quality_Event__c WHERE Title__c = 'Balloon slow to deflate'];
        Test.startTest();
        CqEventReview.Review r = CqEventReview.getReview(ev.Id);
        Test.stopTest();

        System.assertEquals('Balloon slow to deflate', r.title);
        System.assertEquals('RV-PART-1', r.partNumber);
        System.assertEquals(true, r.urgent);
        System.assertEquals(1, r.answers.size());
        System.assertEquals('New Complaint', r.suggestion.becomes, 'at a customer suggests a complaint');
        System.assert(!r.suggestion.reasons.isEmpty(), 'has reasons');
        System.assertEquals(1, r.similarEvents.size(), 'the other event on the same part');
        System.assertEquals(0, r.openOnPart.size(), 'no NCs open on this part in the test');
    }

    @IsTest
    static void noEventRefused() {
        try {
            CqEventReview.getReview(null);
            System.assert(false, 'should refuse a null id');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}

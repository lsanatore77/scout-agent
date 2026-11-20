@IsTest
private class CqIntakeSetupTest {

    @TestSetup
    static void makeRunner() { CqIntakeTestData.runner(); }

    @IsTest
    static void loadsTheDefaultsOnceAndSkipsThemAfter() {
        System.runAs(CqIntakeTestData.runner()) {
            Integer clipResources = [SELECT COUNT() FROM StaticResource WHERE Name LIKE 'CQ_Intake_Clip_%'];

            Test.startTest();
            CqIntakeSetup.Loaded first = CqIntakeSetup.loadDefaults();
            CqIntakeSetup.Loaded again = CqIntakeSetup.loadDefaults();
            Test.stopTest();

            System.assertEquals(9, first.questions);
            System.assertEquals(Math.min(clipResources, 9), first.clips, 'one clip per question when the package clips are there');
            System.assertEquals(4, first.categories);
            System.assertEquals(0, again.questions, 'safe to run again');
            System.assertEquals(0, again.clips);
            System.assertEquals(0, again.categories);
            System.assert(first.toString().contains('Questions added: 9'));

            Event_Question__c where1 = [SELECT Role__c, Required__c, Case_Field__c, Choices__c, Active__c FROM Event_Question__c
                                        WHERE Question__c = 'Where did this happen?'];
            System.assertEquals('Where Found', where1.Role__c);
            System.assertEquals('Where_Found__c', where1.Case_Field__c, 'the answer goes to the Case field');
            System.assert(where1.Required__c && where1.Active__c);
            System.assertEquals(9, [SELECT COUNT() FROM Event_Question__c]);
        }
    }

    @IsTest
    static void keepsAQuestionAnOrgAlreadyHas() {
        System.runAs(CqIntakeTestData.runner()) {
            insert new Event_Question__c(Question__c = 'Was anyone injured?', Order__c = 9, Answer_Type__c = 'Text', Active__c = false);
            CqIntakeSetup.Loaded r = CqIntakeSetup.loadDefaults();
            System.assertEquals(8, r.questions, 'the existing one is left as it is');
            Event_Question__c kept = [SELECT Order__c, Active__c FROM Event_Question__c WHERE Question__c = 'Was anyone injured?'];
            System.assertEquals(9, kept.Order__c);
            System.assertEquals(false, kept.Active__c);
        }
    }
}

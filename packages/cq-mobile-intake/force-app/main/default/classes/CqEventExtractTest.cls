@IsTest
private class CqEventExtractTest {

    @TestSetup
    static void setup() {
        System.runAs(CqIntakeTestData.runner()) {
            compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Extract Family');
            insert fam;
            insert CqIntakeTestData.part(new compliancequest__SQX_Part__c(Name = 'Intake Part',
                compliancequest__Part_Number__c = 'INT-PART-1', compliancequest__Part_Family__c = fam.Id,
                compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true));
            insert new List<Event_Question__c>{
                new Event_Question__c(Order__c = 1, Question__c = 'Where did this happen?', Answer_Type__c = 'Choice',
                    Choices__c = 'In Our Plant;At a Supplier;At a Customer', Role__c = 'Where Found', Required__c = true, Active__c = true),
                new Event_Question__c(Order__c = 2, Question__c = 'Was anyone injured?', Answer_Type__c = 'Yes or No',
                    Role__c = 'Injury', Required__c = true, Active__c = true),
                new Event_Question__c(Order__c = 3, Question__c = 'Is safety at risk?', Answer_Type__c = 'Choice',
                    Choices__c = 'No;Yes;Not Sure', Role__c = 'Safety Risk', Required__c = true, Active__c = true),
                new Event_Question__c(Order__c = 4, Question__c = 'Which test found it?', Answer_Type__c = 'Text',
                    Role__c = 'None', Active__c = true)
            };
        }
    }

    @IsTest
    static void extractsSuggestionsAndFlagsMissingRequired() {
        System.runAs(CqIntakeTestData.runner()) {
            CqEventExtract.mockJson =
                '{"TITLE":{"value":"Balloons slow to deflate","reason":null},' +
                '"PART":{"value":"Intake","reason":null},' +
                '"LOT":{"value":"L26-0908","reason":null},' +
                '"UNITS AFFECTED":{"value":"3","reason":null},' +
                '"DEFECT":{"value":"Slow deflation","reason":null},' +
                '"WHERE FOUND":{"value":"in our plant","reason":null},' +
                '"INJURY":{"value":null,"reason":null},' +
                '"SAFETY RISK":{"value":"Not Sure","reason":null}}';

            Test.startTest();
            CqEventExtract.Result res = CqEventExtract.fromDescription('three balloons slow to deflate in final test');
            Test.stopTest();

            System.assertEquals('Balloons slow to deflate', res.title);

            Map<String, CqEventExtract.Suggestion> byKey = new Map<String, CqEventExtract.Suggestion>();
            for (CqEventExtract.Suggestion s : res.suggestions) { byKey.put(s.key, s); }

            System.assert(byKey.containsKey('part'), 'part suggested');
            System.assertNotEquals(null, byKey.get('part').recordId, 'part resolved to a record');
            System.assert(byKey.get('part').value.contains('INT-PART-1'), 'resolved part shows its number');

            System.assertEquals('3', byKey.get('units').value);
            System.assert(byKey.get('units').needsConfirm, 'quantity flagged to confirm');
            System.assertEquals('L26-0908', byKey.get('lot').value);

            System.assertEquals('In Our Plant', byKey.get('Where Found').value, 'lowercased answer mapped to the real choice');
            System.assertEquals('Not Sure', byKey.get('Safety Risk').value);
            System.assert(!byKey.containsKey('Injury'), 'injury not answered, so not suggested');

            System.assertEquals(1, res.stillNeeded.size(), 'the one unanswered required question');
            System.assertEquals('Was anyone injured?', res.stillNeeded[0]);
        }
    }

    @IsTest
    static void blankDescriptionRefused() {
        System.runAs(CqIntakeTestData.runner()) {
            try {
                CqEventExtract.fromDescription('   ');
                System.assert(false, 'should refuse a blank description');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void withoutCqAiSimpleRulesKeepItGoing() {
        System.runAs(CqIntakeTestData.runner()) {
            CqEventExtract.mockJson = CqEventExtract.FAIL;   // as in an org without CQ's prompt template
            CqEventExtract.Result res = CqEventExtract.fromDescription('there was a problem with lot-2011 5 items were affected');
            Map<String, CqEventExtract.Suggestion> byKey = new Map<String, CqEventExtract.Suggestion>();
            for (CqEventExtract.Suggestion s : res.suggestions) { byKey.put(s.key, s); }
            System.assertEquals('there was a problem with lot-2011 5 items were affected', res.title, 'the story\'s first words');
            System.assertEquals('LOT-2011', byKey.get('lot').value);
            System.assertEquals('5', byKey.get('units').value);
            System.assertEquals(3, res.stillNeeded.size(), 'every required question is still asked');
        }
    }

    @IsTest
    static void basicReadFindsLotAfterTheWord() {
        Map<String, String> v = CqEventExtract.basicRead('Batch number L26-0908, three of them. Twelve more words here to make the title get cut short ok');
        System.assertEquals('L26-0908', v.get('LOT'));
        System.assert(v.get('TITLE').endsWith('...'), 'a long story gives a shortened title');
        System.assert(!v.containsKey('UNITS AFFECTED'), 'no number with a unit word');
        System.assertEquals('7', CqEventExtract.basicRead('lot 4471 had 7 units leak').get('UNITS AFFECTED'));
        System.assertEquals('4471', CqEventExtract.basicRead('lot 4471 had 7 units leak').get('LOT'));
    }
}

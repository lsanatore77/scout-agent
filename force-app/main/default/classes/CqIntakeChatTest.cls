@IsTest
private class CqIntakeChatTest {

    @TestSetup
    static void setup() {
        System.runAs(CqIntakeTestData.runner()) {
            compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Chat Family');
            insert fam;
            insert CqIntakeTestData.part(new compliancequest__SQX_Part__c(Name = 'CardioFlow',
                compliancequest__Part_Number__c = 'PTCA-1000', compliancequest__Part_Family__c = fam.Id,
                compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true));

            // One required question with a role, so "still needed" has something to ask for.
            insert new Event_Question__c(Active__c = true, Required__c = true, Order__c = 1,
                Question__c = 'Where did this happen?', Answer_Type__c = 'Choice',
                Choices__c = 'In Our Plant;At a Customer;At a Supplier;Not Known', Role__c = 'Where Found');
        }
    }

    @IsTest
    static void opensWithAPrompt() {
        System.runAs(CqIntakeTestData.runner()) {
            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.start();
            Test.stopTest();
            System.assertEquals('describe', t.askKey);
            System.assert(String.isNotBlank(t.reply));
            System.assert(String.isNotBlank(t.reporter));
        }
    }

    @IsTest
    static void asksForWhatIsMissing() {
        System.runAs(CqIntakeTestData.runner()) {
            // Extractor returns a part, lot and defect, but nothing for the "Where Found" question.
            CqEventExtract.mockJson = '{"PART":{"value":"CardioFlow"},"LOT":{"value":"L26-0908"},"DEFECT":{"value":"slow to deflate"},"UNITS AFFECTED":{"value":"8"},"TITLE":{"value":"Balloon slow to deflate"}}';
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'The CardioFlow balloon from lot L26-0908 was slow to deflate, about 8 units.',
                'answers' => new List<Object>()
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            System.assertEquals(false, t.ready, 'a required question is still open');
            System.assertEquals('Where Found', t.askKey);
            System.assert(t.askQuestionId != null, 'it names the question it is asking');
            System.assertEquals(4, t.choices.size(), 'the choice question offers its choices');
            System.assert(!t.understood.isEmpty(), 'it reads back what it understood');
            System.assert(t.reply.contains('CardioFlow'), 'the readback names the part');
            System.assert(!t.stillNeeded.isEmpty());
        }
    }

    @IsTest
    static void readyWhenNothingRequiredIsMissing() {
        System.runAs(CqIntakeTestData.runner()) {
            CqEventExtract.mockJson = '{"PART":{"value":"CardioFlow"},"LOT":{"value":"L26-0908"},"WHERE FOUND":{"value":"At a Customer"},"TITLE":{"value":"Balloon issue"}}';
            Event_Question__c q = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'CardioFlow balloon, lot L26-0908, failed at a customer.',
                'answers' => new List<Object>{ new Map<String, Object>{ 'questionId' => q.Id, 'answer' => 'At a Customer' } }
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            System.assertEquals(true, t.ready, 'the required question was answered');
            System.assertEquals('ready', t.askKey);
            System.assert(String.isNotBlank(t.draftJson), 'it hands back a draft to submit');
            Map<String, Object> d = (Map<String, Object>) JSON.deserializeUntyped(t.draftJson);
            System.assertEquals('CardioFlow balloon, lot L26-0908, failed at a customer.', d.get('problem'));
            System.assert(d.containsKey('answers'));
        }
    }

    @IsTest
    static void safetyIsAlwaysAsked() {
        System.runAs(CqIntakeTestData.runner()) {
            // A required Safety question, and extraction DID produce a value for it.
            Event_Question__c safety = new Event_Question__c(Active__c = true, Required__c = true, Order__c = 2,
                Question__c = 'Could anyone get hurt, or is product safety at risk?', Answer_Type__c = 'Yes or No', Role__c = 'Safety Risk');
            insert safety;

            CqEventExtract.mockJson = '{"DEFECT":{"value":"cracked hub"},"WHERE FOUND":{"value":"In Our Plant"},"SAFETY RISK":{"value":"No"}}';
            Event_Question__c where1 = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'cracked hub found in our plant',
                'answers' => new List<Object>{ new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'In Our Plant' } }
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            System.assertEquals(false, t.ready, 'safety must be asked even though the AI guessed it');
            System.assertEquals('Safety Risk', t.askKey);
            System.assertEquals(safety.Id, t.askQuestionId);
            System.assertEquals('No', t.askSuggested, 'the AI guess is offered as a default to confirm');
            Boolean safetyFlagged = false;
            for (CqIntakeChat.Field f : t.understood) {
                if (f.key == 'Safety Risk') { safetyFlagged = f.needsConfirm; }
            }
            System.assert(safetyFlagged, 'the unconfirmed safety guess wears the needs-confirm mark');
        }
    }

    @IsTest
    static void asksWhoWasHurtOnlyWhenInjured() {
        System.runAs(CqIntakeTestData.runner()) {
            Event_Question__c injury = new Event_Question__c(Active__c = true, Required__c = true, Order__c = 3,
                Question__c = 'Was anyone injured?', Answer_Type__c = 'Yes or No', Role__c = 'Injury');
            insert injury;
            Event_Question__c who = new Event_Question__c(Active__c = true, Required__c = false, Order__c = 5,
                Question__c = 'Who was hurt?', Answer_Type__c = 'Text', Role__c = 'Injured Person');
            insert who;
            Event_Question__c where1 = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];

            CqEventExtract.mockJson = '{"DEFECT":{"value":"cut"}}';

            // Injury = No -> it must NOT ask who was hurt, and nothing requires it.
            String noInjury = JSON.serialize(new Map<String, Object>{
                'description' => 'a small cut on the line',
                'answers' => new List<Object>{
                    new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'In Our Plant' },
                    new Map<String, Object>{ 'questionId' => injury.Id, 'answer' => 'No' } }
            });
            CqIntakeChat.Turn t1 = CqIntakeChat.respond(noInjury);
            for (String s : t1.stillNeeded) { System.assertNotEquals('Who was hurt?', s, 'no injury -> never asks who'); }

            // Injury = Yes -> it asks who was hurt.
            String injured = JSON.serialize(new Map<String, Object>{
                'description' => 'someone cut their hand',
                'answers' => new List<Object>{
                    new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'In Our Plant' },
                    new Map<String, Object>{ 'questionId' => injury.Id, 'answer' => 'Yes' } }
            });
            Test.startTest();
            CqIntakeChat.Turn t2 = CqIntakeChat.respond(injured);
            Test.stopTest();

            System.assertEquals(false, t2.ready, 'who was hurt is still outstanding');
            System.assertEquals('Injured Person', t2.askKey);
            System.assertEquals(who.Id, t2.askQuestionId);
            System.assertEquals('Who was hurt?', t2.askQuestion);
        }
    }

    @IsTest
    static void asksCustomerWhenFoundAtACustomer() {
        System.runAs(CqIntakeTestData.runner()) {
            Event_Question__c cust = new Event_Question__c(Active__c = true, Required__c = false, Order__c = 1.1,
                Question__c = 'Which customer?', Answer_Type__c = 'Text', Role__c = 'Customer');
            insert cust;
            Event_Question__c where1 = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];

            CqEventExtract.mockJson = '{"DEFECT":{"value":"leak"}}';
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'a leak reported by a customer',
                'answers' => new List<Object>{ new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'At a Customer' } }
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            System.assertEquals(false, t.ready);
            System.assertEquals('Customer', t.askKey, 'at a customer -> asks which customer');
            System.assertEquals(cust.Id, t.askQuestionId);
        }
    }

    @IsTest
    static void doesNotAskCustomerWhenInPlant() {
        System.runAs(CqIntakeTestData.runner()) {
            Event_Question__c cust = new Event_Question__c(Active__c = true, Required__c = false, Order__c = 1.1,
                Question__c = 'Which customer?', Answer_Type__c = 'Text', Role__c = 'Customer');
            insert cust;
            Event_Question__c where1 = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];

            CqEventExtract.mockJson = '{"DEFECT":{"value":"leak"}}';
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'a leak at final test',
                'answers' => new List<Object>{ new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'In Our Plant' } }
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            for (String s : t.stillNeeded) { System.assertNotEquals('Which customer?', s, 'in-plant -> never asks for a customer'); }
        }
    }

    @IsTest
    static void asksForLotWhenNoneAndFeedsDescription() {
        System.runAs(CqIntakeTestData.runner()) {
            Event_Question__c lot = new Event_Question__c(Active__c = true, Required__c = false, Order__c = 1.5,
                Question__c = 'Do you have a lot or batch number?', Answer_Type__c = 'Text', Role__c = 'Lot Or Part');
            insert lot;
            Event_Question__c where1 = [SELECT Id FROM Event_Question__c WHERE Role__c = 'Where Found'];

            // No PART and no LOT extracted from the description.
            CqEventExtract.mockJson = '{"DEFECT":{"value":"bent pin"}}';
            String state = JSON.serialize(new Map<String, Object>{
                'description' => 'found a bent pin',
                'answers' => new List<Object>{ new Map<String, Object>{ 'questionId' => where1.Id, 'answer' => 'In Our Plant' } }
            });

            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(state);
            Test.stopTest();

            System.assertEquals(false, t.ready);
            System.assertEquals('Lot Or Part', t.askKey, 'no lot and no part -> asks for a lot/batch');
            System.assertEquals(lot.Id, t.askQuestionId);
            System.assertEquals(true, t.askFeedsDescription, 'the lot answer is treated as more description');
        }
    }

    @IsTest
    static void blankDescriptionFallsBackToOpening() {
        System.runAs(CqIntakeTestData.runner()) {
            Test.startTest();
            CqIntakeChat.Turn t = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{ 'description' => '' }));
            Test.stopTest();
            System.assertEquals('describe', t.askKey);
        }
    }
}

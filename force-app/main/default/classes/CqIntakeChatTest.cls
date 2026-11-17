@IsTest
private class CqIntakeChatTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Chat Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(Name = 'CardioFlow', cqext__Title__c = 'CardioFlow',
            compliancequest__Part_Number__c = 'PTCA-1000', compliancequest__Part_Family__c = fam.Id,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true,
            cqext__Part_Definition__c = 'Individual');

        // One required question with a role, so "still needed" has something to ask for.
        insert new Event_Question__c(Active__c = true, Required__c = true, Order__c = 1,
            Question__c = 'Where did this happen?', Answer_Type__c = 'Choice',
            Choices__c = 'In Our Plant;At a Customer;At a Supplier;Not Known', Role__c = 'Where Found');
    }

    @IsTest
    static void opensWithAPrompt() {
        Test.startTest();
        CqIntakeChat.Turn t = CqIntakeChat.start();
        Test.stopTest();
        System.assertEquals('describe', t.askKey);
        System.assert(String.isNotBlank(t.reply));
        System.assert(String.isNotBlank(t.reporter));
    }

    @IsTest
    static void asksForWhatIsMissing() {
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

    @IsTest
    static void readyWhenNothingRequiredIsMissing() {
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

    @IsTest
    static void blankDescriptionFallsBackToOpening() {
        Test.startTest();
        CqIntakeChat.Turn t = CqIntakeChat.respond(JSON.serialize(new Map<String, Object>{ 'description' => '' }));
        Test.stopTest();
        System.assertEquals('describe', t.askKey);
    }
}

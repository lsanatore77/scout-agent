@IsTest
private class AskCqServiceTest {

    class Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            System.assert(url.startsWith('callout:Ask_CQ_Agent_API/'), url);
            System.assert(req.getHeader('Authorization') == null, 'the Named Credential adds the token');
            if (url.endsWith('/sessions') && req.getMethod() == 'POST') {
                res.setStatusCode(201);
                res.setBody('{"sessionId":"S1","messages":[{"type":"Inform","id":"m1","message":"Hi, I am Scout."}]}');
            } else if (url.endsWith('/messages')) {
                res.setStatusCode(200);
                System.assert(req.getBody().contains('"sequenceId":1'), req.getBody());
                System.assert(req.getBody().contains('The record open on screen is'), req.getBody());
                res.setBody('{"messages":[{"type":"Inform","id":"m2","message":"NC-000139 is red because it meets all three criteria."}]}');
            } else if (req.getMethod() == 'DELETE') {
                res.setStatusCode(200);
                res.setBody('{"messages":[{"type":"SessionEnded","reason":"ClientRequest"}]}');
            } else {
                res.setStatusCode(404);
                res.setBody('{}');
            }
            return res;
        }
    }

    static void setup() {
        AskCqService.testAgentId = Id.valueOf('0XxW40000000wIXKAY');
    }

    @IsTest static void startAskEnd() {
        setup();
        Test.setMock(HttpCalloutMock.class, new Mock());
        // No complaint is saved: only its Id is passed along, so complaint validation rules don't matter here.
        Id complaintId = compliancequest__SQX_Complaint__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Test.startTest();
        AskCqService.Reply r = AskCqService.startSession(complaintId, null);
        System.assertEquals('S1', r.sessionId);
        System.assert(r.text.contains('Scout'), r.text);
        AskCqService.Reply a = AskCqService.sendMessage(r.sessionId, r.nextSequence, 'Why is NC-000139 red?', complaintId);
        System.assert(a.text.contains('three criteria'), a.text);
        System.assertEquals(2, a.nextSequence);
        AskCqService.endSession(r.sessionId);
        Test.stopTest();
    }

    @IsTest static void agentGivenByIdIsUsed() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        AskCqService.Reply r = AskCqService.startSession(null, '0XxW400000010ijKAA');
        System.assertEquals('S1', r.sessionId);
    }

    @IsTest static void messagesTextJoinsInformMessages() {
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped('{"messages":[{"message":"a"},{"message":""},{"message":"b"}]}');
        System.assertEquals('a\n\nb', AskCqService.messagesText(out));
        System.assertEquals('', AskCqService.messagesText(null));
    }
}

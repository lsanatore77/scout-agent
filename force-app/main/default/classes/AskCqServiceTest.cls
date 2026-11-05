@IsTest
private class AskCqServiceTest {

    class Mock implements HttpCalloutMock {
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            res.setHeader('Content-Type', 'application/json');
            String url = req.getEndpoint();
            if (url.endsWith('/services/oauth2/token')) {
                res.setStatusCode(200);
                res.setBody('{"access_token":"tok","instance_url":"https://x.my.salesforce.com"}');
            } else if (url.endsWith('/sessions') && req.getMethod() == 'POST') {
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
        AskCqService.Settings s = new AskCqService.Settings();
        s.consumerKey = 'k'; s.consumerSecret = 's'; s.agentId = '0XxW40000000wIXKAY';
        AskCqService.testSettings = s;
    }

    @IsTest static void startAskEnd() {
        setup();
        Test.setMock(HttpCalloutMock.class, new Mock());
        compliancequest__SQX_Complaint__c c = new compliancequest__SQX_Complaint__c(compliancequest__Description__c = 'x');
        insert c;
        Test.startTest();
        AskCqService.Reply r = AskCqService.startSession(c.Id, null);
        System.assertEquals('S1', r.sessionId);
        System.assert(r.text.contains('Scout'), r.text);
        AskCqService.Reply a = AskCqService.sendMessage(r.sessionId, r.nextSequence, 'Why is NC-000139 red?', c.Id);
        System.assert(a.text.contains('three criteria'), a.text);
        System.assertEquals(2, a.nextSequence);
        AskCqService.endSession(r.sessionId);
        Test.stopTest();
    }

    @IsTest static void missingSettingsFailClearly() {
        Test.setMock(HttpCalloutMock.class, new Mock());
        AskCqService.Settings s = new AskCqService.Settings();
        AskCqService.testSettings = s;
        try {
            AskCqService.startSession(null, null);
            System.assert(false, 'expected an exception');
        } catch (AskCqService.AskCqException e) {
            System.assert(e.getMessage().contains('not set up'), e.getMessage());
        }
    }

    @IsTest static void messagesTextJoinsInformMessages() {
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped('{"messages":[{"message":"a"},{"message":""},{"message":"b"}]}');
        System.assertEquals('a\n\nb', AskCqService.messagesText(out));
        System.assertEquals('', AskCqService.messagesText(null));
    }
}

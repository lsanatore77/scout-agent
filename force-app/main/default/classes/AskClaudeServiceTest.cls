@IsTest
private class AskClaudeServiceTest {
    class Reply implements HttpCalloutMock {
        Integer status; String body; HttpRequest seen;
        Reply(Integer status, String body) { this.status = status; this.body = body; }
        public HttpResponse respond(HttpRequest req) {
            seen = req;
            HttpResponse r = new HttpResponse();
            r.setStatusCode(status);
            r.setBody(body);
            return r;
        }
    }

    @IsTest static void offUnlessGranted() {
        AskClaudeService.forceEnabled = false;
        System.assertEquals(false, AskClaudeService.isEnabled());
        try {
            AskClaudeService.ask('Why Class II?', 'The HHE rates the risk as temporary.', null);
            System.assert(false, 'should refuse when Ask Claude is off');
        } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest static void sendsQuestionAndAnswerAndReturnsText() {
        AskClaudeService.forceEnabled = true;
        Reply mock = new Reply(200, '{"content":[{"type":"text","text":"Class II means temporary harm."},{"type":"text","text":"More detail."}]}');
        Test.setMock(HttpCalloutMock.class, mock);
        Test.startTest();
        String a = AskClaudeService.ask('Why Class II?', 'The HHE rates the risk as temporary.', 'Glance');
        Test.stopTest();
        System.assertEquals('Class II means temporary harm.\nMore detail.', a);
        System.assertEquals('callout:Anthropic_Claude/v1/messages', mock.seen.getEndpoint());
        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(mock.seen.getBody());
        System.assertEquals(AskClaudeService.MODEL, body.get('model'));
        String sent = (String) ((Map<String, Object>) ((List<Object>) body.get('messages'))[0]).get('content');
        System.assert(sent.contains('Why Class II?') && sent.contains('temporary') && sent.contains('Glance step'), sent);
        System.assertEquals(null, mock.seen.getHeader('x-api-key'), 'the key comes from the credential, never the code');
    }

    @IsTest static void badKeyGivesAPlainReason() {
        AskClaudeService.forceEnabled = true;
        Test.setMock(HttpCalloutMock.class, new Reply(401, '{"type":"error"}'));
        Test.startTest();
        try {
            AskClaudeService.ask('Q', 'An answer', null);
            System.assert(false, 'should fail on 401');
        } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
        System.assert(AskClaudeService.failure(401).contains('API key'));
        System.assert(AskClaudeService.failure(429).contains('busy'));
        System.assert(AskClaudeService.failure(529).contains('unavailable'));
        System.assert(AskClaudeService.failure(400).contains('400'));
    }

    @IsTest static void needsAnAnswer() {
        AskClaudeService.forceEnabled = true;
        try {
            AskClaudeService.ask('Q', '  ', null);
            System.assert(false, 'should refuse an empty answer');
        } catch (AuraHandledException e) { System.assert(true); }
    }
}

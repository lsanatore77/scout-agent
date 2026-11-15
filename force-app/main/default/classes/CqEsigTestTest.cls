@IsTest
private class CqEsigTestTest {

    class Mock implements HttpCalloutMock {
        Id userId; Integer status;
        Mock(Id userId, Integer status) { this.userId = userId; this.status = status; }
        public HttpResponse respond(HttpRequest req) {
            HttpResponse res = new HttpResponse();
            if (req.getEndpoint().endsWith('/services/oauth2/revoke')) { res.setStatusCode(200); return res; }
            res.setStatusCode(status);
            res.setBody(status == 200
                ? JSON.serialize(new Map<String, Object>{ 'access_token' => 'tok', 'id' => 'https://x/id/' + UserInfo.getOrganizationId() + '/' + userId })
                : '{"error":"invalid_grant","error_description":"authentication failure"}');
            return res;
        }
    }

    @IsTest
    static void signerLoggedIn() {
        Test.setMock(HttpCalloutMock.class, new Mock(UserInfo.getUserId(), 200));
        Test.startTest();
        CqEsigTest.Result r = CqEsigTest.verify('c', 'v', 'k', 'https://x/apex/CqEsigCallback', 'Approved');
        Test.stopTest();
        System.assert(r.ok, r.message);
        System.assert(r.message.startsWith('Signed: '), r.message);
    }

    @IsTest
    static void someoneElseLoggedIn() {
        Id other = User.SObjectType.getDescribe().getKeyPrefix() + '000000000001AAA';
        Test.setMock(HttpCalloutMock.class, new Mock(other, 200));
        CqEsigTest.Result r = CqEsigTest.verify('c', 'v', 'k', 'https://x/apex/CqEsigCallback', 'Approved');
        System.assert(!r.ok);
        System.assert(r.message.contains('Someone other than the signer'), r.message);
    }

    @IsTest
    static void loginRefused() {
        Test.setMock(HttpCalloutMock.class, new Mock(UserInfo.getUserId(), 400));
        CqEsigTest.Result r = CqEsigTest.verify('c', 'v', 'k', 'https://x/apex/CqEsigCallback', 'Approved');
        System.assert(!r.ok);
        System.assert(r.message.contains('authentication failure'), r.message);
        System.assert(!CqEsigTest.verify(null, 'v', 'k', 'r', null).ok);
    }
}

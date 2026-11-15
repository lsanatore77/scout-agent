/**
 * CqEsigTest: dev test of signing with Salesforce's own login page (OAuth web server flow with PKCE).
 *
 * The signer types their password on Salesforce's real login page in a pop-up, forced to log in again
 * (prompt=login). Our code never sees the password. verify() swaps the one-time code for a token, checks
 * the token belongs to the person signing in this org, reads the login Salesforce recorded, and revokes the
 * token straight away. Nothing is written: this only proves the sign-in step works without the retiring
 * OAuth password flow or SOAP login().
 *
 * Used by the CqEsigTest and CqEsigCallback Visualforce pages. The consumer key is typed into the page.
 */
public with sharing class CqEsigTest {

    public class Result {
        public Boolean ok = false;
        public String message;
        public String userId;
        public String userName;
        public String meaning;
        public String signedAt;
        public Integer ms;
        public List<Login> logins = new List<Login>();
    }
    public class Login {
        public String loginTime; public String loginType; public String status; public String application; public String method;
    }

    /** The org's My Domain, where the login page and token endpoint live. */
    public String orgBase { get { return URL.getOrgDomainUrl().toExternalForm(); } }

    @RemoteAction
    public static Result verify(String code, String verifier, String clientId, String redirectUri, String meaning) {
        Long t0 = System.currentTimeMillis();
        Result r = new Result();
        r.meaning = meaning;
        if (String.isBlank(code) || String.isBlank(verifier) || String.isBlank(clientId) || String.isBlank(redirectUri)) {
            r.message = 'Missing the code, verifier, consumer key or callback URL.';
            return r;
        }
        String base = URL.getOrgDomainUrl().toExternalForm();

        // 1. swap the one-time code for a token (PKCE: the verifier proves this page started the login)
        HttpRequest req = new HttpRequest();
        req.setEndpoint(base + '/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody(String.join(new List<String>{
            'grant_type=authorization_code',
            'code=' + enc(code),
            'client_id=' + enc(clientId),
            'redirect_uri=' + enc(redirectUri),
            'code_verifier=' + enc(verifier)
        }, '&'));
        HttpResponse res = new Http().send(req);
        Map<String, Object> tok;
        try { tok = (Map<String, Object>) JSON.deserializeUntyped(res.getBody()); } catch (Exception e) { tok = new Map<String, Object>(); }
        if (res.getStatusCode() != 200 || tok.get('access_token') == null) {
            r.message = 'Salesforce did not accept the login: ' + String.valueOf(tok.get('error_description') != null ? tok.get('error_description') : res.getBody());
            return r;
        }
        String accessToken = (String) tok.get('access_token');

        // 2. the token must belong to the person signing, in this org
        //    identity URL: https://<host>/id/<orgId>/<userId>
        String idUrl = (String) tok.get('id');
        List<String> parts = idUrl == null ? new List<String>() : idUrl.split('/');
        Id tokenUser; Id tokenOrg;
        try {
            tokenUser = Id.valueOf(parts[parts.size() - 1]);
            tokenOrg = Id.valueOf(parts[parts.size() - 2]);
        } catch (Exception e) { /* left null: fails the check below */ }
        Boolean sameUser = tokenUser == UserInfo.getUserId();
        Boolean sameOrg = tokenOrg == UserInfo.getOrganizationId();

        // 3. revoke the token at once: it was only needed to prove who logged in
        try {
            HttpRequest rv = new HttpRequest();
            rv.setEndpoint(base + '/services/oauth2/revoke');
            rv.setMethod('POST');
            rv.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            rv.setBody('token=' + enc(accessToken));
            new Http().send(rv);
        } catch (Exception e) { /* the token expires on its own */ }

        r.userId = tokenUser;
        if (!sameOrg) { r.message = 'The login was for a different org.'; return r; }
        if (!sameUser) { r.message = 'Someone other than the signer logged in, so the signature is refused.'; return r; }

        // 4. the login Salesforce recorded for this signature (needs permission to view login history)
        try {
            for (LoginHistory h : [
                    SELECT LoginTime, LoginType, LoginSubType, Status, Application, AuthMethodReference
                    FROM LoginHistory WHERE UserId = :UserInfo.getUserId() AND LoginTime >= :Datetime.now().addMinutes(-10)
                    ORDER BY LoginTime DESC LIMIT 3]) {
                Login l = new Login();
                l.loginTime = h.LoginTime.format('h:mm:ss a z');
                l.loginType = h.LoginSubType == null ? h.LoginType : h.LoginType + ' / ' + h.LoginSubType;
                l.status = h.Status; l.application = h.Application; l.method = h.AuthMethodReference;
                r.logins.add(l);
            }
        } catch (Exception e) { /* login history not visible to this user */ }

        r.ok = true;
        r.userName = UserInfo.getName();
        r.signedAt = Datetime.now().format('MMM d, yyyy h:mm:ss a z');
        r.message = 'Signed: ' + r.userName + ', ' + (String.isBlank(meaning) ? 'Approved' : meaning) + ', ' + r.signedAt + '.';
        r.ms = (Integer) (System.currentTimeMillis() - t0);
        return r;
    }

    static String enc(String v) { return EncodingUtil.urlEncode(v, 'UTF-8'); }
}

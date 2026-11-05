/**
 * AskCqService
 * ------------
 * Proof of concept: lets a Lightning page talk to the Scout agent through the Agentforce Agent API,
 * so "Ask CQ" can pop over the PHR workspace instead of living in the side panel.
 *
 * Flow: client-credentials token from this org's My Domain -> create an agent session ->
 * send messages (synchronous) -> end the session when the popover closes.
 *
 * Settings come from AskCqSecrets (consumer key and secret of the External Client App connected to
 * the agent, and the agent's Id). That class is dev only and kept out of git; a blank template is
 * committed. A real build would use a Named Credential instead.
 */
public with sharing class AskCqService {

    public static final String API_BASE = 'https://api.salesforce.com/einstein/ai-agent/v1';

    public class Reply {
        @AuraEnabled public String sessionId;
        @AuraEnabled public String text;
        @AuraEnabled public Integer nextSequence;
    }

    public class AskCqException extends Exception {}

    /** Opens a session with the agent and returns its opening message, if any. */
    @AuraEnabled
    public static Reply startSession(Id recordId, String agentId) {
        Settings s = settings();
        if (String.isNotBlank(agentId)) { s.agentId = agentId; }   // another agent (the Scout Checklist agent, say) through the same pipe
        String token = accessToken(s);
        Map<String, Object> body = new Map<String, Object>{
            'externalSessionKey' => uuid(),
            'instanceConfig' => new Map<String, Object>{ 'endpoint' => orgDomain() },
            'streamingCapabilities' => new Map<String, Object>{ 'chunkTypes' => new List<String>{ 'Text' } },
            'bypassUser' => false
        };
        // Same context the native panel gives the agent, so the script's {!@variables.currentRecordId} works.
        if (recordId != null) {
            body.put('variables', new List<Object>{
                variable('currentRecordId', String.valueOf(recordId)),
                variable('currentObjectApiName', String.valueOf(recordId.getSObjectType())),
                variable('currentPageType', 'record')
            });
        }
        HttpResponse res = send('POST', API_BASE + '/agents/' + s.agentId + '/sessions', token, JSON.serialize(body), null);
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Reply r = new Reply();
        r.sessionId = (String) out.get('sessionId');
        r.text = messagesText(out);
        r.nextSequence = 1;
        if (String.isBlank(r.sessionId)) { throw new AskCqException('The agent did not return a session: ' + res.getBody()); }
        return r;
    }

    /**
     * Sends one message and returns the agent's answer. The record the page is on is named in the
     * first message so the agent knows which complaint or review the question is about.
     */
    @AuraEnabled
    public static Reply sendMessage(String sessionId, Integer sequenceId, String text, Id recordId) {
        Settings s = settings();
        String token = accessToken(s);
        String msg = text;
        if (sequenceId == 1 && recordId != null) {
            msg = 'The record open on screen is ' + recordId + ' (' + recordId.getSObjectType().getDescribe().getLabel() + '). ' + text;
        }
        Map<String, Object> body = new Map<String, Object>{
            'message' => new Map<String, Object>{ 'sequenceId' => sequenceId, 'type' => 'Text', 'text' => msg }
        };
        HttpResponse res = send('POST', API_BASE + '/sessions/' + sessionId + '/messages', token, JSON.serialize(body), null);
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Reply r = new Reply();
        r.sessionId = sessionId;
        r.text = messagesText(out);
        r.nextSequence = sequenceId + 1;
        return r;
    }

    @AuraEnabled
    public static void endSession(String sessionId) {
        if (String.isBlank(sessionId)) { return; }
        Settings s = settings();
        String token = accessToken(s);
        send('DELETE', API_BASE + '/sessions/' + sessionId, token, null, new Map<String, String>{ 'x-session-end-reason' => 'UserRequest' });
    }

    // ---------- helpers ----------

    public class Settings {
        public String consumerKey;
        public String consumerSecret;
        public String agentId;
    }

    @TestVisible private static Settings testSettings;

    @TestVisible
    private static Settings settings() {
        Settings s = new Settings();
        s.consumerKey = testSettings != null ? testSettings.consumerKey : AskCqSecrets.CONSUMER_KEY;
        s.consumerSecret = testSettings != null ? testSettings.consumerSecret : AskCqSecrets.CONSUMER_SECRET;
        s.agentId = testSettings != null ? testSettings.agentId : AskCqSecrets.AGENT_ID;
        if (String.isBlank(s.consumerKey) || String.isBlank(s.consumerSecret) || String.isBlank(s.agentId)) {
            throw new AskCqException('Ask CQ is not set up: AskCqSecrets needs the consumer key, consumer secret and agent Id.');
        }
        return s;
    }

    private static String cachedToken;

    @TestVisible
    private static String accessToken(Settings s) {
        if (cachedToken != null) { return cachedToken; }
        HttpRequest req = new HttpRequest();
        req.setEndpoint(orgDomain() + '/services/oauth2/token');
        req.setMethod('POST');
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');
        req.setBody('grant_type=client_credentials&client_id=' + EncodingUtil.urlEncode(s.consumerKey, 'UTF-8')
            + '&client_secret=' + EncodingUtil.urlEncode(s.consumerSecret, 'UTF-8'));
        req.setTimeout(60000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() != 200) {
            throw new AskCqException('Could not get a token (' + res.getStatusCode() + '): ' + res.getBody());
        }
        Map<String, Object> out = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        cachedToken = (String) out.get('access_token');
        return cachedToken;
    }

    private static HttpResponse send(String method, String url, String token, String body, Map<String, String> extra) {
        HttpRequest req = new HttpRequest();
        req.setEndpoint(url);
        req.setMethod(method);
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Accept', 'application/json');
        if (body != null) {
            req.setHeader('Content-Type', 'application/json');
            req.setBody(body);
        }
        if (extra != null) { for (String k : extra.keySet()) { req.setHeader(k, extra.get(k)); } }
        req.setTimeout(120000);
        HttpResponse res = new Http().send(req);
        if (res.getStatusCode() < 200 || res.getStatusCode() > 299) {
            throw new AskCqException('Agent API ' + method + ' failed (' + res.getStatusCode() + '): ' + res.getBody());
        }
        return res;
    }

    /** Joins the text of every message in an Agent API response. */
    @TestVisible
    private static String messagesText(Map<String, Object> out) {
        List<String> parts = new List<String>();
        Object msgs = out == null ? null : out.get('messages');
        if (msgs instanceof List<Object>) {
            for (Object o : (List<Object>) msgs) {
                Map<String, Object> m = (Map<String, Object>) o;
                String t = (String) m.get('message');
                if (String.isNotBlank(t)) { parts.add(t); }
            }
        }
        return String.join(parts, '\n\n');
    }

    private static Map<String, Object> variable(String name, String value) {
        return new Map<String, Object>{ 'name' => name, 'type' => 'Text', 'value' => value };
    }

    private static String orgDomain() {
        return URL.getOrgDomainUrl().toExternalForm();
    }

    private static String uuid() {
        String h = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return h.substring(0, 8) + '-' + h.substring(8, 12) + '-' + h.substring(12, 16) + '-' + h.substring(16, 20) + '-' + h.substring(20);
    }
}

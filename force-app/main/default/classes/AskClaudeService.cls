/**
 * Ask Claude: a fuller explanation under an Ask CQ answer, from Anthropic's Claude.
 * DEMO ORGS ONLY. Never for FDA-regulated companies or customer production use.
 * Off unless the user has the Ask_Claude custom permission (granted by the Ask Claude Demo permission set).
 * The API key lives only in the Anthropic_Claude External Credential (principal Demo_Key, parameter ApiKey):
 * it is never in code, in the repo or on the page. Claude gets the question, CQ.AI's answer and the step name,
 * nothing else, and cannot see or change any record.
 */
public with sharing class AskClaudeService {
    @TestVisible static final String MODEL = 'claude-sonnet-5-5';
    @TestVisible static Boolean forceEnabled;   // tests only: the custom permission cannot be granted inside a test
    static final Integer MAX_IN = 4000;          // characters kept of the question and of CQ.AI's answer

    static final String SYSTEM_PROMPT =
        'You are Claude, helping a quality professional in a ComplianceQuest demo org. You are given a question the user '
        + 'asked CQ.AI and the answer CQ.AI gave from the org\'s records. Explain or expand on that answer in plain language, '
        + 'in about 150 words or fewer. For anything about this org\'s records, use only the facts in CQ.AI\'s answer: never '
        + 'invent record numbers, dates, counts or names. CQ.AI\'s answer may cover only part of the record (for example only what '
        + 'is still open), so say nothing about what it does not mention: never sum up the record as all done or all outstanding. You may add general quality or regulatory background (for example '
        + '21 CFR Part 7 or ISO 13485) and say when you do. You cannot see or change any record, so do not offer to. '
        + 'Write short paragraphs or "- " bullets, with no headings, tables or bold.';

    /** True when this user may see the Ask Claude button. */
    @AuraEnabled(cacheable=true)
    public static Boolean isEnabled() {
        return forceEnabled != null ? forceEnabled : FeatureManagement.checkPermission('Ask_Claude');
    }

    /** Claude's fuller explanation of one CQ.AI answer. */
    @AuraEnabled
    public static String ask(String question, String cqAnswer, String step) {
        if (!isEnabled()) { throw new AuraHandledException('Ask Claude is not turned on for you.'); }
        if (String.isBlank(cqAnswer)) { throw new AuraHandledException('There is no CQ.AI answer to ask Claude about.'); }
        String prompt = (String.isBlank(question) ? '' : 'The user asked CQ.AI: ' + question.abbreviate(MAX_IN) + '\n\n')
            + 'CQ.AI answered:\n' + cqAnswer.abbreviate(MAX_IN)
            + (String.isBlank(step) ? '' : '\n\nThe user is on the ' + step.abbreviate(80) + ' step.')
            + '\n\nExplain this answer more fully for the user.';
        Map<String, Object> body = new Map<String, Object>{
            'model' => MODEL,
            'max_tokens' => 800,
            'system' => SYSTEM_PROMPT,
            'messages' => new List<Object>{ new Map<String, Object>{ 'role' => 'user', 'content' => prompt } }
        };
        HttpRequest req = new HttpRequest();
        req.setEndpoint('callout:Anthropic_Claude/v1/messages');
        req.setMethod('POST');
        req.setHeader('content-type', 'application/json');
        req.setTimeout(60000);
        req.setBody(JSON.serialize(body));
        HttpResponse res;
        try { res = new Http().send(req); }
        catch (CalloutException e) { throw new AuraHandledException('Claude could not be reached. Try again in a moment.'); }
        if (res.getStatusCode() != 200) { throw new AuraHandledException(failure(res.getStatusCode())); }
        String text = textOf(res.getBody());
        if (String.isBlank(text)) { throw new AuraHandledException('Claude sent back an empty answer.'); }
        return text.trim();
    }

    /** The text blocks of a Messages API reply, joined. */
    @TestVisible static String textOf(String json) {
        Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
        List<String> parts = new List<String>();
        for (Object o : (List<Object>) m.get('content')) {
            Map<String, Object> c = (Map<String, Object>) o;
            if (c.get('type') == 'text') { parts.add((String) c.get('text')); }
        }
        return String.join(parts, '\n');
    }

    /** A plain reason for a failed call. The reply body is never shown. */
    @TestVisible static String failure(Integer status) {
        if (status == 401 || status == 403) { return 'Claude did not accept the API key. An admin can check the key in the Anthropic Claude credential.'; }
        if (status == 429) { return 'Claude is busy right now. Try again in a minute.'; }
        if (status == 529 || status >= 500) { return 'Claude is unavailable right now. Try again shortly.'; }
        return 'Claude could not answer (status ' + status + ').';
    }
}

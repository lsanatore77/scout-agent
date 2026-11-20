/**
 * Turns a free-text / spoken event description into suggested intake answers by calling
 * CQ's managed "Entity Extraction" prompt template (ConnectApi, native Apex — no callout).
 * Returns per-field suggestions (Part resolved to a record), plus the required questions
 * the description did not answer. The LWC shows these for the reporter to confirm/change.
 */
public with sharing class CqEventExtract {

    // Canned model output for tests (ConnectApi.EinsteinLLM is not callable in test context).
    @TestVisible static String mockJson;
    @TestVisible static final String FAIL = 'FAIL';   // tests: makes the CQ.AI read fail

    public class Suggestion {
        @AuraEnabled public String key;        // 'title','part','lot','units','defect', or the question Role
        @AuraEnabled public Id questionId;     // set for question-based suggestions
        @AuraEnabled public String label;
        @AuraEnabled public String value;      // display / canonical answer
        @AuraEnabled public String rawValue;   // exactly what the model returned
        @AuraEnabled public Id recordId;       // resolved record (Part)
        @AuraEnabled public Boolean needsConfirm = false;
    }

    public class Result {
        @AuraEnabled public String title;
        @AuraEnabled public List<Suggestion> suggestions = new List<Suggestion>();
        @AuraEnabled public List<String> stillNeeded = new List<String>();
        @AuraEnabled public String rawJson;
    }

    @AuraEnabled
    public static Result fromDescription(String description) {
        if (String.isBlank(description)) {
            throw new AuraHandledException('Tell me what happened first.');
        }

        List<Event_Question__c> questions = [
            SELECT Id, Order__c, Question__c, Answer_Type__c, Choices__c, Role__c, Required__c
            FROM Event_Question__c WHERE Active__c = true WITH USER_MODE ORDER BY Order__c
        ];

        // Core fields plus one entity per role-bearing question (with allowed values as a hint).
        List<String> entityDefs = new List<String>{
            'TITLE (a short title, up to 10 words)',
            'PART (the product or part name)',
            'LOT (the lot or batch number)',
            'UNITS AFFECTED (how many units failed or were defective, as a number)',
            'DEFECT (what went wrong, a few words)'
        };
        for (Event_Question__c q : questions) {
            if (String.isBlank(q.Role__c) || q.Role__c == 'None' || q.Role__c == 'Lot Or Part') { continue; }
            List<String> choices = choicesFor(q);
            String key = q.Role__c.toUpperCase();
            entityDefs.add(choices.isEmpty() ? key : key + ' (answer: ' + allowedPhrase(choices) + ')');
        }

        // CQ.AI reads the story. If it cannot (no generative AI in the org, CQ's prompt template missing, a timeout),
        // simple rules pick out the title, lot and units, and the questions ask for the rest: never a dead end.
        String raw;
        try { raw = generate(description, String.join(entityDefs, ', ')); } catch (Exception e) { raw = null; }
        Map<String, String> vals = parse(raw);
        if (vals.isEmpty()) { vals = basicRead(description); }

        Result res = new Result();
        res.rawJson = raw;
        res.title = vals.get('TITLE');

        addCore(res, 'title', 'Title', vals.get('TITLE'), false);

        String partRaw = vals.get('PART');
        if (String.isNotBlank(partRaw)) {
            Suggestion s = new Suggestion();
            s.key = 'part'; s.label = 'Part'; s.rawValue = partRaw; s.needsConfirm = true;
            List<CqEventParts.Part> hits = CqEventParts.search(partRaw);
            if (!hits.isEmpty()) {
                s.recordId = hits[0].id;
                s.value = hits[0].partNumber + ' · ' + hits[0].name;
                s.needsConfirm = false;
            } else {
                s.value = partRaw;
            }
            res.suggestions.add(s);
        }

        addCore(res, 'lot', 'Lot', vals.get('LOT'), false);
        addCore(res, 'units', 'Units Affected', vals.get('UNITS AFFECTED'), true); // quantity: always worth a glance
        addCore(res, 'defect', 'Defect', vals.get('DEFECT'), false);

        for (Event_Question__c q : questions) {
            if (String.isBlank(q.Role__c) || q.Role__c == 'None' || q.Role__c == 'Lot Or Part') { continue; }
            String v = vals.get(q.Role__c.toUpperCase());
            if (String.isBlank(v)) {
                if (q.Required__c) { res.stillNeeded.add(q.Question__c); }
                continue;
            }
            Suggestion s = new Suggestion();
            s.key = q.Role__c; s.questionId = q.Id; s.label = q.Question__c;
            s.rawValue = v; s.value = mapChoice(v, choicesFor(q));
            res.suggestions.add(s);
        }
        return res;
    }

    static void addCore(Result res, String key, String label, String val, Boolean confirm) {
        if (String.isBlank(val)) { return; }
        Suggestion s = new Suggestion();
        s.key = key; s.label = label; s.value = val; s.rawValue = val; s.needsConfirm = confirm;
        res.suggestions.add(s);
    }

    static List<String> choicesFor(Event_Question__c q) {
        if (q.Answer_Type__c == 'Yes or No') { return new List<String>{ 'Yes', 'No' }; }
        if (q.Answer_Type__c == 'Choice' && String.isNotBlank(q.Choices__c)) {
            List<String> out = new List<String>();
            for (String c : q.Choices__c.split(';')) { if (String.isNotBlank(c)) { out.add(c.trim()); } }
            return out;
        }
        return new List<String>();
    }

    static String allowedPhrase(List<String> choices) {
        if (choices.size() <= 1) { return String.join(choices, ', '); }
        if (choices.size() == 2) { return choices[0] + ' or ' + choices[1]; }
        List<String> head = new List<String>(choices);
        String last = head.remove(head.size() - 1);
        return String.join(head, ', ') + ', or ' + last;
    }

    static String mapChoice(String val, List<String> choices) {
        if (choices.isEmpty() || String.isBlank(val)) { return val; }
        for (String c : choices) { if (c.equalsIgnoreCase(val.trim())) { return c; } }
        String lv = val.toLowerCase();
        for (String c : choices) {
            String lc = c.toLowerCase();
            if (lv.contains(lc) || lc.contains(lv)) { return c; }
        }
        return val.trim();
    }

    static Map<String, String> parse(String raw) {
        Map<String, String> out = new Map<String, String>();
        if (String.isBlank(raw)) { return out; }
        Integer a = raw.indexOf('{');
        Integer b = raw.lastIndexOf('}');
        if (a < 0 || b < a) { return out; }
        Object top;
        try { top = JSON.deserializeUntyped(raw.substring(a, b + 1)); } catch (Exception e) { return out; }
        if (!(top instanceof Map<String, Object>)) { return out; }
        for (String k : ((Map<String, Object>) top).keySet()) {
            Object v = ((Map<String, Object>) top).get(k);
            String sval = null;
            if (v instanceof Map<String, Object>) {
                Object iv = ((Map<String, Object>) v).get('value');
                sval = (iv == null) ? null : String.valueOf(iv);
            } else if (v != null) {
                sval = String.valueOf(v);
            }
            if (String.isNotBlank(sval) && sval != 'null') {
                String key = k.toUpperCase().trim();
                Integer p = key.indexOf('(');
                if (p > 0) { key = key.substring(0, p).trim(); }
                out.put(key, sval.trim());
            }
        }
        return out;
    }

    static String generate(String description, String entities) {
        if (Test.isRunningTest()) {
            if (mockJson == FAIL) { throw new CalloutException('Template Not found for CQSS_Entity_Extraction_Prompt'); }
            return mockJson;
        }
        ConnectApi.EinsteinPromptTemplateGenerationsInput inp = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        inp.isPreview = false;
        ConnectApi.EinsteinLlmAdditionalConfigInput cfg = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        cfg.applicationName = 'PromptTemplateGenerationsInvocable';
        inp.additionalConfig = cfg;
        inp.inputParams = new Map<String, ConnectApi.WrappedValue>{
            'Input:Description' => wrap(description),
            'Input:Entities' => wrap(entities),
            'Input:Date_Entities' => wrap(String.valueOf(Date.today())),
            'Input:Reason_Required' => wrap('false')
        };
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation r =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('CQSS_Entity_Extraction_Prompt', inp);
        return (r != null && r.generations != null && !r.generations.isEmpty()) ? r.generations[0].text : null;
    }

    /**
     * Without CQ.AI: the title is the story's first words; the lot is the token after "lot" or "batch" (or one like
     * LOT-2011); the units are a number followed by units, items, pieces, parts or devices.
     */
    @TestVisible
    static Map<String, String> basicRead(String description) {
        Map<String, String> out = new Map<String, String>();
        String text = description.normalizeSpace();
        List<String> words = text.split(' ');
        List<String> head = new List<String>();
        for (Integer i = 0; i < words.size() && i < 10; i++) { head.add(words[i]); }
        String title = String.join(head, ' ').removeEnd('.').removeEnd(',');
        out.put('TITLE', (words.size() > 10 ? title + '...' : title).left(255));

        for (Integer i = 0; i < words.size(); i++) {
            String w = words[i].replaceAll('[,.;:)(]+$', '');
            String lw = w.toLowerCase();
            if ((lw.startsWith('lot') || lw.startsWith('batch')) && w.length() > 3 && w.replaceAll('[^0-9]', '').length() > 0
                    && !lw.startsWith('lots')) {
                out.put('LOT', w.toUpperCase());
                break;
            }
            if (lw == 'lot' || lw == 'batch' || lw == 'lot:' || lw == 'batch:') {
                for (Integer j = i + 1; j < words.size() && j <= i + 3; j++) {
                    String n = words[j].replaceAll('[,.;:)(]+$', '');
                    String ln = n.toLowerCase();
                    if (ln == 'number' || ln == 'no' || ln == 'no.' || ln == '#' || ln == 'is') { continue; }
                    if (n.replaceAll('[^0-9]', '').length() > 0) { out.put('LOT', n.removeStart('#').toUpperCase()); }
                    break;
                }
                if (out.containsKey('LOT')) { break; }
            }
        }

        Matcher m = Pattern.compile('(?i)\\b(\\d+)\\s*(units?|items?|pieces?|pcs|parts?|devices?)\\b').matcher(text);
        if (m.find()) { out.put('UNITS AFFECTED', m.group(1)); }
        return out;
    }

    static ConnectApi.WrappedValue wrap(String v) {
        ConnectApi.WrappedValue w = new ConnectApi.WrappedValue();
        w.value = v;
        return w;
    }
}

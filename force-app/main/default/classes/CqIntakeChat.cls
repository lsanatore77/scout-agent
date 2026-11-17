/**
 * The conversational intake. The reporter describes a problem in their own words (typed now, spoken
 * later); CQ.AI reads it, tells them what it understood, and asks only for what is still missing,
 * one gap at a time, until there is enough to send to a reviewer.
 *
 * Understanding is done by CqEventExtract (CQ's managed entity-extraction prompt template, native
 * Apex), so every turn re-reads the whole description and picks up anything added since. The part and
 * lot are resolved through CqEventLotLink (the same resolver the before-insert trigger uses), so the
 * read-back shows the canonical lot and the real part, not the reporter's raw words.
 *
 * Safety and injury are ALWAYS asked, never silently inferred: a quality system should not guess
 * whether someone could get hurt. The AI's guess is offered as a one-tap default, but the reporter
 * confirms it. Everything else the AI may fill on its own.
 */
public with sharing class CqIntakeChat {

    // Questions we never auto-answer from the description, even when the model has a guess.
    static final Set<String> ALWAYS_ASK = new Set<String>{ 'Injury', 'Safety Risk' };

    public class Field {
        @AuraEnabled public String key;
        @AuraEnabled public Id questionId;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Id recordId;
        @AuraEnabled public Boolean needsConfirm = false;
    }

    public class Turn {
        @AuraEnabled public String reply;
        @AuraEnabled public String askKey;
        @AuraEnabled public Id askQuestionId;
        @AuraEnabled public String askQuestion;
        @AuraEnabled public String askSuggested;    // the AI's guess for the pending question, if any
        @AuraEnabled public Boolean askFeedsDescription = false;   // the lot/part prompt: its answer is extra description
        @AuraEnabled public List<String> choices = new List<String>();
        @AuraEnabled public List<Field> understood = new List<Field>();
        @AuraEnabled public List<String> stillNeeded = new List<String>();
        @AuraEnabled public Boolean ready = false;
        @AuraEnabled public String draftJson;
        @AuraEnabled public String reporter;
    }

    @AuraEnabled
    public static Turn start() {
        Turn t = new Turn();
        t.reporter = reporterName();
        t.askKey = 'describe';
        t.reply = 'Tell me what happened, in your own words — what the problem is and which product or lot it was on. '
                + 'You can say it all at once; I’ll ask about anything I still need.';
        return t;
    }

    @AuraEnabled
    public static Turn respond(String stateJson) {
        Map<String, Object> state = new Map<String, Object>();
        if (String.isNotBlank(stateJson)) {
            try { state = (Map<String, Object>) JSON.deserializeUntyped(stateJson); } catch (Exception e) { state = new Map<String, Object>(); }
        }
        String description = str(state.get('description'));

        Turn t = new Turn();
        t.reporter = reporterName();
        if (String.isBlank(description)) { return start(); }

        Map<Id, String> answered = new Map<Id, String>();
        Object ansObj = state.get('answers');
        if (ansObj instanceof List<Object>) {
            for (Object o : (List<Object>) ansObj) {
                if (!(o instanceof Map<String, Object>)) { continue; }
                Map<String, Object> a = (Map<String, Object>) o;
                String qid = str(a.get('questionId'));
                String ans = str(a.get('answer'));
                if (String.isNotBlank(qid) && String.isNotBlank(ans)) { answered.put((Id) qid, ans); }
            }
        }

        CqEventExtract.Result ex = CqEventExtract.fromDescription(description);

        // Pull the core fields out of the extraction, then resolve lot + part canonically.
        String lotRaw = null, defect = null, units = null;
        CqEventExtract.Suggestion partSug = null;
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'lot') { lotRaw = s.value; }
            else if (s.key == 'part') { partSug = s; }
            else if (s.key == 'defect') { defect = s.value; }
            else if (s.key == 'units') { units = s.value; }
        }

        String lotDisplay = String.isBlank(lotRaw) ? null : lotRaw.toUpperCase();
        Id partId = (partSug != null) ? partSug.recordId : null;
        String partLabel = (partSug != null && partSug.recordId != null) ? partSug.value : null;
        Boolean partCertain = partId != null;

        if (String.isNotBlank(lotRaw)) {
            CqEventLotLink.LotMatch lm = CqEventLotLink.resolve(lotRaw);
            if (lm != null && lm.matches == 1) {
                if (String.isNotBlank(lm.lotName)) { lotDisplay = lm.lotName; }   // canonical lot, e.g. 0901 -> L26-0901
                if (partId == null && lm.partId != null) {                        // part the record will actually get
                    partId = lm.partId; partLabel = lm.partLabel; partCertain = true;
                }
            }
        }

        // The read-back.
        Map<Id, String> extractedByQ = new Map<Id, String>();
        Boolean partShown = false;
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            Field f = new Field();
            f.key = s.key; f.questionId = s.questionId; f.label = s.label;
            f.value = s.value; f.recordId = s.recordId; f.needsConfirm = s.needsConfirm;
            if (s.key == 'lot' && lotDisplay != null) { f.value = lotDisplay; }
            if (s.key == 'part') {
                partShown = true;
                if (partCertain) { f.value = partLabel; f.recordId = partId; f.needsConfirm = false; }
            }
            // A still-unconfirmed safety/injury guess wears the "needs confirm" mark, so it never looks settled.
            if (s.questionId != null) {
                extractedByQ.put(s.questionId, s.value);
                if (ALWAYS_ASK.contains(s.key) && !answered.containsKey(s.questionId)) { f.needsConfirm = true; }
            }
            t.understood.add(f);
        }
        if (!partShown && partCertain) {
            Field f = new Field();
            f.key = 'part'; f.label = 'Part'; f.value = partLabel; f.recordId = partId; f.needsConfirm = false;
            t.understood.add(f);
        }

        // The next gap: required questions not yet answered. Safety/injury always count as a gap
        // until the reporter answers them, even when the AI produced a guess.
        List<Event_Question__c> active = [
            SELECT Id, Order__c, Question__c, Answer_Type__c, Choices__c, Role__c, Help_Text__c, Required__c
            FROM Event_Question__c WHERE Active__c = true WITH USER_MODE ORDER BY Order__c
        ];
        Id injuryQId, whereQId;
        for (Event_Question__c q : active) {
            if (q.Role__c == 'Injury') { injuryQId = q.Id; }
            if (q.Role__c == 'Where Found') { whereQId = q.Id; }
        }
        // "Who was hurt?" is only asked once the reporter has confirmed an injury.
        Boolean injuryYes = injuryQId != null && 'Yes'.equalsIgnoreCase(answered.get(injuryQId));
        // Where Found may be answered or inferred; the customer/supplier follow-ups key off its value.
        String whereVal = whereQId == null ? null : (answered.containsKey(whereQId) ? answered.get(whereQId) : extractedByQ.get(whereQId));
        // The lot/part prompt only fires when we have neither.
        Boolean noPartNoLot = String.isBlank(lotRaw) && partId == null;

        Event_Question__c nextGap;
        String nextGuess;
        for (Event_Question__c q : active) {
            Boolean isGap;
            String role = q.Role__c;
            if (role == 'Injured Person') {
                isGap = injuryYes && !answered.containsKey(q.Id) && !extractedByQ.containsKey(q.Id);
            } else if (role == 'Customer') {
                isGap = 'At a Customer'.equalsIgnoreCase(whereVal) && !answered.containsKey(q.Id) && !extractedByQ.containsKey(q.Id);
            } else if (role == 'Supplier') {
                isGap = 'At a Supplier'.equalsIgnoreCase(whereVal) && !answered.containsKey(q.Id) && !extractedByQ.containsKey(q.Id);
            } else if (role == 'Lot Or Part') {
                isGap = noPartNoLot && !answered.containsKey(q.Id);
            } else if (q.Required__c) {
                Boolean mustAsk = ALWAYS_ASK.contains(role);
                isGap = !(answered.containsKey(q.Id) || (extractedByQ.containsKey(q.Id) && !mustAsk));
            } else {
                isGap = false;
            }
            if (isGap) {
                t.stillNeeded.add(q.Question__c);
                if (nextGap == null) { nextGap = q; nextGuess = extractedByQ.get(q.Id); }
            }
        }

        String rb = readback(partLabel, partCertain, lotDisplay, defect, units);

        if (nextGap != null) {
            t.askKey = String.isBlank(nextGap.Role__c) ? 'question' : nextGap.Role__c;
            t.askQuestionId = nextGap.Id;
            t.askQuestion = nextGap.Question__c;
            t.askSuggested = nextGuess;
            t.askFeedsDescription = (nextGap.Role__c == 'Lot Or Part');
            t.choices = choicesFor(nextGap);
            String tail = String.isNotBlank(nextGuess)
                ? ' (From what you said I’d put ' + nextGuess + ' — tap to confirm or change.)'
                : (String.isBlank(nextGap.Help_Text__c) ? '' : ' (' + nextGap.Help_Text__c + ')');
            t.reply = (rb == null ? '' : rb + ' ') + nextGap.Question__c + tail;
            return t;
        }

        t.ready = true;
        t.askKey = 'ready';
        t.reply = (rb == null ? 'Got it.' : rb) + ' That’s everything I need — want me to send this to a reviewer?';
        t.draftJson = draft(description, ex, answered, lotDisplay, partId);
        return t;
    }

    static String readback(String partLabel, Boolean partCertain, String lotDisplay, String defect, String units) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(partLabel)) { parts.add(partLabel + (partCertain ? '' : ' (is that right?)')); }
        if (String.isNotBlank(lotDisplay)) { parts.add('lot ' + lotDisplay); }
        if (String.isNotBlank(defect)) { parts.add(defect); }
        if (String.isNotBlank(units)) { parts.add(units + ' unit(s)'); }
        if (parts.isEmpty()) { return null; }
        return 'Got it — ' + String.join(parts, ', ') + '.';
    }

    static String draft(String description, CqEventExtract.Result ex, Map<Id, String> answered, String lotDisplay, Id partId) {
        Map<String, Object> d = new Map<String, Object>();
        d.put('problem', description);
        if (String.isNotBlank(ex.title)) { d.put('title', ex.title); }
        if (String.isNotBlank(lotDisplay)) { d.put('lot', lotDisplay); }
        if (partId != null) { d.put('partId', partId); }
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'units' && String.isNotBlank(s.value)) {
                try { d.put('units', Decimal.valueOf(s.value.replaceAll('[^0-9.]', ''))); } catch (Exception e) {}
            }
        }
        // answers: the reporter's answers win; the AI's own extracted answers fill the rest.
        Map<Id, String> all = new Map<Id, String>(answered);
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.questionId != null && String.isNotBlank(s.value) && !all.containsKey(s.questionId)) {
                all.put(s.questionId, s.value);
            }
        }
        List<Map<String, Object>> answers = new List<Map<String, Object>>();
        for (Id qid : all.keySet()) {
            answers.add(new Map<String, Object>{ 'questionId' => qid, 'answer' => all.get(qid) });
        }
        d.put('answers', answers);
        return JSON.serialize(d);
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

    static String reporterName() {
        return [SELECT Name FROM User WHERE Id = :UserInfo.getUserId()].Name;
    }

    static String str(Object o) { return o == null ? null : String.valueOf(o); }
}

/**
 * The conversational intake. The reporter describes a problem in their own words (typed now, spoken
 * later); CQ.AI reads it, tells them what it understood, and asks only for what is still missing,
 * one gap at a time, until there is enough to send to a reviewer.
 *
 * This is the chat engine, not the form. Understanding is done by CqEventExtract (CQ's managed
 * entity-extraction prompt template, native Apex), so every turn re-reads the whole description and
 * picks up anything the reporter has added since. The LWC holds the conversation; each turn it sends
 * the running description plus any answers given to direct questions, and gets back CQ.AI's next turn.
 *
 * Text only for now. When enough is in hand, the turn carries a draft the LWC submits through
 * CqEventIntake.submitReport (the same path the suggestions form uses).
 */
public with sharing class CqIntakeChat {

    public class Field {
        @AuraEnabled public String key;        // title / part / lot / units / defect, or a question Role
        @AuraEnabled public Id questionId;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Id recordId;       // resolved Part
        @AuraEnabled public Boolean needsConfirm = false;
    }

    public class Turn {
        @AuraEnabled public String reply;                 // CQ.AI's message this turn
        @AuraEnabled public String askKey;                // 'describe' | a question Role | 'ready'
        @AuraEnabled public Id askQuestionId;             // the question CQ.AI is asking, if any
        @AuraEnabled public String askQuestion;           // its text
        @AuraEnabled public List<String> choices = new List<String>();   // quick replies, if a choice question
        @AuraEnabled public List<Field> understood = new List<Field>();  // the readback
        @AuraEnabled public List<String> stillNeeded = new List<String>();
        @AuraEnabled public Boolean ready = false;        // enough to send
        @AuraEnabled public String draftJson;             // payload for CqEventIntake.submitReport when ready
        @AuraEnabled public String reporter;
    }

    /** The opening turn, before the reporter has said anything. */
    @AuraEnabled
    public static Turn start() {
        Turn t = new Turn();
        t.reporter = reporterName();
        t.askKey = 'describe';
        t.reply = 'Tell me what happened, in your own words — what the problem is and which product or lot it was on. '
                + 'You can say it all at once; I’ll ask about anything I still need.';
        return t;
    }

    /**
     * One turn of the conversation.
     * stateJson = { "description": "<everything the reporter has said so far>",
     *               "answers": [ { "questionId": "..", "role": "..", "answer": ".." } ] }
     */
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

        // Answers the reporter has already given to specific questions (button taps or earlier turns).
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

        // Re-read the whole description with CQ's extractor.
        CqEventExtract.Result ex = CqEventExtract.fromDescription(description);

        // The readback: the core fields CQ.AI pulled out, plus any question it already answered.
        Map<Id, String> extractedByQ = new Map<Id, String>();
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            Field f = new Field();
            f.key = s.key; f.questionId = s.questionId; f.label = s.label;
            f.value = s.value; f.recordId = s.recordId; f.needsConfirm = s.needsConfirm;
            t.understood.add(f);
            if (s.questionId != null) { extractedByQ.put(s.questionId, s.value); }
        }

        // Which required questions are still unanswered (not extracted, not given)?
        List<Event_Question__c> required = [
            SELECT Id, Order__c, Question__c, Answer_Type__c, Choices__c, Role__c, Help_Text__c
            FROM Event_Question__c WHERE Active__c = true AND Required__c = true WITH USER_MODE ORDER BY Order__c
        ];
        Event_Question__c nextGap;
        for (Event_Question__c q : required) {
            Boolean have = answered.containsKey(q.Id) || extractedByQ.containsKey(q.Id);
            if (!have) {
                t.stillNeeded.add(q.Question__c);
                if (nextGap == null) { nextGap = q; }
            }
        }

        String readback = readback(ex);

        if (nextGap != null) {
            t.askKey = String.isBlank(nextGap.Role__c) ? 'question' : nextGap.Role__c;
            t.askQuestionId = nextGap.Id;
            t.askQuestion = nextGap.Question__c;
            t.choices = choicesFor(nextGap);
            t.reply = (readback == null ? '' : readback + ' ') + nextGap.Question__c
                    + (String.isBlank(nextGap.Help_Text__c) ? '' : ' (' + nextGap.Help_Text__c + ')');
            return t;
        }

        // Nothing required is missing.
        t.ready = true;
        t.askKey = 'ready';
        t.reply = (readback == null ? 'Got it.' : readback)
                + ' That’s everything I need — want me to send this to a reviewer?';
        t.draftJson = draft(description, ex, answered);
        return t;
    }

    /** A short, natural summary of what CQ.AI understood: "Got it — a CardioFlow balloon, lot L26-0908, slow to deflate, 8 units." */
    static String readback(CqEventExtract.Result ex) {
        List<String> parts = new List<String>();
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'part' && String.isNotBlank(s.value)) { parts.add(s.value + (s.needsConfirm ? ' (is that right?)' : '')); }
        }
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'lot' && String.isNotBlank(s.value)) { parts.add('lot ' + s.value); }
        }
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'defect' && String.isNotBlank(s.value)) { parts.add(s.value); }
        }
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'units' && String.isNotBlank(s.value)) { parts.add(s.value + ' unit(s)'); }
        }
        if (parts.isEmpty()) { return null; }
        return 'Got it — ' + String.join(parts, ', ') + '.';
    }

    /** Build the payload CqEventIntake.submitReport expects. */
    static String draft(String description, CqEventExtract.Result ex, Map<Id, String> answered) {
        Map<String, Object> d = new Map<String, Object>();
        d.put('problem', description);
        if (String.isNotBlank(ex.title)) { d.put('title', ex.title); }
        for (CqEventExtract.Suggestion s : ex.suggestions) {
            if (s.key == 'lot' && String.isNotBlank(s.value)) { d.put('lot', s.value); }
            if (s.key == 'part' && s.recordId != null) { d.put('partId', s.recordId); }
            if (s.key == 'units' && String.isNotBlank(s.value)) {
                try { d.put('units', Decimal.valueOf(s.value.replaceAll('[^0-9.]', ''))); } catch (Exception e) {}
            }
        }
        // answers: everything extracted against a question, plus everything the reporter gave directly
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

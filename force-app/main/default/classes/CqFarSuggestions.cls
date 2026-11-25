/**
 * CqFarSuggestions: CQ.AI's suggestions on a Field Action Review, and what people decided, in the review's audit trail.
 *
 * CQ.AI suggests from facts in CQ: the risk level (from the risk score), the outcome, a field action to join, and the
 * scope of a new field action. Each suggestion is recorded once, the first time the review is opened while it is being
 * worked on, with the facts it rests on and the records they come from, as they stood then. It is recorded again only
 * when the suggestion itself changes (for example the score moves because a new complaint arrived).
 *
 * When the coordinator submits the recommendation, each choice is recorded against the suggestion it answers:
 * Accepted, or Changed with CQ.AI's value, the person's value and a reason. Because the suggestions rest on facts,
 * choosing differently needs a reason: submit is refused without one.
 *
 * Entries are written through CqFarAudit (system mode) and, like every audit entry, can never be changed or deleted.
 */
public with sharing class CqFarSuggestions {
    public static final String SUGGESTED = 'CQ.AI Suggested';
    public static final String ACCEPTED = 'Accepted';
    public static final String CHANGED = 'Changed';
    public static final String CQ_AI = 'CQ.AI';

    public static final String RISK = 'Risk Level';
    public static final String OUTCOME = 'Outcome';
    public static final String FA = 'Field Action';
    public static final String SCOPE = 'Scope';
    public static final String NEW_FA = 'Start a New Field Action';

    private static final Integer MAX_SOURCES = 12;

    public class Source {
        public String label; public String id;
        public Source(String label, Id id) { this.label = label; this.id = id == null ? null : String.valueOf(id); }
    }
    /** One suggestion: what CQ.AI suggests (choice), how the trail words it (value), and the facts with their records. */
    public class Item {
        public String key; public String choice; public String value;
        public List<String> facts = new List<String>();
        public List<Source> sources = new List<Source>();
        Item(String key, String choice, String value) { this.key = key; this.choice = choice; this.value = value; }
        void source(String label, Id id) {
            if (sources.size() >= MAX_SOURCES || String.isBlank(label)) { return; }
            for (Source s : sources) { if (s.label == label) { return; } }
            sources.add(new Source(label, id));
        }
    }
    /** What the screen sends with the recommendation: the field action chosen, and the reasons for choosing differently. */
    public class Decisions {
        public String faChoice;
        public Map<String, String> reasons = new Map<String, String>();
    }

    /** Called by the workspace when it opens a review that is being worked on. Records any suggestion not yet in the trail. */
    @AuraEnabled
    public static void note(Id recordId) {
        Field_Action_Review__c r = [SELECT Name, Status__c FROM Field_Action_Review__c WHERE Id = :recordId WITH USER_MODE];
        if (!CqFarChecklist.OPEN.contains(r.Status__c)) { return; }
        CqFieldActionReview.View v = CqFieldActionReview.getView(recordId);
        record(recordId, r.Name, items(v, CqFieldActionLots.scopeFor(v)));
    }

    /** The suggestions CQ.AI makes on this review now. */
    public static List<Item> items(CqFieldActionReview.View v, CqFieldActionLots.Scope s) {
        List<Item> out = new List<Item>();

        // Risk level, from the risk score: each factor is a fact
        if (String.isNotBlank(v.band)) {
            Item riskItem = new Item(RISK, v.band, v.band + ' (score ' + v.score + ' of 100)');
            for (CqFieldActionReview.Factor f : v.factors) { riskItem.facts.add(f.name + ': ' + f.detail + ' (' + f.pts + ' of ' + f.max + ')'); }
            sourceRecords(riskItem, v);
            out.add(riskItem);
        }

        // Outcome
        if (String.isNotBlank(v.suggestedOutcome)) {
            Item oc = new Item(OUTCOME, v.suggestedOutcome, v.suggestedOutcome);
            // the why already says whether the product reached the field
            if (String.isNotBlank(v.suggestedWhy)) { oc.facts.add(v.suggestedWhy); }
            if (v.qtyShipped != null) { oc.facts.add('Quantity shipped: ' + v.qtyShipped.format()); }
            sourceRecords(oc, v);
            out.add(oc);
        }

        // A field action to join (or, when the part has none open, a new one): only when CQ.AI suggests a field action
        if (v.suggestedOutcome == 'Field Action Needed') {
            CqFieldActionReview.Fa joinFa;
            for (CqFieldActionReview.Fa f : v.fieldActions) { if (f.suggested) { joinFa = f; break; } }
            if (joinFa != null) {
                Item faItem = new Item(FA, joinFa.id, 'Join ' + joinFa.name);
                faItem.facts.add(joinFa.why + (String.isBlank(joinFa.title) ? '' : ': ' + joinFa.title));
                if (String.isNotBlank(joinFa.lots)) { faItem.facts.add('Lots covered: ' + joinFa.lots); }
                faItem.source(joinFa.name, joinFa.id);
                out.add(faItem);
            } else if (v.fieldActions.isEmpty()) {
                Item faItem = new Item(FA, 'new', NEW_FA);
                faItem.facts.add('No open field action on ' + (v.partName == null ? 'this part' : v.partName) + '.');
                out.add(faItem);
            }
        }

        // Scope of a new field action
        if (s != null && String.isNotBlank(s.suggested) && v.suggestedOutcome == 'Field Action Needed') {
            Item sc = new Item(SCOPE, s.suggested, s.suggested);
            if (String.isNotBlank(s.why)) { sc.facts.add(s.why); }
            for (CqFieldActionLots.Lot l : s.lots) {
                if (!l.suggested) { continue; }
                sc.facts.add('Lot ' + l.name + ': ' + l.why);
                sc.source('Lot ' + l.name, l.id);
            }
            out.add(sc);
        }
        return out;
    }

    /** The review's source record, the records on the same lot, and the signals that count toward the score. */
    private static void sourceRecords(Item it, CqFieldActionReview.View v) {
        if (v.sourceId != null) { it.source(v.sourceName, v.sourceId); }
        for (CqFieldActionReview.Rec r : v.records) { if (r.sameLot) { it.source(r.name, r.id); } }
        for (CqFieldActionReview.Sig g : v.signals) { if (g.counts) { it.source(g.name, g.id); } }
    }

    /** Writes each suggestion that is new or has changed since the last one. Returns the latest suggestion entry per key. */
    public static Map<String, Id> record(Id recordId, String reviewName, List<Item> items) {
        Map<String, Field_Action_Review_Audit__c> last = latest(recordId);
        Map<String, Field_Action_Review_Audit__c> fresh = new Map<String, Field_Action_Review_Audit__c>();
        for (Item it : items) {
            Field_Action_Review_Audit__c had = last.get(it.key);
            if (had != null && had.New_Value__c == it.value) { continue; }
            fresh.put(it.key, new Field_Action_Review_Audit__c(
                Field_Action_Review__c = recordId, Record_Id__c = String.valueOf(recordId), Record_Name__c = reviewName,
                Action__c = SUGGESTED, Suggestion_Key__c = it.key, Field_Label__c = it.key,
                Old_Value__c = it.choice, New_Value__c = it.value.left(32768),
                Facts__c = String.join(it.facts, '\n').left(32768), Sources__c = JSON.serialize(it.sources).left(32768),
                Changed_By__c = CQ_AI, Request_Id__c = CqFarAudit.request()));
        }
        CqFarAudit.write(fresh.values());
        Map<String, Id> out = new Map<String, Id>();
        for (String k : last.keySet()) { out.put(k, last.get(k).Id); }
        for (String k : fresh.keySet()) { out.put(k, fresh.get(k).Id); }
        return out;
    }

    private static Map<String, Field_Action_Review_Audit__c> latest(Id recordId) {
        Map<String, Field_Action_Review_Audit__c> out = new Map<String, Field_Action_Review_Audit__c>();
        for (Field_Action_Review_Audit__c e : [
                SELECT Id, Suggestion_Key__c, New_Value__c FROM Field_Action_Review_Audit__c
                WHERE Record_Id__c = :String.valueOf(recordId) AND Action__c = :SUGGESTED ORDER BY CreatedDate DESC, Name DESC LIMIT 200]) {
            if (!out.containsKey(e.Suggestion_Key__c)) { out.put(e.Suggestion_Key__c, e); }
        }
        return out;
    }

    /**
     * The coordinator's choices against CQ.AI's suggestions, called as the recommendation goes to the committee.
     * A choice that differs from the suggestion needs a reason; without one nothing is submitted.
     */
    public static void decide(Id recordId, String riskLevel, String chosenOutcome, String chosenScope, String decisionsJson) {
        // (Apex names ignore case: the parameters must not be called outcome or scope, or they would hide OUTCOME and SCOPE)
        // the old Field Action Workspace sends no decisions: its choices are still recorded, but it cannot ask for reasons
        Boolean asked = String.isNotBlank(decisionsJson);
        Decisions d = asked ? (Decisions) JSON.deserialize(decisionsJson, Decisions.class) : new Decisions();
        if (d.reasons == null) { d.reasons = new Map<String, String>(); }
        CqFieldActionReview.View v = CqFieldActionReview.getView(recordId);
        List<Item> items = items(v, CqFieldActionLots.scopeFor(v));

        Map<String, String> chosen = new Map<String, String>{ RISK => riskLevel, OUTCOME => chosenOutcome };
        Boolean needed = chosenOutcome == 'Field Action Needed';
        if (needed && String.isNotBlank(d.faChoice)) { chosen.put(FA, d.faChoice); }
        if (needed && d.faChoice == 'new' && String.isNotBlank(chosenScope)) { chosen.put(SCOPE, chosenScope); }

        List<Item> answered = new List<Item>();
        for (Item it : items) {
            if (!chosen.containsKey(it.key)) { continue; }
            if (asked && chosen.get(it.key) != it.choice && String.isBlank(d.reasons.get(it.key))) {
                String m = 'Give a reason for choosing differently from CQ.AI: ' + it.key + '.';
                AuraHandledException e = new AuraHandledException(m); e.setMessage(m);
                throw e;
            }
            answered.add(it);
        }

        Map<String, Id> sug = record(recordId, v.name, items);
        Map<Id, String> faNames = new Map<Id, String>();
        for (CqFieldActionReview.Fa f : v.fieldActions) { faNames.put(f.id, f.name); }
        List<Field_Action_Review_Audit__c> out = new List<Field_Action_Review_Audit__c>();
        for (Item it : answered) {
            String mine = chosen.get(it.key);
            Boolean same = mine == it.choice;
            out.add(new Field_Action_Review_Audit__c(
                Field_Action_Review__c = recordId, Record_Id__c = String.valueOf(recordId), Record_Name__c = v.name,
                Action__c = same ? ACCEPTED : CHANGED, Suggestion_Key__c = it.key, Field_Label__c = it.key, Suggestion__c = sug.get(it.key),
                Old_Value__c = words(it.key, it.choice, faNames), New_Value__c = words(it.key, mine, faNames),
                Reason__c = same || String.isBlank(d.reasons.get(it.key)) ? null : d.reasons.get(it.key).trim().left(32768),
                Changed_By__c = CqFarAudit.who().left(255), Request_Id__c = CqFarAudit.request()));
        }
        CqFarAudit.write(out);

        // on the record too, for reports: what CQ.AI suggested beside what was chosen, and the reasons for choosing differently
        Field_Action_Review__c rec = new Field_Action_Review__c(Id = recordId, CQAI_Suggested_Risk_Level__c = null,
            CQAI_Suggested_Outcome__c = null, CQAI_Suggested_Scope__c = null);
        for (Item it : items) {
            if (it.key == RISK) { rec.CQAI_Suggested_Risk_Level__c = it.choice; }
            else if (it.key == OUTCOME) { rec.CQAI_Suggested_Outcome__c = it.choice; }
            else if (it.key == SCOPE) { rec.CQAI_Suggested_Scope__c = it.choice; }
        }
        rec.Risk_Level_Reason__c = reasonFor(d, RISK, chosen, items);
        rec.Outcome_Reason__c = reasonFor(d, OUTCOME, chosen, items);
        rec.Scope_Reason__c = reasonFor(d, SCOPE, chosen, items);
        String typeWhy = d.reasons.get('Action Type');
        rec.Action_Type_Reason__c = String.isBlank(typeWhy) ? null : typeWhy.trim().left(32768);
        update rec;
    }

    /** The reason given for choosing differently from CQ.AI on one suggestion, or null when the choice was CQ.AI's. */
    private static String reasonFor(Decisions d, String key, Map<String, String> chosen, List<Item> items) {
        String why = d.reasons.get(key);
        if (String.isBlank(why) || !chosen.containsKey(key)) { return null; }
        for (Item it : items) { if (it.key == key && it.choice == chosen.get(key)) { return null; } }
        return why.trim().left(32768);
    }

    /** A choice as the trail shows it: a field action by its number, a new one in words. */
    private static String words(String key, String choice, Map<Id, String> faNames) {
        if (key != FA || choice == null) { return choice; }
        if (choice == 'new') { return NEW_FA; }
        try { String n = faNames.get(Id.valueOf(choice)); return n == null ? choice : 'Join ' + n; } catch (Exception e) { return choice; }
    }
}

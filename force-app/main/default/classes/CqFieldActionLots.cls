/**
 * CqFieldActionLots: the scope of a field action, decided in the Field Action Review.
 *
 * A review that starts a new Field Action recommends Full (every lot of the part on record in CQ) or Partial (named lots).
 * CQ.AI suggests one of the two and the lots, from the signals on the review. The lots are kept as Field Action Lots:
 * on the review while it is with the committee, and on the Field Action once the committee approves.
 * A review that joins an open Field Action brings its own lot.
 */
public with sharing class CqFieldActionLots {
    public class Lot {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Decimal built; @AuraEnabled public Date made;
        @AuraEnabled public Integer records = 0; @AuraEnabled public Integer signals = 0;
        @AuraEnabled public Boolean known = false;      // has a CQ lot record; a lot number found only on a record does not
        @AuraEnabled public Boolean thisLot = false; @AuraEnabled public Boolean suggested = false; @AuraEnabled public String why;
    }
    public class Scope {
        @AuraEnabled public List<Lot> lots = new List<Lot>();            // this review's lot, then suggested lots, then the rest
        @AuraEnabled public String suggested; @AuraEnabled public String why;
        @AuraEnabled public String scope;                                 // as recommended: Full or Partial
        @AuraEnabled public List<String> chosen = new List<String>();     // the lots the recommendation covers
    }

    @AuraEnabled
    public static Scope getScope(Id recordId) {
        Scope s = build(CqFieldActionReview.getView(recordId));
        s.scope = [SELECT Scope__c FROM Field_Action_Review__c WHERE Id = :recordId].Scope__c;
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action_Review__c = :recordId ORDER BY Lot_Number__c LIMIT 500]) {
            s.chosen.add(l.Lot_Number__c);
        }
        return s;
    }

    /**
     * The lots of the part and CQ.AI's suggestion. Partial unless a Spread signal shows the same failure on more than one lot.
     * A lot is suggested when it is the review's own lot, has a signal of its own at Assess or above,
     * or shares a component lot with the review's lot.
     */
    private static Scope build(CqFieldActionReview.View v) {
        Scope s = new Scope();
        Map<String, Lot> byName = new Map<String, Lot>();
        if (v.partName != null) {
            for (compliancequest__SQX_Lot_Info__c l : [
                    SELECT Id, Name, compliancequest__Manufacturing_Date__c, Batch__r.cqext__Quantity__c, Batch__r.cqext__Actual_Yield__c
                    FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c = :v.partName ORDER BY Name LIMIT 500]) {
                Lot x = new Lot(); x.id = l.Id; x.name = l.Name; x.known = true; x.made = l.compliancequest__Manufacturing_Date__c;
                Decimal yield = l.Batch__r?.cqext__Actual_Yield__c;
                x.built = yield != null && yield > 0 ? yield : l.Batch__r?.cqext__Quantity__c;
                byName.put(x.name, x);
            }
        }
        // records per lot; a lot that appears on a record but has no CQ lot record still counts
        List<String> seen = new List<String>();
        if (v.lot != null) { seen.add(v.lot); }     // the record this review is about
        for (CqFieldActionReview.Rec r : v.records) { if (r.lot != null) { seen.add(r.lot); } }
        for (String n : seen) {
            if (!byName.containsKey(n)) { Lot x = new Lot(); x.name = n; byName.put(n, x); }
            byName.get(n).records++;
        }

        Map<String, List<String>> reasons = new Map<String, List<String>>();
        if (v.lot != null) { byName.get(v.lot).thisLot = true; reasons.put(v.lot, new List<String>{ 'The lot on this review' }); }
        Map<Id, String> code = new Map<Id, String>();
        for (Signal__c g : [SELECT Id, Rule__r.Code__c FROM Signal__c WHERE Id IN :ids(v.signals)]) { code.put(g.Id, g.Rule__r?.Code__c); }
        CqFieldActionReview.Sig spread;
        for (CqFieldActionReview.Sig g : v.signals) {      // Assess or Escalate, not dismissed
            Map<String, String> named = new Map<String, String>();     // lot -> why this signal points at it
            if (code.get(g.id) == 'SHARED_COMPONENT_LOT') {
                if (g.thisLot) {
                    for (CqFieldActionReview.Rec r : g.records) { if (r.lot != null && r.lot != v.lot) { named.put(r.lot, 'Shares component lot ' + g.lot + ' with this lot'); } }
                }
            } else if (g.lot != null) {
                named.put(g.lot, g.rule + ' at ' + g.strength);
            }
            for (String n : named.keySet()) {
                Lot x = byName.get(n);
                if (x == null) { continue; }
                x.signals++;
                if (!reasons.containsKey(n)) { reasons.put(n, new List<String>()); }
                reasons.get(n).add(named.get(n));
            }
            if (spread == null && g.counts && code.get(g.id) == 'SPREAD') { spread = g; }
        }
        List<Lot> first = new List<Lot>(); List<Lot> picked = new List<Lot>(); List<Lot> rest = new List<Lot>(); List<String> names = new List<String>();
        List<String> order = new List<String>(byName.keySet()); order.sort();
        for (String n : order) {
            Lot x = byName.get(n);
            x.suggested = reasons.containsKey(n);
            if (x.suggested) {
                List<String> why = reasons.get(n);
                x.why = String.join(why.size() > 2 ? new List<String>{ why[0], why[1] } : why, '; ');
                names.add(n);
            }
            if (x.thisLot) { first.add(x); } else if (x.suggested) { picked.add(x); } else { rest.add(x); }
        }
        s.lots.addAll(first); s.lots.addAll(picked); s.lots.addAll(rest);
        if (spread != null) {
            s.suggested = 'Full';
            s.why = 'Spread at ' + spread.strength + ': ' + spread.label + '. The same failure is on more than one lot, so it is unlikely to be limited to one batch.';
        } else {
            s.suggested = 'Partial';
            s.why = (names.isEmpty() ? 'No lot is recorded on this review.' : names.size() == 1 ? 'The evidence is on lot ' + names[0] + '.'
                : names.size() + ' lots have signals of their own: ' + String.join(names, ', ') + '.') + ' No Spread signal shows the same failure across lots.';
        }
        return s;
    }
    private static Set<Id> ids(List<CqFieldActionReview.Sig> signals) {
        Set<Id> out = new Set<Id>();
        for (CqFieldActionReview.Sig g : signals) { out.add(g.id); }
        return out;
    }

    /** Sends the recommendation to the committee (see CqFarCommittee) with its scope and lots. */
    @AuraEnabled
    public static CqFieldActionReview.View submitToCommittee(Id recordId, String hazard, String summary, Integer score, String riskLevel,
                                                             String outcome, String rationale, String draft, String team,
                                                             Boolean emergency, String emergencyReason, String scope, List<String> lots) {
        // scope applies to a new field action; a review that joins one brings its own lot
        if (outcome != 'Field Action Needed' || String.isBlank(scope)) { scope = null; }
        if (scope != null && scope != 'Full' && scope != 'Partial') { throw new AuraHandledException('Choose Full or Partial.'); }
        if (scope == 'Partial' && (lots == null || lots.isEmpty())) { throw new AuraHandledException('Choose at least one lot.'); }
        CqFarCommittee.submitToCommittee(recordId, hazard, summary, score, riskLevel, outcome, rationale, draft, team, emergency, emergencyReason);

        delete [SELECT Id FROM Field_Action_Lot__c WHERE Field_Action_Review__c = :recordId AND Field_Action__c = null];
        update new Field_Action_Review__c(Id = recordId, Scope__c = scope);
        if (outcome == 'Field Action Needed') {
            CqFieldActionReview.View v = CqFieldActionReview.getView(recordId);
            Set<String> want = scope == 'Full' ? null : scope == 'Partial' ? new Set<String>(lots) : new Set<String>{ v.lot };
            List<Field_Action_Lot__c> rows = new List<Field_Action_Lot__c>();
            for (Lot l : build(v).lots) {
                // Full: every lot on record in CQ, and the review's own lot
                if (want == null ? (l.known || l.thisLot) : want.contains(l.name)) {
                    rows.add(new Field_Action_Lot__c(Field_Action_Review__c = recordId, Lot__c = l.id, Lot_Number__c = l.name, Units_Built__c = l.built));
                }
            }
            if (scope == 'Partial' && rows.isEmpty()) { throw new AuraHandledException('Choose at least one lot.'); }
            insert rows;
        }
        return CqFieldActionReview.getView(recordId);
    }

    /**
     * Called by the trigger on CQ Approval, after CqFarCommittee has decided the review.
     * Approved with a field action: the review's lots move onto the Field Action, which takes the review's scope if it has none.
     * Approved with no field action: the lots are dropped. Sent back: they stay on the review for the next submission.
     */
    public static void onClosed(Map<Id, String> statusByApproval) {
        for (Field_Action_Review__c r : [
                SELECT Id, Committee_Approval__c, Scope__c, Field_Action__c, Field_Action__r.Scope__c, Field_Action__r.Lot_Numbers__c,
                       (SELECT Id, Lot_Number__c FROM Lots_In_Scope__r WHERE Field_Action__c = null ORDER BY Lot_Number__c)
                FROM Field_Action_Review__c WHERE Committee_Approval__c IN :statusByApproval.keySet() AND Status__c = 'Decided']) {
            if (statusByApproval.get(r.Committee_Approval__c) != 'Approved') { continue; }
            List<Field_Action_Lot__c> rows = r.Lots_In_Scope__r;
            if (r.Field_Action__c == null) { delete rows; continue; }
            Set<String> has = new Set<String>();
            for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :r.Field_Action__c]) { has.add(l.Lot_Number__c); }
            String now = r.Field_Action__r.Lot_Numbers__c;
            List<String> text = String.isBlank(now) ? new List<String>() : now.split(',\\s*');
            List<Field_Action_Lot__c> move = new List<Field_Action_Lot__c>();
            for (Field_Action_Lot__c l : rows) {
                if (!has.contains(l.Lot_Number__c)) { l.Field_Action__c = r.Field_Action__c; move.add(l); }
                if (!text.contains(l.Lot_Number__c)) { text.add(l.Lot_Number__c); }
            }
            update move;
            Field_Action__c f = new Field_Action__c(Id = r.Field_Action__c, Lot_Numbers__c = String.join(text, ', ').left(255));
            if (r.Field_Action__r.Scope__c == null && r.Scope__c != null) { f.Scope__c = r.Scope__c; }
            update f;
        }
    }
}

/**
 * CqFieldActionLots: the scope of a field action, decided in the Field Action Review.
 *
 * A review that starts a new Field Action recommends Full or Partial; the committee approves that with the decision.
 *  - Full covers every lot of the part, including lots found later.
 *  - Partial starts with the review's lot. The coordinator chooses the rest in the Field Action (Scope step) and the
 *    lot list goes for its own approval there (see CqFieldActionScope).
 * CQ.AI suggests Full or Partial from the signals, and the lots it would look at, shown to the committee as the starting scope.
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

    /** Sends the recommendation to the committee (see CqFarCommittee) with its scope. The lots are chosen later, in the Field Action. */
    @AuraEnabled
    public static CqFieldActionReview.View submitToCommittee(Id recordId, String hazard, String summary, Integer score, String riskLevel,
                                                             String outcome, String rationale, String draft, String team,
                                                             Boolean emergency, String emergencyReason, String scope, List<String> lots) {
        // scope applies to a new field action; a review that joins one brings its own lot
        if (outcome != 'Field Action Needed' || String.isBlank(scope)) { scope = null; }
        if (scope != null && scope != 'Full' && scope != 'Partial') { throw new AuraHandledException('Choose Full or Partial.'); }
        CqFarCommittee.submitToCommittee(recordId, hazard, summary, score, riskLevel, outcome, rationale, draft, team, emergency, emergencyReason);

        update new Field_Action_Review__c(Id = recordId, Scope__c = scope);
        return CqFieldActionReview.getView(recordId);
    }
}

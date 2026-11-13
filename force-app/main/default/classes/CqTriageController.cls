/**
 * CqTriageController: data for the purpose-built triage step on a Nonconformance.
 * Reads CQ's own NC fields, adds CQ.AI suggestions from related records, and saves the
 * Field Action Review decision. Suggestions are rules over CQ data; a person always decides.
 */
public with sharing class CqTriageController {
    public static final Integer REPEAT_DAYS = 90;

    public class Fact {
        @AuraEnabled public String k; @AuraEnabled public String v; @AuraEnabled public Boolean warn;
        public Fact(String k, String v, Boolean warn) { this.k = k; this.v = v; this.warn = warn; }
    }
    public class Card {
        @AuraEnabled public String id; @AuraEnabled public String title; @AuraEnabled public String headline;
        @AuraEnabled public String why; @AuraEnabled public String flag; @AuraEnabled public Boolean isSuggestion;
        @AuraEnabled public List<Fact> facts = new List<Fact>();
    }
    public class FieldAction {
        @AuraEnabled public String status;          // null, 'Not Needed', 'Sent for Review'
        @AuraEnabled public String reason; @AuraEnabled public String setBy; @AuraEnabled public Datetime setOn;
        @AuraEnabled public String suggestion;      // 'Not Needed' or 'Send for Review'
        @AuraEnabled public String suggestionWhy;
    }
    public class Glance {
        @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String description;
        @AuraEnabled public String partName; @AuraEnabled public String partNumber; @AuraEnabled public String lot;
        @AuraEnabled public Decimal lotQuantity; @AuraEnabled public Decimal defectiveQuantity; @AuraEnabled public Date occurred;
        @AuraEnabled public String status; @AuraEnabled public String triageResult;
        @AuraEnabled public List<Card> cards = new List<Card>();
        @AuraEnabled public FieldAction fieldAction;
        @AuraEnabled public List<String> gaps = new List<String>();
    }

    @AuraEnabled
    public static Glance getGlance(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = load(recordId);
        Glance g = new Glance();
        g.name = nc.Name; g.title = nc.compliancequest__NC_Title__c; g.description = nc.compliancequest__Description__c;
        g.partName = nc.compliancequest__SQX_Part__r?.Name; g.partNumber = nc.compliancequest__SQX_Part__r?.compliancequest__Part_Number__c;
        g.lot = nc.compliancequest__Lot_Number__c; g.lotQuantity = nc.compliancequest__Lot_Quantity__c;
        g.defectiveQuantity = nc.compliancequest__Defective_Quantity__c; g.occurred = nc.compliancequest__Occurrence_Date__c;
        g.status = nc.compliancequest__Status__c; g.triageResult = nc.compliancequest__Triage_Result__c;

        // Related records on the same part
        List<compliancequest__SQX_Nonconformance__c> others = new List<compliancequest__SQX_Nonconformance__c>();
        List<compliancequest__SQX_Complaint__c> complaints = new List<compliancequest__SQX_Complaint__c>();
        if (nc.compliancequest__SQX_Part__c != null) {
            Date since = Date.today().addDays(-REPEAT_DAYS);
            others = [SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__Status__c, compliancequest__SQX_Investigation__c,
                             compliancequest__SQX_Investigation__r.Name, CreatedDate
                      FROM compliancequest__SQX_Nonconformance__c
                      WHERE compliancequest__SQX_Part__c = :nc.compliancequest__SQX_Part__c AND Id != :nc.Id AND CreatedDate >= :since
                      ORDER BY CreatedDate DESC LIMIT 200];
            complaints = [SELECT Id, Name, compliancequest__Lot_Number__c FROM compliancequest__SQX_Complaint__c
                          WHERE compliancequest__SQX_Part__c = :nc.compliancequest__SQX_Part__c ORDER BY CreatedDate DESC LIMIT 200];
        }
        Integer sameLot = 0; String openInv; Id openInvId; Integer withInv = 0;
        for (compliancequest__SQX_Nonconformance__c o : others) {
            if (g.lot != null && o.compliancequest__Lot_Number__c == g.lot) { sameLot++; }
            if (o.compliancequest__SQX_Investigation__c != null && o.compliancequest__SQX_Investigation__c != nc.compliancequest__SQX_Investigation__c) {
                withInv++; if (openInv == null) { openInv = o.compliancequest__SQX_Investigation__r.Name; openInvId = o.compliancequest__SQX_Investigation__c; }
            }
        }
        List<String> lotComplaints = new List<String>();
        for (compliancequest__SQX_Complaint__c c : complaints) {
            if (g.lot != null && c.compliancequest__Lot_Number__c == g.lot) { lotComplaints.add(c.Name); }
        }

        // 1. Risk: CQ's Severity x Probability, with both inputs suggested by CqTriageRisk
        CqTriageRisk.Risk rr = CqTriageRisk.getRisk(recordId);
        Card risk = new Card(); risk.id = 'risk'; risk.title = 'Risk'; risk.isSuggestion = true;
        risk.headline = rr.level;
        risk.why = rr.escaped ? rr.escapedWhy + '.' : 'Score ' + rr.score + ' of 25. ' + rr.likelihoodWhy + '.';
        risk.facts.add(new Fact('Severity', CqTriageRisk.SEV[rr.severity - 1] + ' · ' + rr.severityWhy, rr.severityAssumed));
        risk.facts.add(new Fact('Likelihood', CqTriageRisk.LIK[rr.likelihood - 1] + ' · ' + rr.likelihoodWhy, rr.likelihood >= 3));
        risk.facts.add(new Fact('Same lot', sameLot + ' other NC(s) on lot ' + (g.lot == null ? '(none)' : g.lot), sameLot > 0));
        risk.facts.add(new Fact('Complaints', complaints.size() + ' on this part, ' + lotComplaints.size() + ' on this lot', !lotComplaints.isEmpty()));
        if (rr.severityAssumed) { g.gaps.add('Severity is assumed Moderate: nothing on the NC, its failure code or the part sets it.'); }
        g.cards.add(risk);

        // 2. Containment: counts the CQ containment records on this NC (CQ's own Has Containment box lags behind them)
        List<compliancequest__SQX_Containment__c> cons = [
            SELECT Name, compliancequest__Status__c, compliancequest__Is_Complete__c FROM compliancequest__SQX_Containment__c
            WHERE compliancequest__SQX_Nonconformance__c = :nc.Id AND compliancequest__Status__c != 'Void' ORDER BY CreatedDate LIMIT 50];
        Integer openCons = 0; List<String> conLabels = new List<String>();
        for (compliancequest__SQX_Containment__c c : cons) {
            conLabels.add(c.Name + ' (' + c.compliancequest__Status__c + ')');
            if (c.compliancequest__Is_Complete__c != true) { openCons++; }
        }
        Card cont = new Card(); cont.id = 'cont'; cont.title = 'Containment';
        Boolean contained = nc.compliancequest__Has_Containment__c == true || !cons.isEmpty();
        Boolean allDone = contained && openCons == 0;
        cont.isSuggestion = !contained;
        cont.headline = allDone ? 'Contained' : contained ? 'Containment raised' : g.lot == null ? 'No lot recorded' : 'Hold lot ' + g.lot;
        cont.why = (g.lotQuantity == null ? 'Quantity not recorded' : g.lotQuantity.format() + ' in the lot')
            + (allDone ? ', containment complete.' : contained ? ', ' + openCons + ' containment(s) not yet complete.' : ', no containment recorded.');
        cont.flag = contained ? null : 'No containment on this NC yet.';
        cont.facts.add(new Fact('Lot', g.lot == null ? 'Not set' : g.lot, g.lot == null));
        cont.facts.add(new Fact('Quantity', g.lotQuantity == null ? 'Not set' : g.lotQuantity.format(), g.lotQuantity == null));
        cont.facts.add(new Fact('Containment', !cons.isEmpty() ? String.join(conLabels, ', ') : contained ? 'Recorded in CQ' : 'None recorded', !contained));
        cont.facts.add(new Fact('Hold status', 'Not known (no ERP connection)', true));
        g.gaps.add('No ERP or MES connection: lot hold status, stock location and shipped quantities are not known.');
        g.cards.add(cont);

        // 3. Disposition
        Card disp = new Card(); disp.id = 'disp'; disp.title = 'Disposition'; disp.isSuggestion = false;
        disp.headline = 'Your decision'; disp.why = 'Only if not investigating.';
        disp.facts.add(new Fact('Quantity', g.lotQuantity == null ? 'Not set' : g.lotQuantity.format() + ' in lot ' + g.lot, false));
        disp.facts.add(new Fact('Defective', g.defectiveQuantity == null ? 'Not set' : g.defectiveQuantity.format(), g.defectiveQuantity == null));
        if (g.defectiveQuantity == null) { g.gaps.add('Defective quantity is not set on the NC.'); }
        g.cards.add(disp);

        // 4. Investigate
        Card inv = new Card(); inv.id = 'inv'; inv.title = 'Investigate'; inv.isSuggestion = true;
        if (nc.compliancequest__SQX_Investigation__c != null) {
            inv.headline = 'Linked: ' + nc.compliancequest__SQX_Investigation__r.Name; inv.why = 'This NC already has an investigation. Continue with it.';
        } else if (openInv != null) {
            inv.headline = 'Join ' + openInv; inv.why = 'Already investigating another NC on this part.';
        } else if (!others.isEmpty()) {
            inv.headline = 'Open new'; inv.why = 'Repeat issue with no investigation yet.';
        } else {
            inv.headline = 'Not needed'; inv.why = 'First NC on this part in ' + REPEAT_DAYS + ' days.';
        }
        inv.facts.add(new Fact('Other NCs', others.size() + ' on this part in ' + REPEAT_DAYS + ' days', false));
        inv.facts.add(new Fact('With investigation', String.valueOf(withInv), false));
        if (!others.isEmpty()) { inv.facts.add(new Fact('Latest', others[0].Name + ' · ' + others[0].compliancequest__Status__c, false)); }
        g.cards.add(inv);

        // Field Action Review
        FieldAction fa = new FieldAction();
        fa.status = nc.Field_Action_Review__c; fa.reason = nc.Field_Action_Review_Reason__c;
        fa.setBy = nc.Field_Action_Review_By__r?.Name; fa.setOn = nc.Field_Action_Review_On__c;
        if (!lotComplaints.isEmpty()) {
            fa.suggestion = 'Send for Review';
            fa.suggestionWhy = 'Lot ' + g.lot + ' has reached customers: ' + String.join(lotComplaints, ', ') + ' reported on the same lot.';
        } else {
            fa.suggestion = 'Not Needed';
            fa.suggestionWhy = 'No complaints on ' + (g.lot == null ? 'this part' : 'lot ' + g.lot) + '. Shipment data is not connected, so confirm nothing from this lot has shipped.';
        }
        g.fieldAction = fa;
        return g;
    }

    @AuraEnabled
    public static FieldAction setFieldAction(Id recordId, String decision, String reason) {
        if (decision != null && decision != 'Not Needed' && decision != 'Sent for Review') { throw new AuraHandledException('Unknown decision: ' + decision); }
        if (decision == 'Sent for Review' && String.isBlank(reason)) { throw new AuraHandledException('A reason is required to send for review.'); }
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(Id = recordId);
        nc.Field_Action_Review__c = decision;
        nc.Field_Action_Review_Reason__c = decision == 'Sent for Review' ? reason : null;
        nc.Field_Action_Review_By__c = decision == null ? null : UserInfo.getUserId();
        nc.Field_Action_Review_On__c = decision == null ? null : Datetime.now();
        update nc;
        return getGlance(recordId).fieldAction;
    }

    private static compliancequest__SQX_Nonconformance__c load(Id recordId) {
        return [SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__Status__c, compliancequest__Triage_Result__c,
                       compliancequest__Defect_Severity__c, compliancequest__Severity__c, compliancequest__Reoccurring__c,
                       compliancequest__Lot_Number__c, compliancequest__Lot_Quantity__c, compliancequest__Defective_Quantity__c, compliancequest__Occurrence_Date__c,
                       compliancequest__Has_Containment__c, compliancequest__SQX_Investigation__c, compliancequest__SQX_Investigation__r.Name,
                       compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.Name, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                       Field_Action_Review__c, Field_Action_Review_Reason__c, Field_Action_Review_By__r.Name, Field_Action_Review_On__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
    }
}

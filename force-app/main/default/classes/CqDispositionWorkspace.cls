/**
 * CqDispositionWorkspace: the CQ.AI Disposition workspace on a Nonconformance in Disposition / Investigate.
 *
 * getView() gives what the two steps show: the NC, each impacted part and lot with its quantities and disposition
 * records, CQ.AI's suggested disposition type (and why), what was decided at triage, and past dispositions on the part.
 *
 * completeDispositions() records what was done with each lot and completes it in CQ in one save. The lot's draft
 * disposition (made at Complete Triage) is reused for the first row; further rows (a split quantity) are new records.
 * CQ then updates the lot's disposed quantity and marks the NC's disposition complete when nothing is left.
 * If a lot still has quantity left afterwards, a new draft is made for the rest.
 *
 * Disposition approval is not handled here yet: an NC that needs it is shown as such and left to CQ.
 */
public with sharing class CqDispositionWorkspace {
    public static final String COMPLETE = 'complete';
    public static final String USE_AS_IS = 'Use As Is';
    public static final List<String> DISPOSITION_TYPES = new List<String>{ 'Scrap', 'Rework', 'Return To Vendor (RTV)', USE_AS_IS };
    public static final Integer HISTORY = 10;

    public class Rec {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String type;
        @AuraEnabled public Decimal qty; @AuraEnabled public String status; @AuraEnabled public Date completedOn;
    }
    public class Lot {
        @AuraEnabled public Id impactedId; @AuraEnabled public Id partId; @AuraEnabled public String partName; @AuraEnabled public String lot;
        @AuraEnabled public Decimal impacted; @AuraEnabled public Decimal disposed; @AuraEnabled public Decimal left;
        @AuraEnabled public Id draftId; @AuraEnabled public String draftName;
        @AuraEnabled public List<Rec> records = new List<Rec>();
    }
    public class Past {
        @AuraEnabled public Id ncId; @AuraEnabled public String ncName; @AuraEnabled public String type;
        @AuraEnabled public Decimal qty; @AuraEnabled public String lot;
    }
    public class View {
        @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String description;
        @AuraEnabled public Id partId; @AuraEnabled public String partNumber; @AuraEnabled public String partName; @AuraEnabled public String lot;
        @AuraEnabled public String stage; @AuraEnabled public String status; @AuraEnabled public String owner; @AuraEnabled public String risk;
        @AuraEnabled public String path; @AuraEnabled public Id investigationId; @AuraEnabled public String investigationName;
        @AuraEnabled public Date dispDue; @AuraEnabled public Boolean needsApproval = false; @AuraEnabled public Boolean isComplete = false;
        @AuraEnabled public List<String> types = DISPOSITION_TYPES;
        @AuraEnabled public String suggestType; @AuraEnabled public String suggestWhy;
        @AuraEnabled public List<Lot> lots = new List<Lot>();
        @AuraEnabled public List<Past> history = new List<Past>();
    }
    public class Row {
        public Id impactedId; public Id draftId; public String type; public Decimal qty;
        public String completedOn; public String comment; public String justification;
    }
    public class Result {
        @AuraEnabled public List<Rec> done = new List<Rec>();
        @AuraEnabled public List<String> remainders = new List<String>();
        @AuraEnabled public Boolean ncComplete = false;
    }

    @AuraEnabled
    public static View getView(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT Name, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Part__r.Name, compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__Lot_Number__c,
                   toLabel(compliancequest__Record_Stage__c), compliancequest__Status__c, Owner.Name, Triage_Risk__c, Triage_Path__c,
                   compliancequest__SQX_Investigation__c, compliancequest__SQX_Investigation__r.Name,
                   compliancequest__Due_Date_Disposition__c, compliancequest__Disposition_Approval__c, compliancequest__Is_Disposition_Complete__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
        View v = new View();
        v.name = nc.Name; v.title = nc.compliancequest__NC_Title__c; v.description = nc.compliancequest__Description__c;
        v.partId = nc.compliancequest__SQX_Part__c; v.lot = nc.compliancequest__Lot_Number__c;
        if (nc.compliancequest__SQX_Part__r != null) {
            v.partNumber = nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c; v.partName = nc.compliancequest__SQX_Part__r.Name;
        }
        v.stage = nc.compliancequest__Record_Stage__c; v.status = nc.compliancequest__Status__c; v.owner = nc.Owner.Name;
        v.risk = nc.Triage_Risk__c; v.path = nc.Triage_Path__c;
        v.investigationId = nc.compliancequest__SQX_Investigation__c;
        v.investigationName = nc.compliancequest__SQX_Investigation__r == null ? null : nc.compliancequest__SQX_Investigation__r.Name;
        v.dispDue = nc.compliancequest__Due_Date_Disposition__c;
        v.needsApproval = nc.compliancequest__Disposition_Approval__c == true;

        Map<Id, Lot> byImpacted = new Map<Id, Lot>();
        for (compliancequest__SQX_NC_Impacted_Product__c ip : [
                SELECT Id, compliancequest__SQX_Impacted_Part__c, compliancequest__SQX_Impacted_Part__r.Name, compliancequest__Lot_Number__c,
                       compliancequest__Lot_Quantity__c, compliancequest__Total_Quantity_Disposed__c, compliancequest__Quantity_Left_To_Dispose__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE ORDER BY Name]) {
            Lot l = new Lot();
            l.impactedId = ip.Id; l.partId = ip.compliancequest__SQX_Impacted_Part__c; l.lot = ip.compliancequest__Lot_Number__c;
            l.partName = ip.compliancequest__SQX_Impacted_Part__r == null ? null : ip.compliancequest__SQX_Impacted_Part__r.Name;
            l.impacted = nz(ip.compliancequest__Lot_Quantity__c); l.disposed = nz(ip.compliancequest__Total_Quantity_Disposed__c);
            l.left = nz(ip.compliancequest__Quantity_Left_To_Dispose__c);
            byImpacted.put(ip.Id, l);
            v.lots.add(l);
        }
        for (compliancequest__SQX_Disposition__c d : [
                SELECT Id, Name, compliancequest__SQX_NC_Impacted_Product__c, compliancequest__Disposition_Type__c,
                       compliancequest__Disposition_Quantity__c, compliancequest__Actual_Quantity_Disposed__c, compliancequest__Status__c,
                       compliancequest__Completed_On__c
                FROM compliancequest__SQX_Disposition__c WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE ORDER BY CreatedDate]) {
            Lot l = byImpacted.get(d.compliancequest__SQX_NC_Impacted_Product__c);
            if (l == null) { continue; }
            l.records.add(rec(d));
            if (l.draftId == null && d.compliancequest__Status__c == 'Draft') { l.draftId = d.Id; l.draftName = d.Name; }
        }
        Decimal left = 0;
        for (Lot l : v.lots) { left += l.left; }
        v.isComplete = !v.lots.isEmpty() && left == 0;

        // past dispositions on this part, newest first, from other NCs
        if (v.partId != null) {
            for (compliancequest__SQX_Disposition__c d : [
                    SELECT compliancequest__SQX_Nonconformance__c, compliancequest__SQX_Nonconformance__r.Name, compliancequest__Disposition_Type__c,
                           compliancequest__Actual_Quantity_Disposed__c, compliancequest__Disposition_Quantity__c, compliancequest__Lot_Number__c
                    FROM compliancequest__SQX_Disposition__c
                    WHERE compliancequest__SQX_Part__c = :v.partId AND compliancequest__SQX_Nonconformance__c != :recordId
                      AND compliancequest__Status__c = 'Complete' AND compliancequest__Disposition_Type__c != null
                    WITH USER_MODE ORDER BY compliancequest__Completed_On__c DESC NULLS LAST, CreatedDate DESC LIMIT :HISTORY]) {
                Past p = new Past();
                p.ncId = d.compliancequest__SQX_Nonconformance__c; p.ncName = d.compliancequest__SQX_Nonconformance__r.Name;
                p.type = d.compliancequest__Disposition_Type__c; p.lot = d.compliancequest__Lot_Number__c;
                p.qty = d.compliancequest__Actual_Quantity_Disposed__c != null ? d.compliancequest__Actual_Quantity_Disposed__c : d.compliancequest__Disposition_Quantity__c;
                v.history.add(p);
            }
        }
        suggest(v);
        if (v.lots.isEmpty()) {
            v.suggestType = null;
            v.suggestWhy = 'This NC has no impacted parts or lots, so there is nothing to dispose.';
        }
        return v;
    }

    /** CQ.AI's suggested type: Scrap when the risk is High; otherwise what this part's past dispositions were mostly; Scrap when there are none. */
    @TestVisible
    static void suggest(View v) {
        Map<String, Integer> counts = new Map<String, Integer>();
        String top; Integer topN = 0;
        for (Past p : v.history) {
            Integer n = (counts.containsKey(p.type) ? counts.get(p.type) : 0) + 1;
            counts.put(p.type, n);
            if (n > topN) { top = p.type; topN = n; }
        }
        String seen = v.history.isEmpty() ? null
            : v.history.size() == 1 ? 'The last disposition on this part was ' + top + '.'
            : topN + ' of the last ' + v.history.size() + ' dispositions on this part ' + (topN == 1 ? 'was ' : 'were ') + top + '.';
        if (v.risk == 'High') {
            v.suggestType = 'Scrap';
            v.suggestWhy = 'Risk is High, so releasing these units would need an engineering justification, and rework would need to bring them back to spec.'
                + (seen == null ? '' : ' ' + seen);
        } else if (top != null) {
            v.suggestType = top;
            v.suggestWhy = seen + (v.risk == null ? '' : ' Risk is ' + v.risk + '.');
        } else {
            v.suggestType = 'Scrap';
            v.suggestWhy = 'There are no past dispositions on this part to go by, so Scrap is the safe choice unless engineering says the units can be used or reworked.';
        }
    }

    @AuraEnabled
    public static Result completeDispositions(Id recordId, String payload) {
        List<Row> rows = (List<Row>) JSON.deserialize(payload, List<Row>.class);
        if (rows == null || rows.isEmpty()) { throw new AuraHandledException('Add at least one disposition.'); }
        View v = getView(recordId);
        if (v.needsApproval) { throw new AuraHandledException('This NC needs disposition approval, which the workspace does not do yet. Use the Disposition tab.'); }
        Map<Id, Lot> lots = new Map<Id, Lot>();
        for (Lot l : v.lots) { lots.put(l.impactedId, l); }

        // check every row before saving anything
        Map<Id, Decimal> total = new Map<Id, Decimal>();
        Set<String> types = new Set<String>(DISPOSITION_TYPES);
        for (Row r : rows) {
            Lot l = lots.get(r.impactedId);
            if (l == null) { throw new AuraHandledException('A lot on this disposition is not on this NC.'); }
            if (String.isBlank(r.type) || !types.contains(r.type)) { throw new AuraHandledException('Choose a type for lot ' + l.lot + '.'); }
            if (r.qty == null || r.qty <= 0) { throw new AuraHandledException('Enter a quantity for lot ' + l.lot + '.'); }
            if (r.type == USE_AS_IS && String.isBlank(r.justification)) { throw new AuraHandledException('Use As Is on lot ' + l.lot + ' needs a justification.'); }
            total.put(r.impactedId, (total.containsKey(r.impactedId) ? total.get(r.impactedId) : 0) + r.qty);
        }
        for (Id k : total.keySet()) {
            Lot l = lots.get(k);
            if (total.get(k) > l.left) { throw new AuraHandledException('Lot ' + l.lot + ' has ' + num(l.left) + ' left to dispose, not ' + num(total.get(k)) + '.'); }
        }

        List<Id> doneIds = new List<Id>();
        Savepoint sp = Database.setSavepoint();
        try {
            // the lot's draft goes with its first row; any other row is a new record, saved as a draft and then completed like the rest
            Set<Id> used = new Set<Id>();
            List<compliancequest__SQX_Disposition__c> fresh = new List<compliancequest__SQX_Disposition__c>();
            List<compliancequest__SQX_Disposition__c> all = new List<compliancequest__SQX_Disposition__c>();
            for (Row r : rows) {
                Lot l = lots.get(r.impactedId);
                Id draft = l.draftId != null && !used.contains(l.draftId) ? l.draftId : null;
                if (draft != null) {
                    used.add(draft);
                    all.add(new compliancequest__SQX_Disposition__c(Id = draft));
                } else {
                    compliancequest__SQX_Disposition__c d = new compliancequest__SQX_Disposition__c(
                        Name = ('Disposition for Lot ' + l.lot).left(80), compliancequest__SQX_Nonconformance__c = recordId,
                        compliancequest__SQX_NC_Impacted_Product__c = l.impactedId, compliancequest__SQX_Part__c = l.partId,
                        compliancequest__Lot_Number__c = l.lot, compliancequest__Disposition_Quantity__c = r.qty,
                        compliancequest__Status__c = 'Draft', compliancequest__Due_Date__c = v.dispDue, compliancequest__SQX_User__c = UserInfo.getUserId());
                    fresh.add(d); all.add(d);
                }
            }
            if (!fresh.isEmpty()) { insert as user fresh; }
            for (Integer i = 0; i < rows.size(); i++) {
                Row r = rows[i];
                compliancequest__SQX_Disposition__c d = new compliancequest__SQX_Disposition__c(Id = all[i].Id);
                d.compliancequest__Disposition_Type__c = r.type;
                d.compliancequest__Disposition_Quantity__c = r.qty;
                d.compliancequest__Actual_Quantity_Disposed__c = r.qty;
                d.compliancequest__Comment__c = String.isBlank(r.comment) ? null : r.comment;
                d.compliancequest__Disposition_Justification__c = String.isBlank(r.justification) ? null : r.justification;
                d.compliancequest__Completed_On__c = toDate(r.completedOn);
                d.compliancequest__Completed_By__c = UserInfo.getName().left(80);
                d.compliancequest__Activity_Code__c = COMPLETE;
                all[i] = d;
            }
            update as user all;
            for (compliancequest__SQX_Disposition__c d : all) { doneIds.add(d.Id); }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('CQ did not complete the disposition: ' + e.getDmlMessage(0));
        }

        Result res = new Result();
        for (compliancequest__SQX_Disposition__c d : [
                SELECT Id, Name, compliancequest__Disposition_Type__c, compliancequest__Disposition_Quantity__c, compliancequest__Actual_Quantity_Disposed__c,
                       compliancequest__Status__c, compliancequest__Completed_On__c
                FROM compliancequest__SQX_Disposition__c WHERE Id IN :doneIds WITH USER_MODE ORDER BY Name]) {
            res.done.add(rec(d));
        }
        // whatever is still left on a lot gets a new draft, so the next person picks it up
        try {
            res.remainders = CqTriageNext.createDraftDispositions(recordId, v.dispDue == null ? Date.today().addDays(CqTriageNext.DISPOSITION_DAYS) : v.dispDue);
        } catch (DmlException e) { /* the dispositions are complete; a missing draft for the rest is not worth failing over */ }
        res.ncComplete = [SELECT compliancequest__Is_Disposition_Complete__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE].compliancequest__Is_Disposition_Complete__c == true;
        return res;
    }

    static Rec rec(compliancequest__SQX_Disposition__c d) {
        Rec r = new Rec();
        r.id = d.Id; r.name = d.Name; r.type = d.compliancequest__Disposition_Type__c; r.status = d.compliancequest__Status__c;
        r.qty = r.status == 'Complete' && d.compliancequest__Actual_Quantity_Disposed__c != null ? d.compliancequest__Actual_Quantity_Disposed__c : d.compliancequest__Disposition_Quantity__c;
        r.completedOn = d.compliancequest__Completed_On__c;
        return r;
    }
    static Decimal nz(Decimal v) { return v == null ? 0 : v; }
    static String num(Decimal v) { return v.stripTrailingZeros().toPlainString(); }
    static Date toDate(String v) {
        try { return String.isBlank(v) ? Date.today() : Date.valueOf(v); } catch (Exception e) { return Date.today(); }
    }
}

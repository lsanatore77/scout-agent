/**
 * CqLotStatus: a lot's Release Status is worked out from everything that controls it, and the strictest wins.
 *
 * What controls a lot (each keeps its own decision; the lot only shows the result):
 *   - a person: Manual Status, what was last set by hand on the lot (Released, Pending QA, Quarantined, Rejected...)
 *   - field action holds (Field_Action_Hold__c, held): open or Rework -> On Hold; confirmed Scrap or Return to Supplier
 *     -> Rejected; confirmed Release -> lets go
 *   - CQ nonconformances (Impacted Part / Lot), matched on part and lot together: quantity left to dispose -> Quarantined
 *     when it covers the whole lot (all its stock, or always when Field Action Settings > NC Quarantines Whole Lot is on);
 *     a smaller quantity is shown on the lot's Quality list, not as a status
 *   - receiving inspection on the lot: Rejected -> Rejected; Pending -> Quarantined
 * Strictness: Rejected > Recalled > On Hold > Quarantined > Pending QA > Released. The lot is free only when every
 * control has let go. Hold Reason names every active control; Status Set By names the one that set the status.
 * When final decisions disagree (one releases the lot, another scraps it), the stricter applies and Status Conflict
 * says so, for a person to settle.
 *
 * Editing Release Status by hand sets Manual Status (the person's own decision); the controls can make the lot stricter
 * than that, never looser. The core works with no configuration.
 */
public without sharing class CqLotStatus {

    public static Boolean syncing = false;

    static final Map<String, Integer> RANK = new Map<String, Integer>{
        'Released' => 1, 'Pending QA' => 2, 'Quarantined' => 3, 'On Hold' => 4, 'Recalled' => 5, 'Rejected' => 6 };

    /** One control's say on a lot. */
    public class Say {
        public String status;      // null: lets go
        public String who;         // e.g. FA-0001, NC-000077, Receiving inspection, Manual
        public String why;         // for Hold Reason
        public Boolean finalRelease = false;
        public Boolean finalReject = false;
        Say(String status, String who, String why) { this.status = status; this.who = who; this.why = why; }
    }

    // ------------------------------------------------------------------ entry points

    /** Lot Info before insert / update: a status set by hand becomes Manual Status, then the lot is worked out. */
    public static void beforeSave(List<compliancequest__SQX_Lot_Info__c> lots, Map<Id, compliancequest__SQX_Lot_Info__c> before) {
        if (syncing) { return; }
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            compliancequest__SQX_Lot_Info__c b = before == null ? null : before.get(l.Id);
            if (b == null) {
                l.Manual_Status__c = l.Release_Status__c == null ? 'Released' : l.Release_Status__c;
            } else if (l.Release_Status__c != b.Release_Status__c) {
                l.Manual_Status__c = l.Release_Status__c == null ? 'Released' : l.Release_Status__c;
            }
        }
        apply(lots, before);
    }

    /** From the source triggers (holds, NC impacted lots): the lot numbers whose controls changed. */
    public static void sourceChanged(Set<String> lotNumbers) {
        lotNumbers.remove(null);
        if (lotNumbers.isEmpty()) { return; }
        List<compliancequest__SQX_Lot_Info__c> lots = [SELECT Id, Name, compliancequest__Part_Number__c, Part__r.compliancequest__Part_Number__c,
                Release_Status__c, Manual_Status__c, Hold_Reason__c, Receiving_Inspection__c, Status_Set_By__c, Status_Set_On__c,
                Status_Conflict__c, Batch__r.cqext__Quantity__c FROM compliancequest__SQX_Lot_Info__c WHERE Name IN :lotNumbers];
        Map<Id, compliancequest__SQX_Lot_Info__c> was = new Map<Id, compliancequest__SQX_Lot_Info__c>();
        for (compliancequest__SQX_Lot_Info__c l : lots) { was.put(l.Id, l.clone(true, true, false, false)); }
        apply(lots, was);
        List<compliancequest__SQX_Lot_Info__c> ups = new List<compliancequest__SQX_Lot_Info__c>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            compliancequest__SQX_Lot_Info__c w = was.get(l.Id);
            if (l.Release_Status__c != w.Release_Status__c || l.Hold_Reason__c != w.Hold_Reason__c
                    || l.Status_Set_By__c != w.Status_Set_By__c || l.Status_Conflict__c != w.Status_Conflict__c) {
                ups.add(new compliancequest__SQX_Lot_Info__c(Id = l.Id, Release_Status__c = l.Release_Status__c, Hold_Reason__c = l.Hold_Reason__c,
                    Status_Set_By__c = l.Status_Set_By__c, Status_Set_On__c = l.Status_Set_On__c, Status_Conflict__c = l.Status_Conflict__c));
            }
        }
        if (ups.isEmpty()) { return; }
        syncing = true;
        try { update ups; } finally { syncing = false; }
    }

    public static void holdsChanged(List<Field_Action_Hold__c> rows, Map<Id, Field_Action_Hold__c> before) {
        Set<String> lots = new Set<String>();
        if (rows != null) { for (Field_Action_Hold__c h : rows) { lots.add(h.Lot_Number__c); } }
        if (before != null) { for (Field_Action_Hold__c h : before.values()) { lots.add(h.Lot_Number__c); } }
        sourceChanged(lots);
    }

    /** An NC save belongs to CQ: a problem working out the lot's status is logged and never blocks it. */
    public static void impactedChanged(List<compliancequest__SQX_NC_Impacted_Product__c> rows, Map<Id, compliancequest__SQX_NC_Impacted_Product__c> before) {
        try {
            impactedLots(rows, before);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CqLotStatus: lot status not updated from an NC: ' + e.getMessage());
        }
    }
    static void impactedLots(List<compliancequest__SQX_NC_Impacted_Product__c> rows, Map<Id, compliancequest__SQX_NC_Impacted_Product__c> before) {
        Set<String> lots = new Set<String>();
        if (rows != null) { for (compliancequest__SQX_NC_Impacted_Product__c r : rows) { lots.add(r.compliancequest__Lot_Number__c); } }
        if (before != null) { for (compliancequest__SQX_NC_Impacted_Product__c r : before.values()) { lots.add(r.compliancequest__Lot_Number__c); } }
        sourceChanged(lots);
    }

    // ------------------------------------------------------------------ working it out

    /** Sets Release Status, Hold Reason, Status Set By / On and Status Conflict on these lots (not saved). */
    static void apply(List<compliancequest__SQX_Lot_Info__c> lots, Map<Id, compliancequest__SQX_Lot_Info__c> before) {
        Set<String> names = new Set<String>();
        for (compliancequest__SQX_Lot_Info__c l : lots) { if (l.Name != null) { names.add(l.Name); } }
        Map<String, List<Say>> says = gather(lots, names);
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            List<Say> all = new List<Say>();
            String manual = l.Manual_Status__c == null ? 'Released' : l.Manual_Status__c;
            if (rank(manual) > 1) { all.add(new Say(manual, 'Manual', 'Set by hand: ' + manual)); }
            if (l.Receiving_Inspection__c == 'Rejected') {
                Say s = new Say('Rejected', 'Receiving inspection', 'Rejected at receiving inspection');
                s.finalReject = true;
                all.add(s);
            } else if (l.Receiving_Inspection__c == 'Pending') {
                all.add(new Say('Quarantined', 'Receiving inspection', 'Receiving inspection pending'));
            }
            if (says.containsKey(l.Name)) { all.addAll(says.get(l.Name)); }

            Say top = null;
            List<String> reasons = new List<String>();
            Boolean rel = false, rej = false;
            List<String> relWho = new List<String>(), rejWho = new List<String>();
            for (Say s : all) {
                if (s.finalRelease) { rel = true; relWho.add(s.who); }
                if (s.finalReject) { rej = true; rejWho.add(s.who); }
                if (s.status == null) { continue; }
                if (s.why != null && !reasons.contains(s.why)) { reasons.add(s.why); }
                if (top == null || rank(s.status) > rank(top.status)) { top = s; }
            }
            String status = top == null ? (manual == null ? 'Released' : manual) : top.status;
            if (rank(manual) >= rank(status)) { status = manual; }
            compliancequest__SQX_Lot_Info__c b = before == null ? null : before.get(l.Id);
            Boolean changed = b == null || b.Release_Status__c != status;
            l.Release_Status__c = status;
            l.Hold_Reason__c = reasons.isEmpty() ? null : String.join(reasons, '; ').left(255);
            String setBy = top == null || rank(manual) >= rank(top.status) ? (rank(manual) > 1 ? 'Manual' : null) : top.who;
            if (changed || l.Status_Set_By__c != setBy) { l.Status_Set_On__c = Datetime.now(); }
            l.Status_Set_By__c = setBy;
            l.Status_Conflict__c = rel && rej
                ? (String.join(relWho, ', ') + ' released this lot but ' + String.join(rejWho, ', ') + ' rejected it. Confirm which stands.').left(255)
                : null;
        }
    }

    /** Every field action hold and NC impacted lot on these lot numbers, as says per lot (matched on part and lot). */
    static Map<String, List<Say>> gather(List<compliancequest__SQX_Lot_Info__c> lots, Set<String> names) {
        Map<String, List<Say>> out = new Map<String, List<Say>>();
        if (names.isEmpty()) { return out; }
        Map<String, String> partOf = new Map<String, String>();
        Map<String, Decimal> sizeOf = new Map<String, Decimal>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            String pn = l.Part__r?.compliancequest__Part_Number__c;
            partOf.put(l.Name, pn != null ? pn : l.compliancequest__Part_Number__c);
            if (l.Batch__r?.cqext__Quantity__c != null) { sizeOf.put(l.Name, l.Batch__r.cqext__Quantity__c); }
        }
        // what is left of the lot: on hand from Lot Stock when there is a record, else what the batch built
        for (AggregateResult r : [SELECT Lot_Number__c lot, SUM(Units_On_Hand__c) units FROM Lot_Stock__c WHERE Lot_Number__c IN :names GROUP BY Lot_Number__c]) {
            sizeOf.put((String) r.get('lot'), (Decimal) r.get('units'));
        }
        Field_Action_Settings__c fs = Field_Action_Settings__c.getOrgDefaults();
        Boolean wholeLot = fs != null && fs.NC_Quarantines_Whole_Lot__c == true;

        for (Field_Action_Hold__c h : [SELECT Lot_Number__c, Part_Number__c, Field_Action__r.Name, Held_On__c, Disposition__c, Disposition_On__c
                                       FROM Field_Action_Hold__c WHERE Lot_Number__c IN :names AND Held__c = true ORDER BY Held_On__c]) {
            String pn = partOf.get(h.Lot_Number__c);
            if (h.Part_Number__c != null && pn != null && h.Part_Number__c != pn) { continue; }
            String fa = h.Field_Action__r?.Name == null ? 'Field action' : h.Field_Action__r.Name;
            Say s;
            if (h.Disposition_On__c == null) {
                s = new Say('On Hold', fa, fa + ' hold' + (h.Held_On__c == null ? '' : ', ' + h.Held_On__c.format('d MMM yyyy')));
            } else if (h.Disposition__c == 'Rework') {
                s = new Say('On Hold', fa, fa + ': rework');
            } else if (h.Disposition__c == 'Scrap' || h.Disposition__c == 'Return to Supplier') {
                s = new Say('Rejected', fa, fa + ': ' + h.Disposition__c);
                s.finalReject = true;
            } else {
                s = new Say(null, fa, null);
                s.finalRelease = true;
            }
            add(out, h.Lot_Number__c, s);
        }

        for (compliancequest__SQX_NC_Impacted_Product__c ip : [
                SELECT compliancequest__Lot_Number__c, compliancequest__Part_Number__c, compliancequest__Lot_Quantity__c,
                       compliancequest__Quantity_Left_To_Dispose__c, compliancequest__SQX_Nonconformance__r.Name,
                       compliancequest__SQX_Nonconformance__r.compliancequest__Status__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__Lot_Number__c IN :names]) {
            String lot = ip.compliancequest__Lot_Number__c;
            String pn = partOf.get(lot);
            if (pn != null && ip.compliancequest__Part_Number__c != null && ip.compliancequest__Part_Number__c != pn) { continue; }
            String ncStatus = ip.compliancequest__SQX_Nonconformance__r?.compliancequest__Status__c;
            if (ncStatus == 'Void' || ncStatus == 'Closed') { continue; }
            Decimal left = ip.compliancequest__Quantity_Left_To_Dispose__c == null ? 0 : ip.compliancequest__Quantity_Left_To_Dispose__c;
            if (left <= 0) { continue; }
            Decimal size = sizeOf.get(lot);
            Boolean whole = wholeLot || size == null || left >= size;
            if (!whole) { continue; }   // a part of the lot: on the Quality list, not a status
            String nc = ip.compliancequest__SQX_Nonconformance__r?.Name == null ? 'NC' : ip.compliancequest__SQX_Nonconformance__r.Name;
            add(out, lot, new Say('Quarantined', nc, nc + ': ' + qty(left) + (size == null ? ' units' : ' of ' + qty(size) + ' units')));
        }
        return out;
    }

    static void add(Map<String, List<Say>> m, String lot, Say s) {
        if (!m.containsKey(lot)) { m.put(lot, new List<Say>()); }
        m.get(lot).add(s);
    }
    static Integer rank(String s) { return s == null || !RANK.containsKey(s) ? 1 : RANK.get(s); }
    static String qty(Decimal d) { return d == null ? '' : d.stripTrailingZeros().toPlainString(); }
}

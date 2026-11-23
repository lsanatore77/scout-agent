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
 *   - CQ NC dispositions, once Complete: Scrap or Return To Vendor of the whole lot -> Rejected; a part of the lot, Rework
 *     or Use As Is is shown on the lot's Quality list, not as a status
 *   - the lot's batch record (CQ EBR, Lot Info.Batch__c): Released -> the lot may be released; Void -> Rejected; any other
 *     status -> Pending QA. A lot with no batch record is not held by this (purchased lots follow receiving inspection)
 *   - receiving inspection on the lot: Rejected -> Rejected; Pending -> Quarantined
 *   - recall field actions (Action Type Removal (Recall)) through their scope (Field_Action_Lot__c): a lot in the scope
 *     -> Recall Pending; in the approved scope (Confirmed In Scope) -> Recalled. Once that field action confirms its own
 *     decision on the lot in Recovery (Release, Rework, Scrap...), that decision replaces the recall.
 * Strictness: Rejected > Recalled > Recall Pending > On Hold > Quarantined > Pending QA > Released. The lot is free only when every
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
        'Released' => 1, 'Pending QA' => 2, 'Quarantined' => 3, 'On Hold' => 4, 'Recall Pending' => 5, 'Recalled' => 6, 'Rejected' => 7 };
    static final String RECALL = 'Removal (Recall)';

    /** One control's say on a lot. */
    public class Say {
        public String status;      // null: lets go
        public String who;         // e.g. FA-0001, NC-000077, Receiving inspection, Manual
        public String why;         // for Hold Reason
        public String detail;      // for the lot's Quality list: the step, who and when, e.g. 'Scope approved by J. Rivera · 23 Nov 2026'
        public Boolean finalRelease = false;
        public Boolean finalReject = false;
        public Boolean basis = false;    // the release the lot rests on (its batch record): names Status Set By when nothing holds it
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
                Status_Conflict__c, Batch__c, Batch__r.Name, Batch__r.cqext__Status__c, Batch__r.cqext__Released_Date__c,
                Batch__r.cqext__Quantity__c FROM compliancequest__SQX_Lot_Info__c WHERE Name IN :lotNumbers];
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

    /** A lot added to, removed from or confirmed in a field action's scope. */
    public static void scopeChanged(List<Field_Action_Lot__c> rows, Map<Id, Field_Action_Lot__c> before) {
        Set<String> lots = new Set<String>();
        if (rows != null) { for (Field_Action_Lot__c r : rows) { lots.add(r.Lot_Number__c); } }
        if (before != null) { for (Field_Action_Lot__c r : before.values()) { lots.add(r.Lot_Number__c); } }
        sourceChanged(lots);
    }

    /** A field action that becomes, or stops being, a recall: every lot in its scope. */
    public static void actionTypeChanged(List<Field_Action__c> rows, Map<Id, Field_Action__c> before) {
        Set<Id> ids = new Set<Id>();
        for (Field_Action__c f : rows) {
            Field_Action__c b = before == null ? null : before.get(f.Id);
            if (b != null) {
                if (b.Action_Type__c != f.Action_Type__c) { ids.add(f.Id); }
            }
        }
        if (ids.isEmpty()) { return; }
        Set<String> lots = new Set<String>();
        for (Field_Action_Lot__c r : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c IN :ids]) { lots.add(r.Lot_Number__c); }
        sourceChanged(lots);
    }

    /** A batch record released, voided or reopened: the lots made from it. A batch save belongs to CQ and is never blocked. */
    public static void batchChanged(List<cqext__CQEBR_Batch__c> rows, Map<Id, cqext__CQEBR_Batch__c> before) {
        try {
            Set<Id> ids = new Set<Id>();
            for (cqext__CQEBR_Batch__c b : rows) {
                cqext__CQEBR_Batch__c was = before == null ? null : before.get(b.Id);
                if (was == null) { ids.add(b.Id); continue; }
                if (was.cqext__Status__c != b.cqext__Status__c) { ids.add(b.Id); }
            }
            if (ids.isEmpty()) { return; }
            Set<String> lots = new Set<String>();
            for (compliancequest__SQX_Lot_Info__c l : [SELECT Name FROM compliancequest__SQX_Lot_Info__c WHERE Batch__c IN :ids]) { lots.add(l.Name); }
            sourceChanged(lots);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CqLotStatus: lot status not updated from a batch record: ' + e.getMessage());
        }
    }

    /** An NC disposition saved or completed: its lot. An NC save belongs to CQ and is never blocked. */
    public static void dispositionChanged(List<compliancequest__SQX_Disposition__c> rows, Map<Id, compliancequest__SQX_Disposition__c> before) {
        try {
            Set<Id> ids = new Set<Id>();
            if (rows != null) { for (compliancequest__SQX_Disposition__c d : rows) { if (d.Id != null) { ids.add(d.Id); } } }
            if (before != null) { ids.addAll(before.keySet()); }
            Set<String> lots = new Set<String>();
            if (rows != null) { for (compliancequest__SQX_Disposition__c d : rows) { lots.add(d.compliancequest__Lot_Number__c); } }
            if (before != null) { for (compliancequest__SQX_Disposition__c d : before.values()) { lots.add(d.compliancequest__Lot_Number__c); } }
            for (compliancequest__SQX_Disposition__c d : [SELECT compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Lot_Number__c
                                                           FROM compliancequest__SQX_Disposition__c WHERE Id IN :ids ALL ROWS]) {
                lots.add(d.compliancequest__SQX_NC_Impacted_Product__r?.compliancequest__Lot_Number__c);
            }
            sourceChanged(lots);
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'CqLotStatus: lot status not updated from a disposition: ' + e.getMessage());
        }
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

    /** Every control's say on one lot, for the lot record's Quality list (the lot needs Name, part and batch quantity). */
    public static List<Say> explain(compliancequest__SQX_Lot_Info__c lot) {
        Map<String, List<Say>> m = gather(new List<compliancequest__SQX_Lot_Info__c>{ lot }, new Set<String>{ lot.Name });
        return m.containsKey(lot.Name) ? m.get(lot.Name) : new List<Say>();
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

            Say top = null, basis = null;
            List<String> reasons = new List<String>();
            Boolean rel = false, rej = false;
            List<String> relWho = new List<String>(), rejWho = new List<String>();
            for (Say s : all) {
                if (s.finalRelease) { rel = true; relWho.add(s.who); }
                if (s.finalReject) { rej = true; rejWho.add(s.who); }
                if (s.basis) { basis = s; }
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
            String setBy = top == null || rank(manual) >= rank(top.status) ? (rank(manual) > 1 ? 'Manual' : basis?.who) : top.who;
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

        Set<String> decided = new Set<String>();   // field action + lot whose own decision is confirmed
        for (Field_Action_Hold__c h : [SELECT Lot_Number__c, Part_Number__c, Field_Action__c, Field_Action__r.Name, Held_On__c, Disposition__c, Disposition_On__c,
                                              Field_Action__r.Strategy_Confirmed_By__r.Name, Field_Action__r.Verdict_By__r.Name
                                       FROM Field_Action_Hold__c WHERE Lot_Number__c IN :names AND Held__c = true ORDER BY Held_On__c]) {
            String pn = partOf.get(h.Lot_Number__c);
            if (h.Part_Number__c != null && pn != null && h.Part_Number__c != pn) { continue; }
            String fa = h.Field_Action__r?.Name == null ? 'Field action' : h.Field_Action__r.Name;
            if (h.Disposition_On__c != null) { decided.add(String.valueOf(h.Field_Action__c) + '|' + h.Lot_Number__c); }
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
            s.detail = h.Disposition_On__c == null
                ? 'Held at Confirm Strategy' + byWhom(h.Field_Action__r?.Strategy_Confirmed_By__r?.Name) + dated(h.Held_On__c)
                : h.Disposition__c + ' confirmed' + byWhom(h.Field_Action__r?.Verdict_By__r?.Name) + dated(h.Disposition_On__c)
                    + (h.Disposition__c == 'Rework' ? ' \u00b7 held until rework is done' : '');
            add(out, h.Lot_Number__c, s);
        }

        // recall field actions: in the scope -> Recall Pending; in the approved scope -> Recalled
        for (Field_Action_Lot__c r : [SELECT Lot_Number__c, Field_Action__c, Field_Action__r.Name, Field_Action__r.Part__r.compliancequest__Part_Number__c,
                                             In_Scope__c, Approved_In_Scope__c, Field_Action__r.Scope_Confirmed_On__c, Field_Action__r.Scope_Confirmed_By__r.Name
                                      FROM Field_Action_Lot__c
                                      WHERE Lot_Number__c IN :names AND Field_Action__r.Action_Type__c = :RECALL
                                        AND (In_Scope__c = true OR Approved_In_Scope__c = true)]) {
            if (decided.contains(String.valueOf(r.Field_Action__c) + '|' + r.Lot_Number__c)) { continue; }   // its own decision replaces the recall
            String pn = partOf.get(r.Lot_Number__c);
            String fpn = r.Field_Action__r?.Part__r?.compliancequest__Part_Number__c;
            if (fpn != null && pn != null && fpn != pn) { continue; }
            String fa = r.Field_Action__r?.Name == null ? 'Field action' : r.Field_Action__r.Name;
            Datetime approvedOn = r.Field_Action__r?.Scope_Confirmed_On__c;
            Say s = r.Approved_In_Scope__c == true
                ? new Say('Recalled', fa, fa + ': recall' + (approvedOn == null ? '' : ', scope approved ' + approvedOn.format('d MMM yyyy')))
                : new Say('Recall Pending', fa, fa + ': recall, scope not yet approved');
            s.detail = r.Approved_In_Scope__c == true
                ? 'Recall \u00b7 scope approved' + byWhom(r.Field_Action__r?.Scope_Confirmed_By__r?.Name) + dated(approvedOn)
                : 'Recall \u00b7 lot in scope, not yet approved';
            add(out, r.Lot_Number__c, s);
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
            String nc = ip.compliancequest__SQX_Nonconformance__r?.Name == null ? 'NC' : ip.compliancequest__SQX_Nonconformance__r.Name;
            String units = qty(left) + (size == null ? ' units' : ' of ' + qty(size) + ' units') + ' left to dispose';
            // a part of the lot: on the Quality list, not a status
            Say s = whole ? new Say('Quarantined', nc, nc + ': ' + qty(left) + (size == null ? ' units' : ' of ' + qty(size) + ' units')) : new Say(null, nc, null);
            s.detail = whole ? units : units + ' \u00b7 not the whole lot';
            add(out, lot, s);
        }

        // NC dispositions, once Complete: scrapping or returning the whole lot rejects it
        Map<String, Decimal> builtOf = new Map<String, Decimal>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            if (l.Batch__r?.cqext__Quantity__c != null) { builtOf.put(l.Name, l.Batch__r.cqext__Quantity__c); }
        }
        Map<String, Decimal> gone = new Map<String, Decimal>();        // NC|lot -> units scrapped or returned
        Map<String, compliancequest__SQX_Disposition__c> lastOf = new Map<String, compliancequest__SQX_Disposition__c>();
        for (compliancequest__SQX_Disposition__c d : [
                SELECT compliancequest__Lot_Number__c, compliancequest__Disposition_Type__c, compliancequest__Actual_Quantity_Disposed__c,
                       compliancequest__Disposition_Quantity__c, compliancequest__Completed_By__c, compliancequest__Completed_On__c,
                       compliancequest__SQX_Nonconformance__r.Name, compliancequest__SQX_Nonconformance__r.compliancequest__Status__c,
                       compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Lot_Number__c,
                       compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Part_Number__c,
                       compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Lot_Quantity__c
                FROM compliancequest__SQX_Disposition__c
                WHERE compliancequest__Status__c = 'Complete'
                  AND (compliancequest__Lot_Number__c IN :names OR compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Lot_Number__c IN :names)
                ORDER BY compliancequest__Completed_On__c]) {
            String lot = d.compliancequest__Lot_Number__c != null && names.contains(d.compliancequest__Lot_Number__c)
                ? d.compliancequest__Lot_Number__c : d.compliancequest__SQX_NC_Impacted_Product__r?.compliancequest__Lot_Number__c;
            if (lot == null || !names.contains(lot)) { continue; }
            String pn = partOf.get(lot);
            String ipn = d.compliancequest__SQX_NC_Impacted_Product__r?.compliancequest__Part_Number__c;
            if (pn != null && ipn != null && ipn != pn) { continue; }
            if (d.compliancequest__SQX_Nonconformance__r?.compliancequest__Status__c == 'Void') { continue; }
            if (!builtOf.containsKey(lot) && d.compliancequest__SQX_NC_Impacted_Product__r?.compliancequest__Lot_Quantity__c != null) {
                builtOf.put(lot, d.compliancequest__SQX_NC_Impacted_Product__r.compliancequest__Lot_Quantity__c);
            }
            String nc = d.compliancequest__SQX_Nonconformance__r?.Name == null ? 'NC' : d.compliancequest__SQX_Nonconformance__r.Name;
            String dtype = d.compliancequest__Disposition_Type__c;
            Decimal units = d.compliancequest__Actual_Quantity_Disposed__c != null && d.compliancequest__Actual_Quantity_Disposed__c > 0
                ? d.compliancequest__Actual_Quantity_Disposed__c : d.compliancequest__Disposition_Quantity__c;
            if (dtype == 'Scrap' || dtype == 'Return To Vendor (RTV)') {
                String k = nc + '|' + lot;
                gone.put(k, (gone.containsKey(k) ? gone.get(k) : 0) + (units == null ? 0 : units));
                lastOf.put(k, d);
            } else {
                Say s = new Say(null, nc, null);
                s.detail = dtype + ' ' + qty(units) + ' units complete' + byWhom(d.compliancequest__Completed_By__c) + datedD(d.compliancequest__Completed_On__c);
                add(out, lot, s);
            }
        }
        for (String k : gone.keySet()) {
            String nc = k.substringBefore('|'), lot = k.substringAfter('|');
            compliancequest__SQX_Disposition__c d = lastOf.get(k);
            Decimal size = builtOf.get(lot);
            Boolean whole = size == null || gone.get(k) >= size;
            String what = d.compliancequest__Disposition_Type__c == 'Scrap' ? 'Scrap' : 'Returned to vendor';
            Say s = whole ? new Say('Rejected', nc, nc + ': ' + what) : new Say(null, nc, null);
            s.finalReject = whole;
            s.detail = what + ' ' + qty(gone.get(k)) + (size == null ? ' units' : ' of ' + qty(size) + ' units') + ' complete'
                + byWhom(d.compliancequest__Completed_By__c) + datedD(d.compliancequest__Completed_On__c);
            add(out, lot, s);
        }

        // the batch record: the lot may be released once its batch is (read by Id: a trigger's lots carry no Batch__r)
        Set<Id> batchIds = new Set<Id>();
        for (compliancequest__SQX_Lot_Info__c l : lots) { if (l.Batch__c != null) { batchIds.add(l.Batch__c); } }
        Map<Id, cqext__CQEBR_Batch__c> batches = batchIds.isEmpty() ? new Map<Id, cqext__CQEBR_Batch__c>()
            : new Map<Id, cqext__CQEBR_Batch__c>([SELECT Id, Name, cqext__Status__c, cqext__Released_Date__c FROM cqext__CQEBR_Batch__c WHERE Id IN :batchIds]);
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            cqext__CQEBR_Batch__c bt = l.Batch__c == null ? null : batches.get(l.Batch__c);
            if (bt == null) { continue; }
            add(out, l.Name, batchSay(bt.Name, bt.cqext__Status__c, bt.cqext__Released_Date__c));
        }
        return out;
    }

    /** What a lot's batch record says: Released lets the lot go and names it; Void rejects; anything else is Pending QA. */
    @TestVisible
    static Say batchSay(String br, String st, Date releasedOn) {
        Say s;
        if (st == 'Released') {
            s = new Say(null, br, null);
            s.basis = true;
            s.detail = 'Batch released' + datedD(releasedOn);
        } else if (st == 'Void') {
            s = new Say('Rejected', br, br + ': batch void');
            s.finalReject = true;
        } else {
            s = new Say('Pending QA', br, br + ': batch ' + (st == null ? 'not released' : st.toLowerCase()) + ', not yet released');
        }
        return s;
    }

    static void add(Map<String, List<Say>> m, String lot, Say s) {
        if (!m.containsKey(lot)) { m.put(lot, new List<Say>()); }
        m.get(lot).add(s);
    }
    static String byWhom(String person) { return person == null ? '' : ' by ' + person; }
    static String datedD(Date d) { return d == null ? '' : ' \u00b7 ' + Datetime.newInstance(d.year(), d.month(), d.day()).format('d MMM yyyy'); }
    static String dated(Datetime d) { return d == null ? '' : ' \u00b7 ' + d.format('d MMM yyyy'); }
    public static Integer rank(String s) { return s == null || !RANK.containsKey(s) ? 1 : RANK.get(s); }
    static String qty(Decimal d) { return d == null ? '' : d.stripTrailingZeros().toPlainString(); }
}

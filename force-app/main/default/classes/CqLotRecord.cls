/**
 * CqLotRecord: everything the Lot record screen (cqLotRecord) shows about one CQ Lot Info record, gathered in one call.
 * The lot's own fields (Lot Type, Release Status, Hold Reason, Sterilization Lot, supply data) come from Lot Info.
 * How it was made comes from CQ's batch record (cqext__CQEBR_Batch__c), read live and never copied onto the lot,
 * and what went into it from the component lot numbers recorded in the batch steps. A component lot shows where it was used.
 * Quality lists only records against this exact lot (complaints, NCs, field actions). A link that is only a guess, such
 * as a complaint whose words match a component's part name, is a CQ.AI suggestion, never a status.
 * On hand and locations come from Lot Stock and Lot Shipment (CqLotStock). Blank values are left out.
 */
public with sharing class CqLotRecord {

    public class Item {
        @AuraEnabled public String key;
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public Id id;
        @AuraEnabled public String tone;
    }
    public class Component {
        @AuraEnabled public String key;
        @AuraEnabled public String lot;
        @AuraEnabled public Id lotId;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String partName;
        @AuraEnabled public String lotType;
        @AuraEnabled public String supplier;
        @AuraEnabled public List<Item> flags = new List<Item>();   // records against this exact component lot
        @AuraEnabled public String aiNote;                          // a CQ.AI suggestion, never a status
        public String partType;                                     // CQ's Part Type, e.g. Sub Assembly, Raw Material
    }
    public class Place {
        @AuraEnabled public String key;
        @AuraEnabled public String location;
        @AuraEnabled public Id locationId;
        @AuraEnabled public Decimal units;
    }
    public class View {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String title;
        @AuraEnabled public String lotType;
        @AuraEnabled public String status;
        @AuraEnabled public String statusTone;
        @AuraEnabled public String conflict;           // final decisions on the lot disagree (CqLotStatus)
        @AuraEnabled public List<Item> header = new List<Item>();
        @AuraEnabled public Id batchId;
        @AuraEnabled public String batchName;
        @AuraEnabled public List<Item> made = new List<Item>();
        @AuraEnabled public List<Component> subAssemblies = new List<Component>();
        @AuraEnabled public List<Component> materials = new List<Component>();
        @AuraEnabled public List<Item> usedIn = new List<Item>();
        @AuraEnabled public List<Item> supply = new List<Item>();
        @AuraEnabled public List<Item> complaints = new List<Item>();
        @AuraEnabled public List<Item> ncs = new List<Item>();
        @AuraEnabled public List<Item> fieldActions = new List<Item>();
        @AuraEnabled public List<Item> aiNotes = new List<Item>();
        @AuraEnabled public Decimal onHand;
        @AuraEnabled public Decimal shipped;
        @AuraEnabled public Datetime stockAsOf;
        @AuraEnabled public List<Place> places = new List<Place>();
    }

    static final Set<String> CLOSED = new Set<String>{ 'Closed', 'Void', 'Voided', 'Cancelled', 'Complete', 'Completed' };

    @AuraEnabled
    public static View get(Id lotId) {
        try {
            return build(lotId);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public static View build(Id lotId) {
        compliancequest__SQX_Lot_Info__c l = [
            SELECT Id, Name, compliancequest__Part_Number__c, compliancequest__Manufacturing_Date__c, compliancequest__Expiration_Date__c,
                   Lot_Type__c, Release_Status__c, Hold_Reason__c, Status_Set_By__c, Status_Set_On__c, Status_Conflict__c, Sterilization_Lot__c, Supplier_Lot__c, Received_Date__c,
                   Receiving_Inspection__c, Supplier__c, Supplier__r.Name, Part__c, Part__r.Name, Part__r.compliancequest__Part_Number__c,
                   Batch__c, Batch__r.Name, Batch__r.cqext__Part_Product_Name__c, Batch__r.cqext__Part_Product_Number__c,
                   Batch__r.cqext__Part_Revision__c, Batch__r.cqext__Org_Site__c, Batch__r.cqext__Location_Name__c,
                   Batch__r.cqext__Start_Date__c, Batch__r.cqext__Manufactured_Date__c, Batch__r.cqext__Released_Date__c,
                   Batch__r.cqext__Expiration_Date__c, Batch__r.cqext__Quantity__c, Batch__r.cqext__Actual_Yield__c,
                   Batch__r.cqext__UoM__c, Batch__r.cqext__Status__c, Batch__r.cqext__CQEBR_Master_Batch__r.Name
            FROM compliancequest__SQX_Lot_Info__c WHERE Id = :lotId WITH USER_MODE];

        View v = new View();
        v.id = l.Id;
        v.name = l.Name;
        v.lotType = l.Lot_Type__c;
        v.status = l.Release_Status__c;
        v.statusTone = toneOf(l.Release_Status__c);
        cqext__CQEBR_Batch__c b = l.Batch__r;
        v.batchId = l.Batch__c;
        v.batchName = b?.Name;
        v.title = firstOf(b?.cqext__Part_Product_Name__c, l.Part__r?.Name);
        String partNumber = firstOf(firstOf(b?.cqext__Part_Product_Number__c, l.Part__r?.compliancequest__Part_Number__c), l.compliancequest__Part_Number__c);

        // the header: what the lot is and where it stands
        field(v.header, 'part', 'Part', partNumber, l.Part__c, null);
        field(v.header, 'type', 'Lot Type', l.Lot_Type__c, null, null);
        field(v.header, 'status', 'Release Status', l.Release_Status__c, null, v.statusTone);
        field(v.header, 'hold', 'Hold Reason', l.Hold_Reason__c, null, null);
        // what set the status, and when (Manual, a field action, an NC, receiving inspection)
        field(v.header, 'setby', 'Status Set By', l.Status_Set_By__c == null ? null
            : l.Status_Set_By__c + (l.Status_Set_On__c == null ? '' : ' \u00b7 ' + l.Status_Set_On__c.format('d MMM yyyy')), null, null);
        v.conflict = l.Status_Conflict__c;
        field(v.header, 'batch', 'Batch Record', b?.Name, l.Batch__c, null);
        field(v.header, 'steril', 'Sterilization Lot', l.Sterilization_Lot__c, null, null);

        // Made: read from the batch record; a lot with no batch shows its own dates
        if (b != null) {
            field(v.made, 'master', 'Master Batch', b.cqext__CQEBR_Master_Batch__r?.Name, null, null);
            field(v.made, 'start', 'Started', fmt(b.cqext__Start_Date__c), null, null);
            field(v.made, 'mfg', 'Manufactured', fmt(firstDate(b.cqext__Manufactured_Date__c, l.compliancequest__Manufacturing_Date__c)), null, null);
            field(v.made, 'rel', 'Released', fmt(b.cqext__Released_Date__c), null, null);
            field(v.made, 'exp', 'Expires', fmt(firstDate(b.cqext__Expiration_Date__c, l.compliancequest__Expiration_Date__c)), null, null);
            Decimal built = b.cqext__Actual_Yield__c != null && b.cqext__Actual_Yield__c > 0 ? b.cqext__Actual_Yield__c : b.cqext__Quantity__c;
            field(v.made, 'built', 'Built', built == null ? null : built.stripTrailingZeros().toPlainString() + (b.cqext__UoM__c == null ? '' : ' ' + b.cqext__UoM__c), null, null);
            field(v.made, 'rev', 'Revision', b.cqext__Part_Revision__c, null, null);
            field(v.made, 'site', 'Site', b.cqext__Org_Site__c, null, null);
            field(v.made, 'loc', 'Location', b.cqext__Location_Name__c, null, null);
            field(v.made, 'bstat', 'Batch Status', b.cqext__Status__c, null, null);
        } else {
            field(v.made, 'mfg', 'Manufactured', fmt(l.compliancequest__Manufacturing_Date__c), null, null);
            field(v.made, 'exp', 'Expires', fmt(l.compliancequest__Expiration_Date__c), null, null);
        }

        // Supply: purchased lots
        field(v.supply, 'sup', 'Supplier', l.Supplier__r?.Name, l.Supplier__c, null);
        field(v.supply, 'slot', 'Supplier Lot', l.Supplier_Lot__c, null, null);
        field(v.supply, 'recv', 'Received', fmt(l.Received_Date__c), null, null);
        field(v.supply, 'insp', 'Receiving Inspection', l.Receiving_Inspection__c, null,
            l.Receiving_Inspection__c == 'Accepted' ? 'pos' : l.Receiving_Inspection__c == 'Rejected' ? 'crit' : l.Receiving_Inspection__c == 'Pending' ? 'warn' : null);

        // Quality on this exact lot
        List<compliancequest__SQX_Complaint__c> comps = [
            SELECT Id, Name, compliancequest__Complaint_Title__c, compliancequest__Description__c, compliancequest__Status__c
            FROM compliancequest__SQX_Complaint__c
            WHERE compliancequest__SQX_Lot_Info__c = :l.Id OR compliancequest__Lot_Number__c = :l.Name
            WITH USER_MODE ORDER BY Name LIMIT 50];
        for (compliancequest__SQX_Complaint__c c : comps) {
            rec(v.complaints, c.Id, c.Name, c.compliancequest__Complaint_Title__c, c.Id, CLOSED.contains(c.compliancequest__Status__c) ? null : 'open');
        }
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Status__c FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__Lot_Number__c = :l.Name WITH USER_MODE ORDER BY Name LIMIT 50]) {
            rec(v.ncs, n.Id, n.Name, n.compliancequest__NC_Title__c, n.Id, CLOSED.contains(n.compliancequest__Status__c) ? null : 'open');
        }
        Map<Id, Field_Action__c> fas = new Map<Id, Field_Action__c>();
        for (Field_Action_Lot__c fl : [SELECT Field_Action__c, Field_Action__r.Name FROM Field_Action_Lot__c
                                       WHERE Lot__c = :l.Id OR Lot_Number__c = :l.Name WITH USER_MODE LIMIT 50]) {
            fas.put(fl.Field_Action__c, fl.Field_Action__r);
        }
        Set<Id> heldBy = new Set<Id>();
        for (Field_Action_Hold__c h : [SELECT Field_Action__c, Field_Action__r.Name FROM Field_Action_Hold__c
                                       WHERE Lot_Number__c = :l.Name AND Held__c = true WITH USER_MODE LIMIT 50]) {
            fas.put(h.Field_Action__c, h.Field_Action__r);
            heldBy.add(h.Field_Action__c);
        }
        for (Field_Action__c fa : fas.values()) {
            if (fa == null) { continue; }
            rec(v.fieldActions, fa.Id, fa.Name, heldBy.contains(fa.Id) ? 'Holds this lot' : 'Lot in scope', fa.Id, null);
        }

        // What went into it: the component lots recorded in the batch steps
        if (l.Batch__c != null) {
            components(v, l.Batch__c, comps);
        }
        // Where a component lot was used: the finished lots whose batch steps recorded it
        usedIn(v, l.Name, l.Batch__c);

        // On hand and where it is
        Map<String, CqLotStock.Stock> stock = CqLotStock.forLots(new Set<String>{ l.Name });
        CqLotStock.Stock st = stock.get(l.Name);
        if (st != null && st.hasRecord) {
            v.onHand = st.total;
            v.stockAsOf = st.asOf;
            Integer i = 0;
            for (CqLotStock.Place p : st.places) {
                Place x = new Place();
                x.key = 'p' + (i++);
                x.location = p.location;
                x.locationId = p.locationId;
                x.units = p.units;
                v.places.add(x);
            }
        }
        Decimal shipped = CqLotShipments.totals(new Set<String>{ l.Name }).get(l.Name);
        v.shipped = shipped;
        return v;
    }

    static void components(View v, Id batchId, List<compliancequest__SQX_Complaint__c> comps) {
        Map<String, Component> byLot = new Map<String, Component>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Operator_Product__r.Name, cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c,
                       cqext__CQEBR_Operator_Product__r.compliancequest__Part_Type__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c != null AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c = :batchId
                WITH USER_MODE ORDER BY Name LIMIT 2000]) {
            String lot = m.cqext__Lot_Number__c.trim();
            if (byLot.containsKey(lot)) { continue; }
            Component c = new Component();
            c.key = lot;
            c.lot = lot;
            c.partNumber = m.cqext__CQEBR_Operator_Product__r?.compliancequest__Part_Number__c;
            c.partName = m.cqext__CQEBR_Operator_Product__r?.Name;
            c.partType = m.cqext__CQEBR_Operator_Product__r?.compliancequest__Part_Type__c;
            byLot.put(lot, c);
        }
        if (byLot.isEmpty()) { return; }
        Set<String> lots = byLot.keySet();
        for (compliancequest__SQX_Lot_Info__c cl : [
                SELECT Id, Name, Lot_Type__c, Release_Status__c, Supplier__r.Name FROM compliancequest__SQX_Lot_Info__c
                WHERE Name IN :lots WITH USER_MODE]) {
            Component c = byLot.get(cl.Name);
            c.lotId = cl.Id;
            c.lotType = cl.Lot_Type__c;
            c.supplier = cl.Supplier__r?.Name;
            if (cl.Release_Status__c != null && cl.Release_Status__c != 'Released' && cl.Release_Status__c != 'Pending QA') {
                rec(c.flags, 'st', cl.Release_Status__c, null, null, toneOf(cl.Release_Status__c));
            }
        }
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__Status__c FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__Lot_Number__c IN :lots WITH USER_MODE LIMIT 500]) {
            if (CLOSED.contains(n.compliancequest__Status__c)) { continue; }
            rec(byLot.get(n.compliancequest__Lot_Number__c).flags, n.Id, n.Name, null, n.Id, 'crit');
        }
        for (compliancequest__SQX_Complaint__c c : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__Status__c FROM compliancequest__SQX_Complaint__c
                WHERE compliancequest__Lot_Number__c IN :lots WITH USER_MODE LIMIT 500]) {
            if (CLOSED.contains(c.compliancequest__Status__c)) { continue; }
            rec(byLot.get(c.compliancequest__Lot_Number__c).flags, c.Id, c.Name, null, c.Id, 'warn');
        }
        // CQ.AI suggestion: a complaint on this lot whose words name a component's part
        for (compliancequest__SQX_Complaint__c c : comps) {
            String text = (' ' + (c.compliancequest__Complaint_Title__c == null ? '' : c.compliancequest__Complaint_Title__c) + ' '
                + (c.compliancequest__Description__c == null ? '' : c.compliancequest__Description__c) + ' ').toLowerCase();
            List<String> matched = new List<String>();
            Set<String> phrases = new Set<String>();
            for (Component k : byLot.values()) {
                String phrase = matchPhrase(k.partName, text);
                if (phrase == null) { continue; }
                k.aiNote = 'May relate to ' + c.Name + ': the complaint mentions the ' + phrase + '.';
                matched.add(k.lot + ' (' + k.partName.substringBefore(',') + ')');
                phrases.add(phrase);
            }
            if (!matched.isEmpty()) {
                matched.sort();
                // one note per complaint, naming every component lot it may relate to
                rec(v.aiNotes, String.valueOf(c.Id), c.Name, c.Name + ' (' + c.compliancequest__Complaint_Title__c + ') mentions the '
                    + String.join(new List<String>(phrases), ' and ') + '. Component lots in this lot that match: ' + String.join(matched, ', ')
                    + '. Not recorded as a link; check before acting on it.', c.Id, null);
            }
        }
        for (Component c : byLot.values()) {
            // the lot's own Lot Type when it has one, otherwise CQ's Part Type for the part
            Boolean sub = c.lotType != null ? c.lotType == 'Sub-assembly' : c.partType == 'Sub Assembly';
            if (sub) { v.subAssemblies.add(c); } else { v.materials.add(c); }
        }
        v.materials.sort(new FlaggedFirst());
        v.subAssemblies.sort(new FlaggedFirst());
    }

    /** A two-word phrase from the part's name (before any comma), e.g. 'marker band', found in the complaint text. */
    @TestVisible
    static String matchPhrase(String partName, String text) {
        if (String.isBlank(partName) || String.isBlank(text)) { return null; }
        String head = partName.substringBefore(',').toLowerCase().replaceAll('[^a-z ]', ' ');
        List<String> words = new List<String>();
        for (String w : head.split(' ')) { if (w.length() >= 3 && w != 'and' && w != 'sub' && w != 'assembly') { words.add(w); } }
        for (Integer i = 0; i < words.size() - 1; i++) {
            String p = words[i] + ' ' + words[i + 1];
            if (text.contains(' ' + p + ' ') || text.contains(' ' + p + 's ') || text.contains(' ' + p + ',') || text.contains(' ' + p + '.')) { return p; }
        }
        return null;
    }

    static void usedIn(View v, String lotNumber, Id ownBatch) {
        Set<Id> batches = new Set<Id>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c WHERE cqext__Lot_Number__c = :lotNumber WITH USER_MODE LIMIT 2000]) {
            Id b = m.cqext__CQEBR_Batch_Sub_Step__r?.cqext__CQEBR_Batch_Step__r?.cqext__CQEBR_Batch__c;
            if (b != null && b != ownBatch) { batches.add(b); }
        }
        if (batches.isEmpty()) { return; }
        for (compliancequest__SQX_Lot_Info__c f : [SELECT Id, Name, Release_Status__c FROM compliancequest__SQX_Lot_Info__c
                                                   WHERE Batch__c IN :batches WITH USER_MODE ORDER BY Name LIMIT 200]) {
            rec(v.usedIn, f.Id, f.Name, f.Release_Status__c, f.Id, toneOf(f.Release_Status__c));
        }
    }

    class FlaggedFirst implements Comparator<Component> {
        public Integer compare(Component a, Component b) {
            Integer fa = a.flags.isEmpty() && a.aiNote == null ? 1 : 0;
            Integer fb = b.flags.isEmpty() && b.aiNote == null ? 1 : 0;
            if (fa != fb) { return fa - fb; }
            Integer na = a.flags.isEmpty() ? 1 : 0;
            Integer nb = b.flags.isEmpty() ? 1 : 0;
            if (na != nb) { return na - nb; }
            return (a.partNumber == null ? a.lot : a.partNumber).compareTo(b.partNumber == null ? b.lot : b.partNumber);
        }
    }

    static String toneOf(String status) {
        if (status == null) { return null; }
        if (status == 'Released') { return 'pos'; }
        if (status == 'On Hold' || status == 'Pending QA') { return 'warn'; }
        return 'crit';   // Quarantined, Rejected, Recalled
    }
    /** A field: left out when it has no value, so blank batch or lot fields don't show. */
    static void field(List<Item> target, String key, String label, String value, Id id, String tone) {
        if (String.isBlank(value)) { return; }
        rec(target, key, label, value, id, tone);
    }
    /** A record or a status flag: always shown, its name in label. */
    static void rec(List<Item> target, String key, String label, String value, Id id, String tone) {
        Item x = new Item();
        x.key = key;
        x.label = label;
        x.value = value;
        x.id = id;
        x.tone = tone;
        target.add(x);
    }
    static String firstOf(String a, String b) { return String.isNotBlank(a) ? a : b; }
    static Date firstDate(Date a, Date b) { return a != null ? a : b; }
    static String fmt(Date d) { return d == null ? null : Datetime.newInstance(d.year(), d.month(), d.day()).format('d MMM yyyy'); }
}

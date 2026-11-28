/**
 * Triage, step 1: Impact (Lou, 28 Nov 2026; board "Lots on an NC"). Replaces the Containment step.
 *
 * The lots that have the problem, how many units of each, and the containment holding each one. People only ever see
 * "lot": each one is a CQ Impacted Product (part, lot, quantity), which Disposition works from later. The NC's own lot
 * (the reported one) is always first and cannot be removed here; when the NC has a lot that is not stored yet (no
 * quantity was known when it was saved, CqNcLots), it is shown as pending, and the triager enters its quantity.
 *
 * A containment made for one lot is linked to it (our Lot field on CQ's containment, Impacted_Lot__c); one made for all
 * lots has no lot and shows on every row.
 *
 * CQ.AI suggests other lots to check: other lots of the same part that share a supplier lot or a sterilization load with
 * one of this NC's lots, have a complaint reporting the same problem (a telling word shared with the NC's title and
 * description), or were made within 10 days of one. Only real matches from
 * CQ's lot records and complaints are shown; a reason with no data behind it never appears.
 */
public with sharing class CqTriageImpact {
    public static final Integer NEAR_DAYS = 10;
    public static final Integer MAX_SUGGESTIONS = 6;

    public class Ref { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title; }
    public class Lot {
        @AuraEnabled public Id id;                      // the Impacted Product; null for the pending reported lot
        @AuraEnabled public String lot;
        @AuraEnabled public String part;
        @AuraEnabled public Decimal qty;
        @AuraEnabled public Boolean reported = false;   // the NC's own lot
        @AuraEnabled public Boolean pending = false;    // the NC's own lot, not stored yet: needs a quantity
        @AuraEnabled public Boolean canRemove = false;
        @AuraEnabled public Decimal disposed = 0;
        @AuraEnabled public List<Ref> containments = new List<Ref>();
    }
    public class Suggestion {
        @AuraEnabled public String lot; @AuraEnabled public String why; @AuraEnabled public String status;
        @AuraEnabled public Integer rank;
    }
    public class Impact {
        @AuraEnabled public List<Lot> lots = new List<Lot>();
        @AuraEnabled public List<Ref> allLots = new List<Ref>();     // containments for every lot
        @AuraEnabled public List<Suggestion> suggestions = new List<Suggestion>();
        @AuraEnabled public String partName; @AuraEnabled public Id partId;
        @AuraEnabled public String reportedLot;
        @AuraEnabled public Boolean editable = true;                 // CQ refuses changes to lots from Implement on
        @AuraEnabled public Decimal defective;
    }

    @AuraEnabled
    public static Impact getImpact(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = nc(recordId);
        Impact x = new Impact();
        x.partId = nc.compliancequest__SQX_Part__c;
        x.partName = nc.compliancequest__SQX_Part__r == null ? null : partLabel(nc.compliancequest__SQX_Part__r);
        x.reportedLot = String.isBlank(nc.compliancequest__Lot_Number__c) ? null : nc.compliancequest__Lot_Number__c.trim();
        x.defective = nc.compliancequest__Defective_Quantity__c;
        x.editable = !CqNcLots.LOCKED.contains(nc.compliancequest__Record_Stage__c);

        Map<Id, Lot> byId = new Map<Id, Lot>();
        Boolean reportedStored = false;
        for (compliancequest__SQX_NC_Impacted_Product__c ip : [
                SELECT Id, compliancequest__Lot_Number__c, compliancequest__Lot_Quantity__c, compliancequest__Total_Quantity_Disposed__c,
                       compliancequest__SQX_Impacted_Part__r.Name, compliancequest__SQX_Impacted_Part__r.compliancequest__Part_Number__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c = :recordId
                WITH USER_MODE ORDER BY CreatedDate, Name]) {
            Lot l = new Lot();
            l.id = ip.Id; l.lot = ip.compliancequest__Lot_Number__c; l.qty = ip.compliancequest__Lot_Quantity__c;
            l.part = ip.compliancequest__SQX_Impacted_Part__r == null ? x.partName : partLabel(ip.compliancequest__SQX_Impacted_Part__r);
            l.disposed = ip.compliancequest__Total_Quantity_Disposed__c == null ? 0 : ip.compliancequest__Total_Quantity_Disposed__c;
            l.reported = x.reportedLot != null && CqNcLots.same(l.lot, x.reportedLot) && !reportedStored;
            if (l.reported) { reportedStored = true; }
            l.canRemove = x.editable && !l.reported && l.disposed == 0;
            byId.put(l.id, l);
            x.lots.add(l);
        }
        if (x.reportedLot != null && !reportedStored) {
            Lot p = new Lot();
            p.lot = x.reportedLot; p.part = x.partName; p.reported = true; p.pending = true;
            p.qty = nc.compliancequest__Defective_Quantity__c != null && nc.compliancequest__Defective_Quantity__c > 0 ? nc.compliancequest__Defective_Quantity__c : null;
            x.lots.add(p);   // put first below
        }
        // the reported lot first, then the others in the order they were added
        List<Lot> ordered = new List<Lot>();
        for (Lot l : x.lots) { if (l.reported) { ordered.add(l); } }
        for (Lot l : x.lots) { if (!l.reported) { ordered.add(l); } }
        x.lots = ordered;

        for (compliancequest__SQX_Containment__c c : [SELECT Id, Name, compliancequest__Title__c, Impacted_Lot__c
                FROM compliancequest__SQX_Containment__c WHERE compliancequest__SQX_Nonconformance__c = :recordId
                AND compliancequest__Status__c != 'Void' WITH USER_MODE ORDER BY CreatedDate, Name]) {
            Ref r = new Ref(); r.id = c.Id; r.name = c.Name; r.title = c.compliancequest__Title__c;
            if (c.Impacted_Lot__c != null && byId.containsKey(c.Impacted_Lot__c)) { byId.get(c.Impacted_Lot__c).containments.add(r); }
            else { x.allLots.add(r); }
        }
        if (x.partId != null) { x.suggestions = suggest(x, words(nc.compliancequest__NC_Title__c + ' ' + nc.compliancequest__Description__c, nc.compliancequest__SQX_Part__r)); }
        return x;
    }

    /** Saves a lot: a new one (impactedId null, lot named), the pending reported lot (its quantity), or a quantity change. */
    @AuraEnabled
    public static Id saveLot(Id recordId, Id impactedId, String lot, Decimal quantity) {
        compliancequest__SQX_Nonconformance__c nc = nc(recordId);
        if (CqNcLots.LOCKED.contains(nc.compliancequest__Record_Stage__c)) { throw new AuraHandledException('Lots can\'t change once the NC is in Implement.'); }
        if (quantity == null || quantity <= 0) { throw new AuraHandledException('Enter how many units have the problem.'); }
        if (quantity.scale() > 2) { throw new AuraHandledException('Enter the quantity with at most two decimal places.'); }
        try {
            if (impactedId != null) {
                compliancequest__SQX_NC_Impacted_Product__c ip = [SELECT Id, compliancequest__SQX_Nonconformance__c FROM compliancequest__SQX_NC_Impacted_Product__c
                    WHERE Id = :impactedId WITH USER_MODE];
                if (ip.compliancequest__SQX_Nonconformance__c != recordId) { throw new AuraHandledException('That lot is not on this NC.'); }
                update as user new compliancequest__SQX_NC_Impacted_Product__c(Id = impactedId, compliancequest__Lot_Quantity__c = quantity);
                return impactedId;
            }
            if (String.isBlank(lot)) { throw new AuraHandledException('Enter the lot number.'); }
            String name = lot.trim().left(80);
            for (compliancequest__SQX_NC_Impacted_Product__c ip : [SELECT compliancequest__Lot_Number__c FROM compliancequest__SQX_NC_Impacted_Product__c
                    WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE]) {
                if (CqNcLots.same(ip.compliancequest__Lot_Number__c, name)) { throw new AuraHandledException('Lot ' + name + ' is already on this NC.'); }
            }
            compliancequest__SQX_NC_Impacted_Product__c ip = new compliancequest__SQX_NC_Impacted_Product__c(compliancequest__SQX_Nonconformance__c = recordId,
                compliancequest__SQX_Impacted_Part__c = nc.compliancequest__SQX_Part__c, compliancequest__Lot_Number__c = name,
                compliancequest__Lot_Quantity__c = quantity);
            insert as user ip;
            return ip.Id;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not accept the lot: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            throw new AuraHandledException('CQ did not accept the lot: ' + CqSave.DENIED);
        }
    }

    /** Removes a lot added by mistake. Not the NC's own lot, and not a lot with a disposition. */
    @AuraEnabled
    public static void removeLot(Id recordId, Id impactedId) {
        compliancequest__SQX_Nonconformance__c nc = nc(recordId);
        if (CqNcLots.LOCKED.contains(nc.compliancequest__Record_Stage__c)) { throw new AuraHandledException('Lots can\'t change once the NC is in Implement.'); }
        compliancequest__SQX_NC_Impacted_Product__c ip = [SELECT Id, compliancequest__SQX_Nonconformance__c, compliancequest__Lot_Number__c,
                compliancequest__Total_Quantity_Disposed__c FROM compliancequest__SQX_NC_Impacted_Product__c WHERE Id = :impactedId WITH USER_MODE];
        if (ip.compliancequest__SQX_Nonconformance__c != recordId) { throw new AuraHandledException('That lot is not on this NC.'); }
        if (CqNcLots.same(ip.compliancequest__Lot_Number__c, nc.compliancequest__Lot_Number__c)) { throw new AuraHandledException('The reported lot stays on the NC.'); }
        if (ip.compliancequest__Total_Quantity_Disposed__c != null && ip.compliancequest__Total_Quantity_Disposed__c > 0) {
            throw new AuraHandledException('Lot ' + ip.compliancequest__Lot_Number__c + ' has a disposition, so it stays.');
        }
        try {
            delete as user ip;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not remove the lot: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            throw new AuraHandledException('CQ did not remove the lot: ' + CqSave.DENIED);
        }
    }

    /** Adds a containment for one lot (impactedId) or for every lot (null), straight away. Returns its number. */
    @AuraEnabled
    public static String addContainment(Id recordId, Id impactedId, String title, String description, String dueDate, Id assigneeId) {
        if (recordId == null || String.isBlank(title)) { throw new AuraHandledException('Give the containment a title.'); }
        if (String.isBlank(dueDate)) { throw new AuraHandledException('Set a due date.'); }
        if (impactedId != null) {
            List<compliancequest__SQX_NC_Impacted_Product__c> ip = [SELECT Id FROM compliancequest__SQX_NC_Impacted_Product__c
                WHERE Id = :impactedId AND compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE];
            if (ip.isEmpty()) { throw new AuraHandledException('That lot is not on this NC.'); }
        }
        compliancequest__SQX_Containment__c c = new compliancequest__SQX_Containment__c(
            compliancequest__SQX_Nonconformance__c = recordId, Impacted_Lot__c = impactedId,
            compliancequest__Title__c = title.trim().left(255),
            compliancequest__Description__c = String.isBlank(description) ? null : description.trim(),
            compliancequest__Due_Date__c = Date.valueOf(dueDate),
            compliancequest__SQX_User__c = assigneeId == null ? UserInfo.getUserId() : assigneeId);
        try {
            insert as user c;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not accept the containment: ' + e.getDmlMessage(0));
        } catch (SecurityException e) {
            throw new AuraHandledException('CQ did not accept the containment: ' + CqSave.DENIED);
        }
        return [SELECT Name FROM compliancequest__SQX_Containment__c WHERE Id = :c.Id WITH USER_MODE].Name;
    }

    // ------------------------------------------------------------ suggested lots

    /** Other lots of the part worth checking, strongest reason first; lots already on the NC are left out. */
    public static List<Suggestion> suggest(Impact x, Set<String> problem) {
        Set<String> mine = new Set<String>();
        for (Lot l : x.lots) { if (l.lot != null) { mine.add(l.lot.trim().toUpperCase()); } }
        if (mine.isEmpty()) { return new List<Suggestion>(); }
        Id partId = x.partId;
        List<compliancequest__SQX_Lot_Info__c> partLots = Database.query('SELECT Name, compliancequest__Manufacturing_Date__c, Sterilization_Lot__c,'
            + ' Supplier_Lot__c, Release_Status__c FROM compliancequest__SQX_Lot_Info__c WHERE Part__c = :partId'
            + ' ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST LIMIT 500', AccessLevel.USER_MODE);
        List<compliancequest__SQX_Lot_Info__c> ours = new List<compliancequest__SQX_Lot_Info__c>();
        for (compliancequest__SQX_Lot_Info__c li : partLots) { if (mine.contains(li.Name.trim().toUpperCase())) { ours.add(li); } }

        Map<String, Suggestion> best = new Map<String, Suggestion>();
        Map<String, compliancequest__SQX_Lot_Info__c> info = new Map<String, compliancequest__SQX_Lot_Info__c>();
        for (compliancequest__SQX_Lot_Info__c li : partLots) {
            String k = li.Name.trim().toUpperCase();
            if (mine.contains(k)) { continue; }
            info.put(k, li);
            for (compliancequest__SQX_Lot_Info__c o : ours) {
                if (String.isNotBlank(li.Supplier_Lot__c) && li.Supplier_Lot__c == o.Supplier_Lot__c) {
                    keep(best, li, 1, 'Same supplier lot ' + li.Supplier_Lot__c + ' as ' + o.Name);
                }
                if (String.isNotBlank(li.Sterilization_Lot__c) && li.Sterilization_Lot__c == o.Sterilization_Lot__c) {
                    keep(best, li, 2, 'Same sterilization load ' + li.Sterilization_Lot__c + ' as ' + o.Name);
                }
                if (li.compliancequest__Manufacturing_Date__c != null && o.compliancequest__Manufacturing_Date__c != null) {
                    Integer d = o.compliancequest__Manufacturing_Date__c.daysBetween(li.compliancequest__Manufacturing_Date__c);
                    if (Math.abs(d) <= NEAR_DAYS && d != 0) {
                        keep(best, li, 4, 'Made ' + Math.abs(d) + (Math.abs(d) == 1 ? ' day ' : ' days ') + (d < 0 ? 'before ' : 'after ') + o.Name);
                    }
                }
            }
        }
        // a complaint on another lot of the part that reports the same problem (shares a telling word with this NC)
        for (compliancequest__SQX_Complaint__c cp : [SELECT Name, compliancequest__Lot_Number__c, compliancequest__Complaint_Title__c
                FROM compliancequest__SQX_Complaint__c WHERE compliancequest__SQX_Part__c = :partId AND compliancequest__Lot_Number__c != null
                WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 500]) {
            String k = cp.compliancequest__Lot_Number__c.trim().toUpperCase();
            if (mine.contains(k) || (best.containsKey(k) && best.get(k).rank <= 3)) { continue; }
            Set<String> w = words(cp.compliancequest__Complaint_Title__c, null);
            w.retainAll(problem);
            if (w.isEmpty()) { continue; }
            Suggestion s = new Suggestion(); s.lot = cp.compliancequest__Lot_Number__c.trim(); s.rank = 3;
            s.why = 'Complaint ' + cp.Name + ' on this lot: ' + cp.compliancequest__Complaint_Title__c;
            s.status = info.containsKey(k) ? info.get(k).Release_Status__c : null;
            best.put(k, s);
        }
        List<Suggestion> out = best.values();
        List<SugSort> s = new List<SugSort>();
        for (Suggestion x2 : out) { s.add(new SugSort(x2)); }
        s.sort();
        List<Suggestion> top = new List<Suggestion>();
        for (SugSort x3 : s) { if (top.size() < MAX_SUGGESTIONS) { top.add(x3.s); } }
        return top;
    }
    static final Set<String> COMMON = new Set<String>{ 'after', 'befor', 'durin', 'found', 'recei', 'prepa', 'about', 'there', 'which',
        'their', 'units', 'would', 'could', 'while', 'other', 'being', 'where', 'shoul', 'final', 'funct' };
    /** The telling words of a problem: words of five letters or more, cut to their first five (deflate, deflated, deflation),
     *  leaving out common words and the part's own name (every complaint on a balloon catheter says balloon). */
    public static Set<String> words(String text, compliancequest__SQX_Part__c part) {
        Set<String> skip = new Set<String>(COMMON);
        if (part != null) { skip.addAll(raw((part.Name == null ? '' : part.Name) + ' ' + (part.compliancequest__Part_Number__c == null ? '' : part.compliancequest__Part_Number__c))); }
        Set<String> out = raw(text);
        out.removeAll(skip);
        return out;
    }
    static Set<String> raw(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) { return out; }
        for (String w : text.toLowerCase().split('[^a-z]+')) { if (w.length() >= 5) { out.add(w.left(5)); } }
        return out;
    }
    static void keep(Map<String, Suggestion> best, compliancequest__SQX_Lot_Info__c li, Integer rank, String why) {
        String k = li.Name.trim().toUpperCase();
        if (best.containsKey(k) && best.get(k).rank <= rank) { return; }
        Suggestion s = new Suggestion(); s.lot = li.Name; s.rank = rank; s.why = why; s.status = li.Release_Status__c;
        best.put(k, s);
    }
    class SugSort implements Comparable {
        Suggestion s;
        SugSort(Suggestion s) { this.s = s; }
        public Integer compareTo(Object o) {
            Suggestion b = ((SugSort) o).s;
            if (s.rank != b.rank) { return s.rank - b.rank; }
            return s.lot.compareTo(b.lot);
        }
    }

    // ------------------------------------------------------------ helpers

    static compliancequest__SQX_Nonconformance__c nc(Id recordId) {
        List<compliancequest__SQX_Nonconformance__c> rows = [SELECT Id, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                compliancequest__NC_Title__c, compliancequest__Description__c,
                compliancequest__SQX_Part__r.Name, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                compliancequest__Defective_Quantity__c, compliancequest__Record_Stage__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE];
        if (rows.isEmpty()) { throw new AuraHandledException('This page works on a nonconformance.'); }
        return rows[0];
    }
    static String partLabel(compliancequest__SQX_Part__c p) {
        return String.isNotBlank(p.compliancequest__Part_Number__c) ? p.compliancequest__Part_Number__c : p.Name;
    }
}

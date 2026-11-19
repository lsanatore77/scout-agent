/**
 * CqInvestigationHistory: the Check History step of the CQ.AI Investigation workspace.
 *
 * getHistory() ranks past records for the NC with the Product History Review relevance model (PhrQmsRelevance,
 * used as is): the NC's part, its bill of materials components, its lot, the words in its title and description
 * and its defect code. Change orders are left to What Changed. Records that match the problem (the symptom
 * criterion) or share the lot are listed; records that only share the part are counted and kept behind Show Them.
 * Each NC carries its investigation's root causes and its CAPA, with the CAPA's latest completed effectiveness
 * review. A closed NC on the same problem, before this one started, whose fix (CAPA) was closed is a recurrence:
 * the problem happened before and the fix did not hold.
 *
 * markNotRelevant() and restore() keep records the user dismissed off this investigation's list.
 */
public with sharing class CqInvestigationHistory {

    public class Item {
        @AuraEnabled public String key; @AuraEnabled public String type; @AuraEnabled public Id recordId; @AuraEnabled public String name;
        @AuraEnabled public String status; @AuraEnabled public Date day; @AuraEnabled public String whatHappened;
        @AuraEnabled public String causeHead; @AuraEnabled public String causeNote; @AuraEnabled public Id investigationId; @AuraEnabled public String investigationName;
        @AuraEnabled public Id capaId; @AuraEnabled public String capaName; @AuraEnabled public String capaTitle; @AuraEnabled public String capaStatus;
        @AuraEnabled public Date capaClosed;
        @AuraEnabled public Id efrId; @AuraEnabled public String efrName; @AuraEnabled public String efrResolution; @AuraEnabled public Date efrDate;
        @AuraEnabled public String colour; @AuraEnabled public Integer score; @AuraEnabled public String why;
        @AuraEnabled public Boolean problemMatch = false; @AuraEnabled public Integer hypothesis; @AuraEnabled public String category;
    }
    public class Dismissed {
        @AuraEnabled public Id id; @AuraEnabled public String recordId; @AuraEnabled public String name; @AuraEnabled public String reason;
        @AuraEnabled public Boolean atTriage = false;    // marked Not the Same Problem in triage, before the investigation
    }
    public class View {
        @AuraEnabled public Date startDate; @AuraEnabled public String partNumber;
        @AuraEnabled public List<Item> items = new List<Item>();        // match the problem or the lot
        @AuraEnabled public List<Item> others = new List<Item>();       // the part only
        @AuraEnabled public List<Item> recurrences = new List<Item>();  // happened before, and the fix did not hold
        @AuraEnabled public List<Dismissed> dismissed = new List<Dismissed>();
        @AuraEnabled public List<String> categories = new List<String>();
    }

    @AuraEnabled
    public static View getHistory(Id recordId) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        compliancequest__SQX_Investigation__c inv = [SELECT compliancequest__SQX_Nonconformance__c FROM compliancequest__SQX_Investigation__c WHERE Id = :invId WITH USER_MODE];
        if (inv.compliancequest__SQX_Nonconformance__c == null) { View v = new View(); v.categories = categories(); return v; }
        return rank(inv.compliancequest__SQX_Nonconformance__c, invId);
    }

    /** The same ranking for an NC that has no investigation yet (triage). */
    public static View forNc(Id ncId) { return rank(ncId, null); }

    static List<String> categories() {
        List<String> out = new List<String>();
        for (Schema.PicklistEntry p : Investigation_Hypothesis__c.Category__c.getDescribe().getPicklistValues()) { if (p.isActive()) { out.add(p.getValue()); } }
        return out;
    }

    static View rank(Id ncId, Id invId) {
        View v = new View();
        v.categories = categories();
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT Id, compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__Lot_Number__c,
                   compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Defect_Code__c,
                   compliancequest__Occurrence_Date__c, compliancequest__Aware_Date__c, CreatedDate
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId WITH USER_MODE];
        v.partNumber = nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
        v.startDate = nc.compliancequest__Occurrence_Date__c != null ? toDate(nc.compliancequest__Occurrence_Date__c)
            : nc.compliancequest__Aware_Date__c != null ? toDate(nc.compliancequest__Aware_Date__c) : nc.CreatedDate.date();

        // what the user marked Not Relevant on this investigation, or Not the Same Problem in this NC's triage
        Set<String> gone = new Set<String>();
        List<Investigation_Not_Relevant__c> marked = invId == null
            ? [SELECT Id, Record_Id__c, Record_Name__c, Reason__c, Nonconformance__c FROM Investigation_Not_Relevant__c WHERE Nonconformance__c = :ncId WITH USER_MODE ORDER BY CreatedDate]
            : [SELECT Id, Record_Id__c, Record_Name__c, Reason__c, Nonconformance__c FROM Investigation_Not_Relevant__c
               WHERE Investigation__c = :invId OR Nonconformance__c = :ncId WITH USER_MODE ORDER BY CreatedDate];
        for (Investigation_Not_Relevant__c d : marked) {
            Dismissed x = new Dismissed();
            x.id = d.Id; x.recordId = d.Record_Id__c; x.name = d.Record_Name__c; x.reason = d.Reason__c; x.atTriage = d.Nonconformance__c != null;
            v.dismissed.add(x);
            if (d.Record_Id__c != null) { gone.add(d.Record_Id__c.left(15)); }
        }

        // rank with the Product History Review model
        PhrQmsRelevance.Input inp = new PhrQmsRelevance.Input();
        inp.ownPartId = nc.compliancequest__SQX_Part__c;
        inp.componentIds = components(nc.compliancequest__SQX_Part__c);
        if (String.isNotBlank(nc.compliancequest__Lot_Number__c)) { inp.lots.add(nc.compliancequest__Lot_Number__c); }
        inp.symptomText = (nc.compliancequest__NC_Title__c == null ? '' : nc.compliancequest__NC_Title__c) + ' ' + (nc.compliancequest__Description__c == null ? '' : nc.compliancequest__Description__c);
        inp.complaintCodeId = nc.compliancequest__SQX_Defect_Code__c;
        inp.occurrenceDate = v.startDate;
        PhrQmsPanelController.PanelData d = new PhrQmsPanelController.PanelData();
        if (inp.ownPartId != null) { PhrQmsRelevance.populate(inp, d); }
        List<PhrQmsPanelController.Row> rows = new List<PhrQmsPanelController.Row>();
        rows.addAll(d.nonconformances); rows.addAll(d.capas); rows.addAll(d.inspections); rows.addAll(d.setAside);

        Map<Id, Item> byId = new Map<Id, Item>();
        Set<Id> ncIds = new Set<Id>(); Set<Id> capaIds = new Set<Id>(); Set<Id> insIds = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null || r.id == nc.Id || byId.containsKey(r.id)) { continue; }
            if (r.recordType == PhrQmsRelevance.TYPE_CO) { continue; }
            if (gone.contains(String.valueOf(r.id).left(15))) { continue; }
            Item it = new Item();
            it.key = String.valueOf(r.id); it.recordId = r.id; it.name = r.name; it.type = r.recordType; it.status = r.status;
            it.colour = r.colour; it.score = r.relevance;
            it.day = r.createdDate == null ? null : r.createdDate.date();
            String crit = r.criteriaMet == null ? '' : r.criteriaMet;
            it.problemMatch = crit.contains('Symptom') || crit.contains('Lot');
            it.why = why(r, crit);
            byId.put(r.id, it);
            if (r.recordType == PhrQmsRelevance.TYPE_NC) { ncIds.add(r.id); }
            else if (r.recordType == PhrQmsRelevance.TYPE_CAPA) { capaIds.add(r.id); }
            else if (r.recordType == PhrQmsRelevance.TYPE_INSPECTION) { insIds.add(r.id); }
        }

        // NCs: what happened, the investigation's root causes, the CAPA
        Map<Id, Id> invOfNc = new Map<Id, Id>();
        Map<Id, Id> capaOfNc = new Map<Id, Id>();
        if (!ncIds.isEmpty()) {
            for (compliancequest__SQX_Nonconformance__c n : [
                    SELECT Id, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__Occurrence_Date__c, compliancequest__Lot_Number__c,
                           compliancequest__SQX_Investigation__c, compliancequest__SQX_Investigation__r.Name, compliancequest__SQX_Investigation__r.compliancequest__Status__c,
                           compliancequest__SQX_CAPA__c
                    FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :ncIds WITH USER_MODE]) {
                Item it = byId.get(n.Id);
                it.whatHappened = joinText(n.compliancequest__NC_Title__c, n.compliancequest__Description__c);
                if (n.compliancequest__Occurrence_Date__c != null) { it.day = toDate(n.compliancequest__Occurrence_Date__c); }
                it.investigationId = n.compliancequest__SQX_Investigation__c;
                if (n.compliancequest__SQX_Investigation__r != null) {
                    it.investigationName = n.compliancequest__SQX_Investigation__r.Name;
                    it.causeNote = n.compliancequest__SQX_Investigation__r.compliancequest__Status__c;
                    invOfNc.put(n.Id, n.compliancequest__SQX_Investigation__c);
                }
                if (n.compliancequest__SQX_CAPA__c != null) { capaOfNc.put(n.Id, n.compliancequest__SQX_CAPA__c); }
            }
        }
        if (!invOfNc.isEmpty()) {
            Map<Id, List<compliancequest__SQX_Root_Cause__c>> causes = new Map<Id, List<compliancequest__SQX_Root_Cause__c>>();
            for (compliancequest__SQX_Root_Cause__c rc : [
                    SELECT compliancequest__SQX_Investigation__c, compliancequest__Category__c,
                           compliancequest__SQX_Root_Cause_Code__r.Name, compliancequest__Description__c
                    FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c IN :invOfNc.values() WITH USER_MODE ORDER BY CreatedDate]) {
                if (!causes.containsKey(rc.compliancequest__SQX_Investigation__c)) { causes.put(rc.compliancequest__SQX_Investigation__c, new List<compliancequest__SQX_Root_Cause__c>()); }
                causes.get(rc.compliancequest__SQX_Investigation__c).add(rc);
            }
            for (Id ncId2 : invOfNc.keySet()) {
                List<compliancequest__SQX_Root_Cause__c> list1 = causes.get(invOfNc.get(ncId2));
                if (list1 == null || list1.isEmpty()) { continue; }
                compliancequest__SQX_Root_Cause__c rc = list1[0];
                Item it = byId.get(ncId2);
                it.causeHead = rc.compliancequest__Category__c + (rc.compliancequest__SQX_Root_Cause_Code__r == null ? '' : ' · ' + rc.compliancequest__SQX_Root_Cause_Code__r.Name);
                it.causeNote = rc.compliancequest__Description__c;
                it.category = rc.compliancequest__Category__c;
            }
        }
        // CAPAs: the NCs' fixes and the CAPAs in the list, with their latest completed effectiveness review
        Set<Id> allCapas = new Set<Id>(capaIds);
        allCapas.addAll(capaOfNc.values());
        Map<Id, compliancequest__SQX_CAPA__c> capas = new Map<Id, compliancequest__SQX_CAPA__c>();
        Map<Id, compliancequest__SQX_Effectiveness_Review__c> efr = new Map<Id, compliancequest__SQX_Effectiveness_Review__c>();
        if (!allCapas.isEmpty()) {
            capas = new Map<Id, compliancequest__SQX_CAPA__c>([
                SELECT Id, Name, compliancequest__Title__c, compliancequest__Status__c, compliancequest__Closed_Date__c, compliancequest__Issued_Date__c
                FROM compliancequest__SQX_CAPA__c WHERE Id IN :allCapas WITH USER_MODE]);
            for (compliancequest__SQX_Effectiveness_Review__c r : [
                    SELECT Id, Name, compliancequest__SQX_CAPA__c, compliancequest__Resolution__c, compliancequest__Review_Completed_On__c
                    FROM compliancequest__SQX_Effectiveness_Review__c
                    WHERE compliancequest__SQX_CAPA__c IN :allCapas AND compliancequest__Status__c = 'Complete'
                    WITH USER_MODE ORDER BY compliancequest__Review_Completed_On__c DESC NULLS LAST, CreatedDate DESC]) {
                if (!efr.containsKey(r.compliancequest__SQX_CAPA__c)) { efr.put(r.compliancequest__SQX_CAPA__c, r); }
            }
        }
        for (Id ncId2 : capaOfNc.keySet()) { fix(byId.get(ncId2), capas.get(capaOfNc.get(ncId2)), efr); }
        for (Id cId : capaIds) {
            Item it = byId.get(cId);
            compliancequest__SQX_CAPA__c c = capas.get(cId);
            if (c == null) { continue; }
            it.whatHappened = 'CAPA: ' + c.compliancequest__Title__c;
            if (c.compliancequest__Issued_Date__c != null) { it.day = toDate(c.compliancequest__Issued_Date__c); }
            fix(it, c, efr);
        }
        // inspections: which lot, and the result
        if (!insIds.isEmpty()) {
            for (compliancequest__SQX_Inspection__c s : [
                    SELECT Id, compliancequest__Lot_Number__c, compliancequest__Inspection_Result__c FROM compliancequest__SQX_Inspection__c WHERE Id IN :insIds WITH USER_MODE]) {
                Item it = byId.get(s.Id);
                String res = s.compliancequest__Inspection_Result__c;
                it.whatHappened = 'Inspection' + (s.compliancequest__Lot_Number__c == null ? '' : ' of lot ' + s.compliancequest__Lot_Number__c)
                    + (res == null ? '' : (res == 'Fail' ? ' failed' : ': ' + res));
            }
        }

        // hypotheses made from these records
        Map<String, Integer> hyp = new Map<String, Integer>();
        for (Investigation_Hypothesis__c h : invId == null ? new List<Investigation_Hypothesis__c>()
                : [SELECT Number__c, Source_Record_Id__c FROM Investigation_Hypothesis__c WHERE Investigation__c = :invId AND Source_Record_Id__c != null WITH USER_MODE ORDER BY Number__c]) {
            String k = h.Source_Record_Id__c.left(15);
            if (!hyp.containsKey(k) && h.Number__c != null) { hyp.put(k, h.Number__c.intValue()); }
        }

        // keep the PHR order (best first); split by whether they match the problem; find recurrences
        for (PhrQmsPanelController.Row r : rows) {
            Item it = byId.remove(r.id);
            if (it == null) { continue; }
            it.hypothesis = hyp.get(String.valueOf(it.recordId).left(15));
            if (it.problemMatch) {
                v.items.add(it);
                if (isRecurrence(it, v.startDate)) { v.recurrences.add(it); }
            } else {
                v.others.add(it);
            }
        }
        return v;
    }

    /** A closed NC on the same problem, before this one started, whose CAPA was closed: the fix did not hold. */
    @TestVisible
    static Boolean isRecurrence(Item it, Date startDate) {
        if (it.type != PhrQmsRelevance.TYPE_NC || it.capaId == null) { return false; }
        if (it.capaStatus != 'Closed' && it.capaStatus != 'Complete') { return false; }
        if (it.day != null && startDate != null && it.day >= startDate) { return false; }
        return true;
    }

    static void fix(Item it, compliancequest__SQX_CAPA__c c, Map<Id, compliancequest__SQX_Effectiveness_Review__c> efr) {
        if (it == null || c == null) { return; }
        it.capaId = c.Id; it.capaName = c.Name; it.capaTitle = c.compliancequest__Title__c; it.capaStatus = c.compliancequest__Status__c;
        it.capaClosed = toDate(c.compliancequest__Closed_Date__c);
        compliancequest__SQX_Effectiveness_Review__c r = efr.get(c.Id);
        if (r != null) {
            it.efrId = r.Id; it.efrName = r.Name; it.efrResolution = r.compliancequest__Resolution__c; it.efrDate = toDate(r.compliancequest__Review_Completed_On__c);
        }
    }

    static String why(PhrQmsPanelController.Row r, String crit) {
        List<String> bits = new List<String>();
        String rel = r.relatedBy;
        bits.add(rel == PhrQmsRelevance.KIND_COMPONENT ? 'A component' : rel == PhrQmsRelevance.KIND_OTHER ? 'A product sharing a component' : 'Same part');
        if (crit.contains('Lot')) { bits.add('same lot'); }
        if (crit.contains('Symptom')) { bits.add(r.recordType == PhrQmsRelevance.TYPE_INSPECTION ? 'failed inspection' : 'similar problem'); }
        String st = r.status == null ? '' : r.status.toLowerCase();
        if (st == 'open' || st == 'draft' || st == 'in progress') { bits.add('open'); }
        return String.join(bits, ' · ');
    }

    /** The NC's part's bill of materials components, walked down up to five levels. */
    static Set<Id> components(Id partId) {
        Set<Id> out = new Set<Id>();
        if (partId == null) { return out; }
        Set<Id> level = new Set<Id>{ partId };
        for (Integer depth = 0; depth < 5 && !level.isEmpty(); depth++) {
            Set<Id> next = new Set<Id>();
            for (cqext__CQPLM_Assembly_line_Item__c li : [
                    SELECT cqext__CQPLM_Part__c FROM cqext__CQPLM_Assembly_line_Item__c
                    WHERE cqext__CQPLM_Assembly__r.cqext__CQPLM_Part_Revision__r.cqext__CQPLM_Part__c IN :level AND cqext__CQPLM_Part__c != null WITH USER_MODE]) {
                if (li.cqext__CQPLM_Part__c != partId && !out.contains(li.cqext__CQPLM_Part__c)) { next.add(li.cqext__CQPLM_Part__c); }
            }
            out.addAll(next);
            level = next;
        }
        return out;
    }

    /** Marks a record Not Relevant for this investigation. */
    @AuraEnabled
    public static void markNotRelevant(Id recordId, Id targetId, String targetName, String reason) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        if (targetId == null) { throw new AuraHandledException('No record to mark.'); }
        try {
            insert as user new Investigation_Not_Relevant__c(Investigation__c = invId, Record_Id__c = targetId, Record_Name__c = targetName == null ? null : targetName.left(80),
                Reason__c = reason == null ? null : reason.left(255));
        } catch (DmlException e) { throw new AuraHandledException('It was not saved: ' + e.getDmlMessage(0)); }
    }

    /** Puts a record marked Not Relevant back on the list. */
    @AuraEnabled
    public static void restore(Id dismissedId) {
        try {
            delete as user [SELECT Id FROM Investigation_Not_Relevant__c WHERE Id = :dismissedId WITH USER_MODE];
        } catch (DmlException e) { throw new AuraHandledException('It was not restored: ' + e.getDmlMessage(0)); }
    }

    static String joinText(String title, String descr) {
        String d = descr == null ? '' : descr.removeStartIgnoreCase('SAMPLE DATA. ').trim();
        if (String.isBlank(title)) { return d.abbreviate(220); }
        return String.isBlank(d) ? title : (title + ': ' + d).abbreviate(220);
    }
    static Date toDate(Object o) {
        if (o == null) { return null; }
        if (o instanceof Datetime) { return ((Datetime) o).dateGmt(); }
        return (Date) o;
    }
}

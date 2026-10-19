/**
 * PhrQmsRelevance
 * ---------------
 * Relevance model for the PHR QMS Records panel and the agent action.
 * Finds Nonconformances, CAPAs, Change Orders and Inspections linked to a
 * Complaint, scores each one and sorts the result into leads and set-aside.
 *
 * The aim is to point the investigator at things worth reviewing. A record is
 * relevant if it is worth a look, whether or not it caused the complaint.
 *
 * Three criteria, each met or not:
 *   Product link  own part, a BOM component, or another product that shares a
 *                 component (where-used). Document-only change orders carry
 *                 almost no weight.
 *   Symptom       text similarity of title and description to the complaint,
 *                 a matching defect code, a failed inspection, or a part or
 *                 design change made shortly before the occurrence date.
 *   Current       the record is open, recent, or both.
 * Colour comes from how many criteria are met: three = Red, two = Yellow,
 * one = Grey. A 0 to 100 score shows how strongly they matched. Ranking is by
 * colour, then score, then recency.
 *
 * A record needs two criteria to be a lead. Records on a component or another
 * product also need the symptom criterion. A record in the complaint's lot is
 * always a lead. Everything else is set aside, with a reason.
 *
 * The result is written into the same lists PhrQmsPanelController already
 * returns (best first), so the panel and the agent action keep working. Set
 * aside records go into PanelData.setAside only. All weights are placeholders
 * held in PhrQmsRelevanceSettings.
 */
public with sharing class PhrQmsRelevance {

    public static final String KIND_OWN = 'Own part';
    public static final String KIND_COMPONENT = 'Component of the part';
    public static final String KIND_OTHER = 'Product sharing a component';
    public static final String KIND_LOT = 'Same lot';

    public static final String CLASS_PART_DESIGN = 'Part or design change';
    public static final String CLASS_DOCUMENT = 'Document change only';
    public static final String CLASS_UNCLASSIFIED = 'Unclassified';

    public static final String TYPE_NC = 'Nonconformance';
    public static final String TYPE_CAPA = 'CAPA';
    public static final String TYPE_CO = 'Change Order';
    public static final String TYPE_INSPECTION = 'Inspection';

    private static final Set<String> CLOSED_STATUSES = new Set<String>{
        'closed', 'complete', 'completed', 'cancelled', 'canceled', 'void', 'voided', 'rejected', 'obsolete'
    };
    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'and', 'for', 'with', 'from', 'that', 'this', 'was', 'were', 'has', 'have', 'had', 'not',
        'are', 'but', 'its', 'into', 'during', 'after', 'before', 'when', 'than', 'then', 'been', 'being',
        'also', 'which', 'their', 'there', 'they', 'them', 'while', 'would', 'could', 'should', 'about'
    };

    /** Tests set a change order class directly instead of building the related records. */
    @TestVisible private static Map<Id, String> changeClassOverride = new Map<Id, String>();

    /** What the panel controller knows about the complaint and what is already added. */
    public class Input {
        public Id ownPartId;
        public Set<Id> componentIds = new Set<Id>();
        public Set<String> lots = new Set<String>();
        public String symptomText;
        public Id complaintCodeId;
        public Date occurrenceDate;
        /** Manufactured date of the complaint's Lot Info record; used by the optional date window. */
        public Date manufactureDate;
        public Set<Id> addedNc = new Set<Id>();
        public Set<Id> addedCapa = new Set<Id>();
        public Set<String> addedRefs = new Set<String>();
    }

    private class Run {
        Input inp;
        Set<Id> comps;
        Set<String> lots;
        Map<Id, Integer> others;
        Set<Id> allParts;
        Set<String> symptom;
        Datetime nowTs;
        Datetime winStart;
        Datetime winEnd;
    }

    private class Cand {
        PhrQmsPanelController.Row row = new PhrQmsPanelController.Row();
        String type;
        String kind;
        String text;
        Id codeId;
        Boolean lotHit = false;
        Boolean isOpenRec = false;
        Boolean isNew = false;
        String changeClass;
        Boolean changeBefore = false;
        Boolean changeAfter = false;
        Boolean failedInspection = false;
        Boolean linkMet = false;
        Boolean symptomMet = false;
        Boolean currentMet = false;
        Integer relevance = 0;
        Integer criteria = 0;
        Boolean keep = false;
    }

    private class ProductCount implements Comparable {
        Id partId;
        Integer shared;
        public Integer compareTo(Object other) {
            ProductCount o = (ProductCount) other;
            if (shared != o.shared) { return shared > o.shared ? -1 : 1; }
            return String.valueOf(partId).compareTo(String.valueOf(o.partId));
        }
    }

    // ---------- Entry point ----------

    /**
     * Replaces the nonconformance, CAPA, change order and inspection lists on
     * the PanelData with the ranked leads and fills setAside. Investigations
     * are not touched.
     */
    public static void populate(Input inp, PhrQmsPanelController.PanelData d) {
        Run run = new Run();
        run.inp = inp;
        run.comps = inp.componentIds == null ? new Set<Id>() : inp.componentIds;
        run.lots = inp.lots == null ? new Set<String>() : inp.lots;
        run.others = otherProducts(inp.ownPartId, run.comps);
        run.allParts = new Set<Id>(run.comps);
        run.allParts.addAll(run.others.keySet());
        if (inp.ownPartId != null) { run.allParts.add(inp.ownPartId); }
        run.symptom = tokens(inp.symptomText);
        run.nowTs = Datetime.now();
        PhrReportSettings.Values win = PhrReportSettings.get();
        run.winStart = PhrReportSettings.windowStart(win, inp.manufactureDate);
        run.winEnd = PhrReportSettings.windowEnd(win, inp.manufactureDate);

        List<Cand> cands = new List<Cand>();
        cands.addAll(loadNcs(run));
        cands.addAll(loadCapas(run));
        cands.addAll(loadChangeOrders(run));
        cands.addAll(loadInspections(run));

        d.nonconformances = new List<PhrQmsPanelController.Row>();
        d.capas = new List<PhrQmsPanelController.Row>();
        d.changeOrders = new List<PhrQmsPanelController.Row>();
        d.inspections = new List<PhrQmsPanelController.Row>();
        d.setAside = new List<PhrQmsPanelController.Row>();
        List<PhrQmsPanelController.Row> leads = new List<PhrQmsPanelController.Row>();

        for (Cand c : cands) {
            score(c, run);
            if (!c.keep) {
                c.row.tier = 'Set aside';
                d.setAside.add(c.row);
                continue;
            }
            leads.add(c.row);
            if (c.type == TYPE_NC) { d.nonconformances.add(c.row); }
            else if (c.type == TYPE_CAPA) { d.capas.add(c.row); }
            else if (c.type == TYPE_CO) { d.changeOrders.add(c.row); }
            else { d.inspections.add(c.row); }
        }

        leads.sort();
        Integer i = 0;
        for (PhrQmsPanelController.Row r : leads) {
            r.tier = i < PhrQmsRelevanceSettings.TOP_LEADS ? 'Top' : 'Next';
            r.highlight = r.tier == 'Top';
            i++;
        }
        d.nonconformances.sort();
        d.capas.sort();
        d.changeOrders.sort();
        d.inspections.sort();
        d.setAside.sort();
        d.relevanceModel = 'v2';
    }

    // ---------- Scoring ----------

    private static void score(Cand c, Run run) {
        // Product link
        Integer link = 0;
        if (c.kind == KIND_OWN) { link = PhrQmsRelevanceSettings.PTS_LINK_OWN; }
        else if (c.kind == KIND_COMPONENT || c.kind == KIND_LOT) { link = PhrQmsRelevanceSettings.PTS_LINK_COMPONENT; }
        else if (c.kind == KIND_OTHER) { link = PhrQmsRelevanceSettings.PTS_LINK_OTHER; }
        c.linkMet = c.kind != null;
        if (c.type == TYPE_CO) {
            if (c.changeClass == CLASS_DOCUMENT) {
                link = Math.round(link * PhrQmsRelevanceSettings.DOCUMENT_ONLY_LINK_FACTOR);
                c.linkMet = false;
            } else if (c.changeClass == CLASS_UNCLASSIFIED) {
                link = Math.round(link * PhrQmsRelevanceSettings.UNCLASSIFIED_LINK_FACTOR);
            }
        }

        // Symptom
        Integer sym = 0;
        Double sim = dice(run.symptom, tokens(c.text));
        if (sim >= PhrQmsRelevanceSettings.SYMPTOM_THRESHOLD) {
            c.symptomMet = true;
            sym = Math.round(PhrQmsRelevanceSettings.PTS_SYMPTOM_MAX * Math.min(1.0, sim / PhrQmsRelevanceSettings.SYMPTOM_FULL));
        }
        if (run.inp.complaintCodeId != null && c.codeId != null && c.codeId == run.inp.complaintCodeId) {
            c.symptomMet = true;
            sym = Math.max(sym, PhrQmsRelevanceSettings.PTS_SYMPTOM_CODE);
        }
        if (c.failedInspection) {
            c.symptomMet = true;
            sym = Math.max(sym, PhrQmsRelevanceSettings.PTS_SYMPTOM_FAILED_INSPECTION);
        }
        if (c.type == TYPE_CO && c.changeClass == CLASS_PART_DESIGN && c.changeBefore) {
            c.symptomMet = true;
            sym = Math.max(sym, PhrQmsRelevanceSettings.PTS_SYMPTOM_CHANGE_BEFORE);
        }

        // Current
        Integer cur = 0;
        if (c.isOpenRec && c.isNew) { cur = PhrQmsRelevanceSettings.PTS_CURRENT_BOTH; }
        else if (c.isOpenRec || c.isNew) { cur = PhrQmsRelevanceSettings.PTS_CURRENT_ONE; }
        c.currentMet = cur > 0;

        // Bonuses
        Integer bonus = 0;
        if (c.lotHit) { bonus += PhrQmsRelevanceSettings.PTS_LOT; c.linkMet = true; }
        if (c.type == TYPE_CO && c.changeClass == CLASS_PART_DESIGN) {
            bonus += PhrQmsRelevanceSettings.PTS_PART_DESIGN_CHANGE;
            if (c.changeBefore) { bonus += PhrQmsRelevanceSettings.PTS_CHANGE_BEFORE_COMPLAINT; }
        }

        c.relevance = Math.min(100, link + sym + cur + bonus);
        c.criteria = (c.linkMet ? 1 : 0) + (c.symptomMet ? 1 : 0) + (c.currentMet ? 1 : 0);
        if (c.lotHit && c.criteria < 2) { c.criteria = 2; }

        // Keep or set aside
        String reason = null;
        if (c.lotHit) {
            c.keep = true;
        } else if (c.kind == null) {
            reason = 'No link to the complaint part or lot';
        } else if (c.type == TYPE_CO && c.changeClass == CLASS_DOCUMENT && c.criteria < 2) {
            reason = 'Document change only';
        } else if (c.kind != KIND_OWN && !c.symptomMet) {
            reason = 'No matching symptom on a related part or product';
        } else if (c.criteria < 2) {
            reason = 'Matched only one criterion';
        } else {
            c.keep = true;
        }

        // Output row
        PhrQmsPanelController.Row r = c.row;
        r.isNew = c.isNew;
        r.colour = c.criteria >= 3 ? 'Red' : (c.criteria == 2 ? 'Yellow' : 'Grey');
        r.relevance = c.relevance;
        r.score = (c.criteria >= 3 ? 3000 : (c.criteria == 2 ? 2000 : 1000)) + c.relevance;
        r.relatedBy = c.kind;
        r.recordType = c.type;
        r.reason = reason;
        List<String> met = new List<String>();
        if (c.linkMet) { met.add('Product'); }
        if (c.symptomMet) { met.add('Symptom'); }
        if (c.currentMet) { met.add('Current'); }
        if (c.lotHit) { met.add('Lot'); }
        r.criteriaMet = String.join(met, ', ');
        Boolean partHit = c.kind == KIND_OWN || c.kind == KIND_COMPONENT || c.kind == KIND_OTHER;
        r.matchedBy = partHit && c.lotHit ? 'Part and Lot' : (c.lotHit ? 'Lot' : (partHit ? 'Part' : null));
        if (c.type == TYPE_CO) {
            r.changeType = c.changeClass
                + (c.changeBefore ? ' (before the complaint)' : (c.changeAfter ? ' (after the complaint)' : ''));
        }
    }

    // ---------- Loading ----------

    private static List<Cand> loadNcs(Run run) {
        List<Cand> out = new List<Cand>();
        Set<Id> parts = run.allParts;
        Set<String> lots = run.lots;
        Integer maxRows = PhrQmsRelevanceSettings.MAX_ROWS;
        Datetime winStart = run.winStart;
        Datetime winEnd = run.winEnd;
        for (compliancequest__SQX_Nonconformance__c nc : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__Lot_Number__c,
                   compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                   compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__SQX_Defect_Code__c
            FROM compliancequest__SQX_Nonconformance__c
            WHERE (compliancequest__SQX_Part__c IN :parts OR compliancequest__Lot_Number__c IN :lots)
            AND CreatedDate >= :winStart AND CreatedDate < :winEnd
            ORDER BY CreatedDate DESC LIMIT :maxRows
        ]) {
            Cand c = newCand(run, TYPE_NC, nc.Id, nc.Name, nc.CreatedDate, nc.compliancequest__Status__c,
                nc.compliancequest__SQX_Part__c,
                nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                nc.compliancequest__Lot_Number__c,
                join(nc.compliancequest__NC_Title__c, nc.compliancequest__Description__c));
            c.codeId = nc.compliancequest__SQX_Defect_Code__c;
            c.row.alreadyAdded = run.inp.addedNc != null && run.inp.addedNc.contains(nc.Id);
            out.add(c);
        }
        return out;
    }

    private static List<Cand> loadCapas(Run run) {
        List<Cand> out = new List<Cand>();
        Set<Id> parts = run.allParts;
        if (parts.isEmpty()) { return out; }
        Integer maxRows = PhrQmsRelevanceSettings.MAX_ROWS;
        Datetime winStart = run.winStart;
        Datetime winEnd = run.winEnd;
        for (compliancequest__SQX_CAPA__c capa : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                   compliancequest__Title__c, compliancequest__Description__c
            FROM compliancequest__SQX_CAPA__c
            WHERE compliancequest__SQX_Part__c IN :parts
            AND CreatedDate >= :winStart AND CreatedDate < :winEnd
            ORDER BY CreatedDate DESC LIMIT :maxRows
        ]) {
            Cand c = newCand(run, TYPE_CAPA, capa.Id, capa.Name, capa.CreatedDate, capa.compliancequest__Status__c,
                capa.compliancequest__SQX_Part__c,
                capa.compliancequest__SQX_Part__r == null ? null : capa.compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                null,
                join(capa.compliancequest__Title__c, capa.compliancequest__Description__c));
            c.row.alreadyAdded = run.inp.addedCapa != null && run.inp.addedCapa.contains(capa.Id);
            out.add(c);
        }
        return out;
    }

    private static List<Cand> loadChangeOrders(Run run) {
        List<Cand> out = new List<Cand>();
        Set<Id> parts = run.allParts;
        if (parts.isEmpty()) { return out; }
        Integer maxRows = PhrQmsRelevanceSettings.MAX_ROWS;
        Datetime winStart = run.winStart;
        Datetime winEnd = run.winEnd;
        List<compliancequest__SQX_Change_Order__c> cos = [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__SQX_Product__c,
                   compliancequest__SQX_Product__r.compliancequest__Part_Number__c,
                   compliancequest__Title__c, compliancequest__Description__c, compliancequest__Justification__c,
                   compliancequest__Submitted_Date__c, compliancequest__Effective_Date__c
            FROM compliancequest__SQX_Change_Order__c
            WHERE compliancequest__SQX_Product__c IN :parts
            AND CreatedDate >= :winStart AND CreatedDate < :winEnd
            ORDER BY CreatedDate DESC LIMIT :maxRows
        ];
        if (cos.isEmpty()) { return out; }
        Set<Id> coIds = new Map<Id, compliancequest__SQX_Change_Order__c>(cos).keySet();
        Set<Id> partDesign = linkedChangeOrders('cqext__CQPLM_Part_Change__c', new List<String>{ 'cqext__CQPLM_Change_Order__c' }, coIds);
        partDesign.addAll(linkedChangeOrders('cqext__SQX_Product_Design_Change_Order__c',
            new List<String>{ 'cqext__SQX_Change_Order__c', 'compliancequest__SQX_Change_Order__c' }, coIds));
        Set<Id> documents = linkedChangeOrders('compliancequest__SQX_Document_Change__c',
            new List<String>{ 'compliancequest__SQX_Change_Order__c' }, coIds);

        for (compliancequest__SQX_Change_Order__c co : cos) {
            Cand c = newCand(run, TYPE_CO, co.Id, co.Name, co.CreatedDate, co.compliancequest__Status__c,
                co.compliancequest__SQX_Product__c,
                co.compliancequest__SQX_Product__r == null ? null : co.compliancequest__SQX_Product__r.compliancequest__Part_Number__c,
                null,
                join(co.compliancequest__Title__c, join(co.compliancequest__Description__c, co.compliancequest__Justification__c)));
            c.row.alreadyAdded = run.inp.addedRefs != null && run.inp.addedRefs.contains(refKey('Change Order', co.Name));
            c.changeClass = partDesign.contains(co.Id) ? CLASS_PART_DESIGN
                : (documents.contains(co.Id) ? CLASS_DOCUMENT : CLASS_UNCLASSIFIED);
            if (changeClassOverride.containsKey(co.Id)) { c.changeClass = changeClassOverride.get(co.Id); }
            Date changeDate = toDate(co.get('compliancequest__Effective_Date__c'));
            if (changeDate == null) { changeDate = toDate(co.get('compliancequest__Submitted_Date__c')); }
            Date occurred = run.inp.occurrenceDate;
            if (changeDate != null && occurred != null) {
                Integer days = changeDate.daysBetween(occurred);
                if (days >= 0 && days <= PhrQmsRelevanceSettings.CHANGE_WINDOW_DAYS) { c.changeBefore = true; }
                else if (days < 0) { c.changeAfter = true; }
            }
            out.add(c);
        }
        return out;
    }

    private static List<Cand> loadInspections(Run run) {
        List<Cand> out = new List<Cand>();
        Set<Id> parts = run.allParts;
        Set<String> lots = run.lots;
        Integer maxRows = PhrQmsRelevanceSettings.MAX_ROWS;
        Datetime winStart = run.winStart;
        Datetime winEnd = run.winEnd;
        for (compliancequest__SQX_Inspection__c insp : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__Lot_Number__c,
                   compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                   compliancequest__Inspection_Result__c
            FROM compliancequest__SQX_Inspection__c
            WHERE (compliancequest__SQX_Part__c IN :parts OR compliancequest__Lot_Number__c IN :lots)
            AND CreatedDate >= :winStart AND CreatedDate < :winEnd
            ORDER BY CreatedDate DESC LIMIT :maxRows
        ]) {
            Cand c = newCand(run, TYPE_INSPECTION, insp.Id, insp.Name, insp.CreatedDate, insp.compliancequest__Status__c,
                insp.compliancequest__SQX_Part__c,
                insp.compliancequest__SQX_Part__r == null ? null : insp.compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                insp.compliancequest__Lot_Number__c, null);
            String result = insp.compliancequest__Inspection_Result__c;
            c.failedInspection = result != null && result.toLowerCase().contains('fail');
            c.row.alreadyAdded = run.inp.addedRefs != null && run.inp.addedRefs.contains(refKey('Inspection', insp.Name));
            out.add(c);
        }
        return out;
    }

    private static Cand newCand(
        Run run, String type, Id id, String name, Datetime created, String status,
        Id partId, String partNumber, String lot, String text
    ) {
        Cand c = new Cand();
        c.type = type;
        c.text = text;
        c.lotHit = lotHit(run.lots, lot);
        if (partId != null && partId == run.inp.ownPartId) { c.kind = KIND_OWN; }
        else if (partId != null && run.comps.contains(partId)) { c.kind = KIND_COMPONENT; }
        else if (partId != null && run.others.containsKey(partId)) { c.kind = KIND_OTHER; }
        else if (c.lotHit) { c.kind = KIND_LOT; }
        c.isOpenRec = isOpen(status);
        c.isNew = created != null && created >= run.nowTs.addDays(-PhrQmsRelevanceSettings.NEW_WINDOW_DAYS);
        PhrQmsPanelController.Row r = c.row;
        r.id = id;
        r.name = name;
        r.createdDate = created;
        r.status = status;
        r.partNumber = partNumber;
        return c;
    }

    /** Change Order Ids that have at least one record in the given object, trying each link field. Never throws. */
    private static Set<Id> linkedChangeOrders(String objectName, List<String> linkFields, Set<Id> coIds) {
        Set<Id> found = new Set<Id>();
        if (coIds == null || coIds.isEmpty()) { return found; }
        for (String field : linkFields) {
            try {
                for (SObject so : Database.query('SELECT ' + field + ' FROM ' + objectName + ' WHERE ' + field + ' IN :coIds')) {
                    Object v = so.get(field);
                    if (v != null) { found.add((Id) v); }
                }
            } catch (Exception ex) {
                // The object or field is not in this org; treat as no records.
            }
        }
        return found;
    }

    // ---------- Where-used: other products sharing a component ----------

    /** Other products that use any of the complaint part's components, most shared components first, capped. */
    @TestVisible
    private static Map<Id, Integer> otherProducts(Id ownPartId, Set<Id> comps) {
        Map<Id, Integer> result = new Map<Id, Integer>();
        if (comps == null || comps.isEmpty()) { return result; }

        Map<Id, Set<Id>> compsByAssembly = new Map<Id, Set<Id>>();
        for (cqext__CQPLM_Assembly_line_Item__c li : [
            SELECT cqext__CQPLM_Assembly__c, cqext__CQPLM_Part__c
            FROM cqext__CQPLM_Assembly_line_Item__c
            WHERE cqext__CQPLM_Part__c IN :comps AND cqext__CQPLM_Assembly__c != null
            LIMIT 2000
        ]) {
            if (!compsByAssembly.containsKey(li.cqext__CQPLM_Assembly__c)) {
                compsByAssembly.put(li.cqext__CQPLM_Assembly__c, new Set<Id>());
            }
            compsByAssembly.get(li.cqext__CQPLM_Assembly__c).add(li.cqext__CQPLM_Part__c);
        }
        if (compsByAssembly.isEmpty()) { return result; }

        Set<Id> assemblyIds = compsByAssembly.keySet();
        Map<Id, Set<Id>> compsByRevision = new Map<Id, Set<Id>>();
        for (cqext__CQPLM_Assembly__c a : [
            SELECT Id, cqext__CQPLM_Part_Revision__c FROM cqext__CQPLM_Assembly__c
            WHERE Id IN :assemblyIds AND cqext__CQPLM_Part_Revision__c != null
        ]) {
            if (!compsByRevision.containsKey(a.cqext__CQPLM_Part_Revision__c)) {
                compsByRevision.put(a.cqext__CQPLM_Part_Revision__c, new Set<Id>());
            }
            compsByRevision.get(a.cqext__CQPLM_Part_Revision__c).addAll(compsByAssembly.get(a.Id));
        }
        if (compsByRevision.isEmpty()) { return result; }

        Set<Id> revisionIds = compsByRevision.keySet();
        Map<Id, Set<Id>> compsByProduct = new Map<Id, Set<Id>>();
        for (cqext__CQPLM_Part_Revision__c rev : [
            SELECT Id, cqext__CQPLM_Part__c FROM cqext__CQPLM_Part_Revision__c
            WHERE Id IN :revisionIds AND cqext__CQPLM_Part__c != null
        ]) {
            Id product = rev.cqext__CQPLM_Part__c;
            if (product == ownPartId || comps.contains(product)) { continue; }
            if (!compsByProduct.containsKey(product)) { compsByProduct.put(product, new Set<Id>()); }
            compsByProduct.get(product).addAll(compsByRevision.get(rev.Id));
        }

        List<ProductCount> counts = new List<ProductCount>();
        for (Id product : compsByProduct.keySet()) {
            ProductCount pc = new ProductCount();
            pc.partId = product;
            pc.shared = compsByProduct.get(product).size();
            counts.add(pc);
        }
        counts.sort();
        for (ProductCount pc : counts) {
            if (result.size() >= PhrQmsRelevanceSettings.OTHER_PRODUCT_CAP) { break; }
            result.put(pc.partId, pc.shared);
        }
        return result;
    }

    // ---------- Text and small helpers ----------

    @TestVisible
    private static Set<String> tokens(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) { return out; }
        for (String t : text.toLowerCase().replaceAll('[^a-z0-9]+', ' ').split(' ')) {
            if (t.length() < 3 || STOP_WORDS.contains(t) || t.isNumeric()) { continue; }
            out.add(t.length() > 4 && t.endsWith('s') ? t.substring(0, t.length() - 1) : t);
        }
        return out;
    }

    /** Dice coefficient of two token sets, 0 to 1. */
    @TestVisible
    private static Double dice(Set<String> a, Set<String> b) {
        if (a == null || b == null || a.isEmpty() || b.isEmpty()) { return 0.0; }
        Integer shared = 0;
        for (String t : a) {
            if (b.contains(t)) { shared++; }
        }
        return (2.0 * shared) / (a.size() + b.size());
    }

    private static String join(String a, String b) {
        return (a == null ? '' : a) + ' ' + (b == null ? '' : b);
    }

    private static Boolean isOpen(String status) {
        return String.isBlank(status) || !CLOSED_STATUSES.contains(status.trim().toLowerCase());
    }

    private static Boolean lotHit(Set<String> lots, String value) {
        if (String.isBlank(value) || lots == null) { return false; }
        for (String l : lots) {
            if (l.equalsIgnoreCase(value.trim())) { return true; }
        }
        return false;
    }

    private static String refKey(String refType, String refNumber) {
        return (refType + '|' + refNumber).toLowerCase();
    }

    private static Date toDate(Object value) {
        if (value instanceof Date) { return (Date) value; }
        if (value instanceof Datetime) { return ((Datetime) value).date(); }
        return null;
    }
}

/**
 * PhrQmsPanelController
 * -----------------------
 * Standalone Apex behind the "PHR QMS Records" panel (phrQmsRecordsPanel LWC)
 * and the agent action PhrQmsRelatedRecordsAction.
 *
 * It does NOT call or share code with AssociatedItemsReportAction; the
 * matching logic below is an independent implementation of the same idea:
 *
 *   Complaint Part -> Part Revision -> Assembly -> Assembly Line Items
 *   (so records filed against assembly components are found too), plus
 *   records carrying the Complaint's Lot Number.
 *
 * Differences from the older class:
 *   - Lot matching is trimmed and also reads the Complaint's Lot Info lookup,
 *     not only the free-text Lot Number field.
 *   - A Lot Number can be supplied by the caller (panel search box).
 *   - Matching records can be written back: Related Product rows on the
 *     Product History Review (NC and CAPA as lookups, Change Order and
 *     Inspection as a reference type plus number). Investigations are not
 *     linked to the Complaint.
 *   - Records already on the PHR / Complaint are flagged and never duplicated.
 *
 * Assembly Line Items are used only to FIND records. They are never written
 * as Associated Items (the managed package auto-expands those).
 */
public with sharing class PhrQmsPanelController {

    public static final String PHR_OBJECT = 'compliancequest__SQX_Product_History_Review__c';
    public static final String COMPLAINT_OBJECT = 'compliancequest__SQX_Complaint__c';
    public static final String TAG = 'Added by PHR QMS Records panel';
    private static final Integer MAX_ROWS = 200;
    /** Records created within this many days get the "New" flag and a score boost. */
    @TestVisible private static final Integer NEW_WINDOW_DAYS = 30;
    /** At most this many rows per section are highlighted. */
    @TestVisible private static final Integer MAX_HIGHLIGHTS = 3;
    private static final Set<String> CLOSED_STATUSES = new Set<String>{
        'closed', 'complete', 'completed', 'cancelled', 'canceled', 'void', 'voided', 'rejected', 'obsolete'
    };

    public class PhrQmsException extends Exception {}

    // ---------- Result types ----------

    public class Row implements Comparable {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String status;
        @AuraEnabled public String matchedBy;
        @AuraEnabled public Boolean alreadyAdded = false;
        @AuraEnabled public Datetime createdDate;
        @AuraEnabled public Boolean isNew = false;
        @AuraEnabled public Boolean highlight = false;
        @AuraEnabled public Integer score = 0;
        // Added by the relevance model (PhrQmsRelevance). Null when the original ranking is used.
        @AuraEnabled public String colour;
        @AuraEnabled public Integer relevance;
        @AuraEnabled public String criteriaMet;
        @AuraEnabled public String tier;
        @AuraEnabled public String relatedBy;
        @AuraEnabled public String recordType;
        @AuraEnabled public String changeType;
        @AuraEnabled public String reason;

        /** Highest score first; newest first within the same score; then by name. */
        public Integer compareTo(Object other) {
            Row o = (Row) other;
            if (score != o.score) { return score > o.score ? -1 : 1; }
            if (createdDate != o.createdDate) {
                if (createdDate == null) { return 1; }
                if (o.createdDate == null) { return -1; }
                return createdDate > o.createdDate ? -1 : 1;
            }
            String a = name == null ? '' : name;
            String b = o.name == null ? '' : o.name;
            return a.compareTo(b);
        }
    }

    public class PanelData {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String errorMessage;
        @AuraEnabled public Id phrId;
        @AuraEnabled public Id complaintId;
        @AuraEnabled public String complaintName;
        @AuraEnabled public String partName;
        @AuraEnabled public String partNumber;
        @AuraEnabled public String lotNumber;
        @AuraEnabled public Integer componentPartCount = 0;
        @AuraEnabled public List<Row> nonconformances = new List<Row>();
        @AuraEnabled public List<Row> capas = new List<Row>();
        @AuraEnabled public List<Row> changeOrders = new List<Row>();
        @AuraEnabled public List<Row> inspections = new List<Row>();
        @AuraEnabled public List<Row> investigations = new List<Row>();
        /** Records the relevance model set aside, each with a reason. Empty with the original ranking. */
        @AuraEnabled public List<Row> setAside = new List<Row>();
        @AuraEnabled public String relevanceModel;
        /** Plain-language note about the optional manufacture date window; blank when the window is off. */
        @AuraEnabled public String windowNote;
    }

    public class CreateResult {
        @AuraEnabled public Boolean success = true;
        @AuraEnabled public String message;
        @AuraEnabled public Integer relatedProductsCreated = 0;
        @AuraEnabled public Integer linkedInvestigationsCreated = 0;
        @AuraEnabled public Integer skipped = 0;
        @AuraEnabled public List<String> errors = new List<String>();
    }

    private class Ctx {
        Id phrId;
        Id complaintId;
        String complaintName;
        Id partId;
        Set<String> lots = new Set<String>();
        String lotLabel;
        String symptomText;
        Id complaintCodeId;
        Date occurrenceDate;
        Date manufactureDate;
        Boolean lotOverridden = false;
    }

    // ---------- Panel: read ----------

    /**
     * recordId is a Product History Review or a Complaint. lotOverride, when
     * not blank, replaces the Complaint's own lot for the search.
     */
    @AuraEnabled
    public static PanelData getPanelData(Id recordId, String lotOverride) {
        PanelData d = new PanelData();
        try {
            Ctx c = resolve(recordId, lotOverride);
            d.phrId = c.phrId;
            d.complaintId = c.complaintId;
            d.complaintName = c.complaintName;
            d.lotNumber = c.lotLabel;

            Set<Id> partIds = new Set<Id>();
            if (c.partId != null) {
                partIds.add(c.partId);
                compliancequest__SQX_Part__c p = [
                    SELECT Name, compliancequest__Part_Number__c
                    FROM compliancequest__SQX_Part__c WHERE Id = :c.partId LIMIT 1
                ];
                d.partName = p.Name;
                d.partNumber = p.compliancequest__Part_Number__c;
                Integer before = partIds.size();
                partIds.addAll(componentPartIds(c.partId));
                d.componentPartCount = partIds.size() - before;
            }

            Set<Id> addedNc = new Set<Id>();
            Set<Id> addedCapa = new Set<Id>();
            Set<String> addedRefs = new Set<String>();
            Set<Id> addedInv = new Set<Id>();
            loadExisting(c, addedNc, addedCapa, addedRefs, addedInv);

            if (!partIds.isEmpty() || !c.lots.isEmpty()) {
                if (PhrQmsRelevanceSettings.useNewModel) {
                    // Relevance model: leads (best first) in the usual lists, set-aside separately.
                    PhrQmsRelevance.Input inp = new PhrQmsRelevance.Input();
                    inp.ownPartId = c.partId;
                    inp.componentIds = new Set<Id>(partIds);
                    if (c.partId != null) { inp.componentIds.remove(c.partId); }
                    inp.lots = c.lots;
                    inp.symptomText = c.symptomText;
                    inp.complaintCodeId = c.complaintCodeId;
                    inp.occurrenceDate = c.occurrenceDate;
                    inp.manufactureDate = c.manufactureDate;
                    d.windowNote = windowNote(c);
                    inp.addedNc = addedNc;
                    inp.addedCapa = addedCapa;
                    inp.addedRefs = addedRefs;
                    PhrQmsRelevance.populate(inp, d);
                    findInvestigations(c, partIds, addedInv, d);
                    rank(d.investigations);
                } else {
                    // Original ranking (kept as the fallback).
                    findNonconformances(partIds, c.lots, addedNc, d);
                    findCapas(partIds, addedCapa, d);
                    findChangeOrders(partIds, addedRefs, d);
                    findInspections(partIds, c.lots, addedRefs, d);
                    findInvestigations(c, partIds, addedInv, d);
                    rank(d.nonconformances);
                    rank(d.capas);
                    rank(d.changeOrders);
                    rank(d.inspections);
                    rank(d.investigations);
                }
            }
        } catch (Exception ex) {
            d.success = false;
            d.errorMessage = ex.getMessage();
        }
        return d;
    }

    // ---------- Panel: write ----------

    /**
     * Creates Related Product rows on the PHR for the selected record Ids. Records already present
     * are skipped. Each list may be null or empty.
     * Investigations are no longer added to the Complaint's Linked Investigations: investigationIds is
     * accepted for compatibility and ignored (the investigation is still stored as a PHR Lead by the caller).
     */
    @AuraEnabled
    public static CreateResult createRelatedRecords(
        Id recordId,
        List<Id> ncIds,
        List<Id> capaIds,
        List<Id> changeOrderIds,
        List<Id> inspectionIds,
        List<Id> investigationIds
    ) {
        CreateResult r = new CreateResult();
        try {
            Ctx c = resolve(recordId, null);
            Set<Id> addedNc = new Set<Id>();
            Set<Id> addedCapa = new Set<Id>();
            Set<String> addedRefs = new Set<String>();
            Set<Id> addedInv = new Set<Id>();
            loadExisting(c, addedNc, addedCapa, addedRefs, addedInv);

            List<compliancequest__SQX_Related_Product__c> rps = new List<compliancequest__SQX_Related_Product__c>();
            Boolean wantsQms = hasAny(ncIds) || hasAny(capaIds) || hasAny(changeOrderIds) || hasAny(inspectionIds);
            if (wantsQms && c.phrId == null) {
                throw new PhrQmsException('This Complaint has no Product History Review yet, so QMS records cannot be added.');
            }

            if (hasAny(ncIds)) {
                for (compliancequest__SQX_Nonconformance__c nc : [
                    SELECT Id, compliancequest__SQX_Part__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :ncIds
                ]) {
                    if (addedNc.contains(nc.Id)) { r.skipped++; continue; }
                    rps.add(new compliancequest__SQX_Related_Product__c(
                        compliancequest__SQX_Product_History_Review__c = c.phrId,
                        compliancequest__SQX_Nonconformance__c = nc.Id,
                        compliancequest__SQX_Product_Component__c = nc.compliancequest__SQX_Part__c,
                        compliancequest__Comment__c = TAG));
                }
            }
            if (hasAny(capaIds)) {
                for (compliancequest__SQX_CAPA__c capa : [
                    SELECT Id, compliancequest__SQX_Part__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capaIds
                ]) {
                    if (addedCapa.contains(capa.Id)) { r.skipped++; continue; }
                    rps.add(new compliancequest__SQX_Related_Product__c(
                        compliancequest__SQX_Product_History_Review__c = c.phrId,
                        compliancequest__SQX_CAPA__c = capa.Id,
                        compliancequest__SQX_Product_Component__c = capa.compliancequest__SQX_Part__c,
                        compliancequest__Comment__c = TAG));
                }
            }
            if (hasAny(changeOrderIds)) {
                for (compliancequest__SQX_Change_Order__c co : [
                    SELECT Id, Name, compliancequest__SQX_Product__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :changeOrderIds
                ]) {
                    if (addedRefs.contains(refKey('Change Order', co.Name))) { r.skipped++; continue; }
                    rps.add(new compliancequest__SQX_Related_Product__c(
                        compliancequest__SQX_Product_History_Review__c = c.phrId,
                        compliancequest__Reference_Type__c = 'Change Order',
                        compliancequest__Other_Reference_Number__c = co.Name,
                        compliancequest__SQX_Product_Component__c = co.compliancequest__SQX_Product__c,
                        compliancequest__Comment__c = TAG));
                }
            }
            if (hasAny(inspectionIds)) {
                for (compliancequest__SQX_Inspection__c insp : [
                    SELECT Id, Name, compliancequest__SQX_Part__c FROM compliancequest__SQX_Inspection__c WHERE Id IN :inspectionIds
                ]) {
                    if (addedRefs.contains(refKey('Inspection', insp.Name))) { r.skipped++; continue; }
                    rps.add(new compliancequest__SQX_Related_Product__c(
                        compliancequest__SQX_Product_History_Review__c = c.phrId,
                        compliancequest__Reference_Type__c = 'Inspection',
                        compliancequest__Other_Reference_Number__c = insp.Name,
                        compliancequest__SQX_Product_Component__c = insp.compliancequest__SQX_Part__c,
                        compliancequest__Comment__c = TAG));
                }
            }

            r.relatedProductsCreated = insertRows(rps, r.errors);
            r.linkedInvestigationsCreated = 0;
            r.success = r.errors.isEmpty();
            r.message = 'Added ' + r.relatedProductsCreated + ' related record(s) to the PHR; '
                + r.skipped + ' already present.';
            if (!r.errors.isEmpty()) {
                r.message += ' Some rows failed: ' + String.join(r.errors, '; ');
            }
        } catch (Exception ex) {
            r.success = false;
            r.message = ex.getMessage();
            r.errors.add(ex.getMessage());
        }
        return r;
    }

    // ---------- Context ----------

    private static Ctx resolve(Id recordId, String lotOverride) {
        if (recordId == null) {
            throw new PhrQmsException('A Product History Review or Complaint Id is required.');
        }
        Ctx c = new Ctx();
        String objName = recordId.getSObjectType().getDescribe().getName();
        if (objName == PHR_OBJECT) {
            compliancequest__SQX_Product_History_Review__c phr = [
                SELECT Id, compliancequest__SQX_Complaint__c
                FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :recordId LIMIT 1
            ];
            c.phrId = phr.Id;
            c.complaintId = phr.compliancequest__SQX_Complaint__c;
        } else if (objName == COMPLAINT_OBJECT) {
            c.complaintId = recordId;
            for (compliancequest__SQX_Product_History_Review__c phr : [
                SELECT Id FROM compliancequest__SQX_Product_History_Review__c
                WHERE compliancequest__SQX_Complaint__c = :recordId
                ORDER BY CreatedDate DESC LIMIT 1
            ]) {
                c.phrId = phr.Id;
            }
        } else {
            throw new PhrQmsException('Unsupported record type: ' + objName);
        }
        if (c.complaintId == null) {
            throw new PhrQmsException('This Product History Review is not linked to a Complaint.');
        }

        compliancequest__SQX_Complaint__c cmp = [
            SELECT Name, compliancequest__SQX_Part__c, compliancequest__Lot_Number__c,
                   compliancequest__SQX_Lot_Info__r.Name,
                   compliancequest__SQX_Lot_Info__r.compliancequest__Manufacturing_Date__c,
                   compliancequest__Complaint_Title__c, compliancequest__Description__c,
                   compliancequest__Description_As_Reported__c, compliancequest__SQX_Complaint_Code__c,
                   compliancequest__Occurrence_Date__c
            FROM compliancequest__SQX_Complaint__c WHERE Id = :c.complaintId LIMIT 1
        ];
        c.complaintName = cmp.Name;
        c.partId = cmp.compliancequest__SQX_Part__c;
        c.symptomText = (cmp.compliancequest__Complaint_Title__c == null ? '' : cmp.compliancequest__Complaint_Title__c)
            + ' ' + (cmp.compliancequest__Description__c == null ? '' : cmp.compliancequest__Description__c)
            + ' ' + (cmp.compliancequest__Description_As_Reported__c == null ? '' : cmp.compliancequest__Description_As_Reported__c);
        c.complaintCodeId = cmp.compliancequest__SQX_Complaint_Code__c;
        c.occurrenceDate = cmp.compliancequest__Occurrence_Date__c;

        if (String.isNotBlank(lotOverride)) {
            addLot(c, lotOverride);
            c.lotOverridden = true;   // the complaint's manufactured date no longer applies
        } else {
            if (cmp.compliancequest__SQX_Lot_Info__r != null) {
                c.manufactureDate = cmp.compliancequest__SQX_Lot_Info__r.compliancequest__Manufacturing_Date__c;
            }
            addLot(c, cmp.compliancequest__Lot_Number__c);
            if (cmp.compliancequest__SQX_Lot_Info__r != null) {
                addLot(c, cmp.compliancequest__SQX_Lot_Info__r.Name);
            }
        }
        return c;
    }

    /** Says whether the optional manufacture date window was applied, and why not when it was skipped. */
    @TestVisible
    private static String windowNote(Ctx c) {
        PhrReportSettings.Values v = PhrReportSettings.get();
        if (!v.useWindow) { return null; }
        if (c.lotOverridden) {
            return 'The manufacture date window is on, but a different lot was typed, so the window was not applied.';
        }
        if (c.manufactureDate == null) {
            return 'The manufacture date window is on, but the complaint has no Lot Info with a manufactured date, so the window was not applied.';
        }
        Datetime first = PhrReportSettings.windowStart(v, c.manufactureDate);
        Datetime last = PhrReportSettings.windowEnd(v, c.manufactureDate).addDays(-1);
        return 'Only records created from ' + first.format('MMM d, yyyy') + ' to ' + last.format('MMM d, yyyy')
            + ' are shown (manufactured ' + c.manufactureDate.format() + ', ' + v.daysBefore + ' days before and ' + v.daysAfter + ' days after).';
    }

    private static void addLot(Ctx c, String lot) {
        if (String.isBlank(lot)) {
            return;
        }
        String t = lot.trim();
        c.lots.add(t);
        c.lotLabel = c.lotLabel == null ? t : (c.lotLabel.equalsIgnoreCase(t) ? c.lotLabel : c.lotLabel + ', ' + t);
    }

    /** Component Part Ids from Part -> Revision -> Assembly -> Assembly Line Item. */
    private static Set<Id> componentPartIds(Id partId) {
        Set<Id> ids = new Set<Id>();
        Set<Id> revisionIds = new Map<Id, cqext__CQPLM_Part_Revision__c>([
            SELECT Id FROM cqext__CQPLM_Part_Revision__c WHERE cqext__CQPLM_Part__c = :partId
        ]).keySet();
        if (revisionIds.isEmpty()) {
            return ids;
        }
        Set<Id> assemblyIds = new Map<Id, cqext__CQPLM_Assembly__c>([
            SELECT Id FROM cqext__CQPLM_Assembly__c WHERE cqext__CQPLM_Part_Revision__c IN :revisionIds
        ]).keySet();
        if (assemblyIds.isEmpty()) {
            return ids;
        }
        for (cqext__CQPLM_Assembly_line_Item__c li : [
            SELECT cqext__CQPLM_Part__c FROM cqext__CQPLM_Assembly_line_Item__c
            WHERE cqext__CQPLM_Assembly__c IN :assemblyIds AND cqext__CQPLM_Part__c != null
        ]) {
            ids.add(li.cqext__CQPLM_Part__c);
        }
        ids.remove(partId);
        return ids;
    }

    /** What is already on the PHR (Related Products) and on the Complaint (Linked Investigations). */
    private static void loadExisting(Ctx c, Set<Id> nc, Set<Id> capa, Set<String> refs, Set<Id> inv) {
        if (c.phrId != null) {
            for (compliancequest__SQX_Related_Product__c rp : [
                SELECT compliancequest__SQX_Nonconformance__c, compliancequest__SQX_CAPA__c,
                       compliancequest__Reference_Type__c, compliancequest__Other_Reference_Number__c
                FROM compliancequest__SQX_Related_Product__c
                WHERE compliancequest__SQX_Product_History_Review__c = :c.phrId
            ]) {
                if (rp.compliancequest__SQX_Nonconformance__c != null) { nc.add(rp.compliancequest__SQX_Nonconformance__c); }
                if (rp.compliancequest__SQX_CAPA__c != null) { capa.add(rp.compliancequest__SQX_CAPA__c); }
                if (rp.compliancequest__Reference_Type__c != null && rp.compliancequest__Other_Reference_Number__c != null) {
                    refs.add(refKey(rp.compliancequest__Reference_Type__c, rp.compliancequest__Other_Reference_Number__c));
                }
            }
        }
        for (compliancequest__SQX_Linked_Investigation__c li : [
            SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_Linked_Investigation__c
            WHERE compliancequest__SQX_Complaint__c = :c.complaintId
        ]) {
            if (li.compliancequest__SQX_Investigation__c != null) {
                inv.add(li.compliancequest__SQX_Investigation__c);
            }
        }
    }

    @TestVisible
    private static String refKey(String refType, String refNumber) {
        return (refType + '|' + refNumber).toLowerCase();
    }

    // ---------- Finders ----------

    private static void findNonconformances(Set<Id> partIds, Set<String> lots, Set<Id> added, PanelData d) {
        for (compliancequest__SQX_Nonconformance__c nc : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_Nonconformance__c
            WHERE compliancequest__SQX_Part__c IN :partIds OR compliancequest__Lot_Number__c IN :lots
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            Row r = newRow(nc.Id, nc.Name, nc.CreatedDate, nc.compliancequest__Status__c,
                nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c);
            r.matchedBy = matchedBy(partIds.contains(nc.compliancequest__SQX_Part__c), lotHit(lots, nc.compliancequest__Lot_Number__c));
            r.alreadyAdded = added.contains(nc.Id);
            d.nonconformances.add(r);
        }
    }

    private static void findCapas(Set<Id> partIds, Set<Id> added, PanelData d) {
        if (partIds.isEmpty()) { return; }
        for (compliancequest__SQX_CAPA__c capa : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_CAPA__c
            WHERE compliancequest__SQX_Part__c IN :partIds
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            Row r = newRow(capa.Id, capa.Name, capa.CreatedDate, capa.compliancequest__Status__c,
                capa.compliancequest__SQX_Part__r == null ? null : capa.compliancequest__SQX_Part__r.compliancequest__Part_Number__c);
            r.matchedBy = 'Part';
            r.alreadyAdded = added.contains(capa.Id);
            d.capas.add(r);
        }
    }

    private static void findChangeOrders(Set<Id> partIds, Set<String> addedRefs, PanelData d) {
        if (partIds.isEmpty()) { return; }
        for (compliancequest__SQX_Change_Order__c co : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c,
                   compliancequest__SQX_Product__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_Change_Order__c
            WHERE compliancequest__SQX_Product__c IN :partIds
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            Row r = newRow(co.Id, co.Name, co.CreatedDate, co.compliancequest__Status__c,
                co.compliancequest__SQX_Product__r == null ? null : co.compliancequest__SQX_Product__r.compliancequest__Part_Number__c);
            r.matchedBy = 'Part';
            r.alreadyAdded = addedRefs.contains(refKey('Change Order', co.Name));
            d.changeOrders.add(r);
        }
    }

    private static void findInspections(Set<Id> partIds, Set<String> lots, Set<String> addedRefs, PanelData d) {
        for (compliancequest__SQX_Inspection__c insp : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_Inspection__c
            WHERE compliancequest__SQX_Part__c IN :partIds OR compliancequest__Lot_Number__c IN :lots
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            Row r = newRow(insp.Id, insp.Name, insp.CreatedDate, insp.compliancequest__Status__c,
                insp.compliancequest__SQX_Part__r == null ? null : insp.compliancequest__SQX_Part__r.compliancequest__Part_Number__c);
            r.matchedBy = matchedBy(partIds.contains(insp.compliancequest__SQX_Part__c), lotHit(lots, insp.compliancequest__Lot_Number__c));
            r.alreadyAdded = addedRefs.contains(refKey('Inspection', insp.Name));
            d.inspections.add(r);
        }
    }

    private static void findInvestigations(Ctx c, Set<Id> partIds, Set<Id> added, PanelData d) {
        Set<String> lots = c.lots;
        for (compliancequest__SQX_Investigation__c inv : [
            SELECT Id, Name, CreatedDate, compliancequest__Status__c, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                   compliancequest__SQX_Complaint__c, compliancequest__Source_Id__c,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_Investigation__c
            WHERE compliancequest__SQX_Part__c IN :partIds OR compliancequest__Lot_Number__c IN :lots
            ORDER BY CreatedDate DESC LIMIT :MAX_ROWS
        ]) {
            if (isOwnInvestigation(c.complaintId, inv.compliancequest__SQX_Complaint__c, inv.compliancequest__Source_Id__c)) {
                continue;
            }
            Row r = newRow(inv.Id, inv.Name, inv.CreatedDate, inv.compliancequest__Status__c,
                inv.compliancequest__SQX_Part__r == null ? null : inv.compliancequest__SQX_Part__r.compliancequest__Part_Number__c);
            r.matchedBy = matchedBy(partIds.contains(inv.compliancequest__SQX_Part__c), lotHit(lots, inv.compliancequest__Lot_Number__c));
            r.alreadyAdded = added.contains(inv.Id);
            d.investigations.add(r);
        }
    }

    // ---------- Helpers ----------

    private static Row newRow(Id id, String name, Datetime createdDate, String status, String partNumber) {
        Row r = new Row();
        r.id = id;
        r.name = name;
        r.createdDate = createdDate;
        r.status = status;
        r.partNumber = partNumber;
        return r;
    }

    /**
     * Scores every row, sorts the list (best first) and highlights the top few.
     * Match type dominates: Part+Lot (300) > Lot (200) > Part (100). Recent
     * creation (+10) and an open status (+5) only reorder rows within a tier.
     * A row is highlighted when it is in the first MAX_HIGHLIGHTS positions and
     * is either a Lot/Part+Lot match or newly created.
     */
    @TestVisible
    private static void rank(List<Row> rows) {
        Datetime cutoff = Datetime.now().addDays(-NEW_WINDOW_DAYS);
        for (Row r : rows) {
            r.isNew = r.createdDate != null && r.createdDate >= cutoff;
            r.score = score(r.matchedBy, r.isNew, r.status);
        }
        rows.sort();
        Integer shown = 0;
        for (Row r : rows) {
            if (shown >= MAX_HIGHLIGHTS) { break; }
            if (r.matchedBy == 'Part and Lot' || r.matchedBy == 'Lot' || r.isNew) {
                r.highlight = true;
                shown++;
            }
        }
    }

    @TestVisible
    private static Integer score(String matchedBy, Boolean isNew, String status) {
        Integer s = 0;
        if (matchedBy == 'Part and Lot') { s = 300; }
        else if (matchedBy == 'Lot') { s = 200; }
        else if (matchedBy == 'Part') { s = 100; }
        if (isNew == true) { s += 10; }
        if (isOpenStatus(status)) { s += 5; }
        return s;
    }

    @TestVisible
    private static Boolean isOpenStatus(String status) {
        return String.isBlank(status) || !CLOSED_STATUSES.contains(status.trim().toLowerCase());
    }

    /** Case-insensitive, trimmed lot comparison. */
    @TestVisible
    private static Boolean lotHit(Set<String> lots, String value) {
        if (String.isBlank(value) || lots == null) {
            return false;
        }
        for (String l : lots) {
            if (l.equalsIgnoreCase(value.trim())) {
                return true;
            }
        }
        return false;
    }

    @TestVisible
    private static String matchedBy(Boolean inPart, Boolean inLot) {
        if (inPart && inLot) { return 'Part and Lot'; }
        if (inLot) { return 'Lot'; }
        if (inPart) { return 'Part'; }
        return null;
    }

    /** True when the Investigation was started from this Complaint. */
    @TestVisible
    private static Boolean isOwnInvestigation(Id complaintId, Id investigationComplaintId, String sourceId) {
        if (complaintId == null) { return false; }
        if (investigationComplaintId != null && investigationComplaintId == complaintId) { return true; }
        return String.isNotBlank(sourceId) && sourceId.left(15) == String.valueOf(complaintId).left(15);
    }

    private static Boolean hasAny(List<Id> ids) {
        return ids != null && !ids.isEmpty();
    }

    /** Inserts what the running user may create; collects per-row failures. Returns the success count. */
    private static Integer insertRows(List<SObject> rows, List<String> errors) {
        if (rows.isEmpty()) {
            return 0;
        }
        SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, rows);
        Integer ok = 0;
        for (Database.SaveResult sr : Database.insert(decision.getRecords(), false)) {
            if (sr.isSuccess()) {
                ok++;
            } else if (errors.size() < 5) {
                errors.add(sr.getErrors()[0].getMessage());
            }
        }
        return ok;
    }

    /** Short plain-text summary used by the agent action. */
    public static String summarize(PanelData d, Boolean includeInvestigations) {
        Integer nc = countNew(d.nonconformances);
        Integer capa = countNew(d.capas);
        Integer co = countNew(d.changeOrders);
        Integer insp = countNew(d.inspections);
        Integer inv = includeInvestigations ? countNew(d.investigations) : 0;
        Integer already = countAdded(d.nonconformances) + countAdded(d.capas) + countAdded(d.changeOrders)
            + countAdded(d.inspections) + (includeInvestigations ? countAdded(d.investigations) : 0);
        return 'For ' + d.complaintName + (d.partNumber != null ? ' (part ' + d.partNumber + ')' : '')
            + (String.isNotBlank(d.lotNumber) ? ', lot ' + d.lotNumber : '')
            + ' (' + d.componentPartCount + ' assembly component part(s) included): '
            + nc + ' nonconformance(s), ' + capa + ' CAPA(s), ' + co + ' change order(s), '
            + insp + ' inspection(s), ' + inv + ' investigation(s) not yet added; '
            + already + ' already present.';
    }

    private static Integer countNew(List<Row> rows) {
        Integer n = 0;
        for (Row r : rows) { if (!r.alreadyAdded) { n++; } }
        return n;
    }

    private static Integer countAdded(List<Row> rows) {
        return rows.size() - countNew(rows);
    }
}

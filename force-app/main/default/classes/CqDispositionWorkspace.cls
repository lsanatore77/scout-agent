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
 *
 * Evidence-led (option B, 2026-11-22): What's Wrong shows the failure code, severity, specification against actual, the
 * photo and the investigation. Scrap and Return To Vendor can be done at any time; Rework and Use As Is need the root cause
 * recorded on the investigation, or a stated reason. The dispositioner signs off on their work: completing asks CQ's
 * electronic signature policy for Nonconformance > Completing Disposition (completedisposition) and signs first.
 */
public with sharing class CqDispositionWorkspace {
    public static final String COMPLETE = 'complete';
    public static final String USE_AS_IS = 'Use As Is';
    public static final List<String> DISPOSITION_TYPES = new List<String>{ 'Scrap', 'Rework', 'Return To Vendor (RTV)', USE_AS_IS };
    public static final Integer HISTORY = 50;         // past dispositions counted on the glance, by type
    public static final Integer EVIDENCE = 50;        // past dispositions weighed for the suggestion
    public static final String REWORK = 'Rework';
    public static final String SCRAP = 'Scrap';
    public static final String RTV = 'Return To Vendor (RTV)';
    public static final String HOLD = 'Hold';         // not a CQ type: leave the lot open until the root cause is known
    public static final String SIGN_ACTION = 'completedisposition';   // CQ's Nonconformance esig action, Completing Disposition

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
        @AuraEnabled public String code;              // the failure code of the NC it came from
        @AuraEnabled public Date completedOn;
        public Boolean cameBack = false;              // a Rework after which the same defect was reported again on the part
    }
    public class View {
        @AuraEnabled public String name; @AuraEnabled public String title; @AuraEnabled public String description;
        @AuraEnabled public Id partId; @AuraEnabled public String partNumber; @AuraEnabled public String partName; @AuraEnabled public String lot;
        @AuraEnabled public String stage; @AuraEnabled public String status; @AuraEnabled public String owner; @AuraEnabled public String risk;
        @AuraEnabled public String path; @AuraEnabled public Id investigationId; @AuraEnabled public String investigationName;
        @AuraEnabled public Date dispDue; @AuraEnabled public Boolean needsApproval = false; @AuraEnabled public Boolean isComplete = false;
        @AuraEnabled public List<String> types = DISPOSITION_TYPES;
        @AuraEnabled public String suggestType; @AuraEnabled public String suggestWhy;
        @AuraEnabled public List<String> suggestFactors = new List<String>();   // what the suggestion rests on
        @AuraEnabled public String confidence;                                 // High, Moderate, Low
        @AuraEnabled public String suggestAlt;                                 // with Hold: what to do if the stock cannot be held
        // What's Wrong
        @AuraEnabled public String failureCode; @AuraEnabled public String failureCategory; @AuraEnabled public String severity;
        @AuraEnabled public String spec; @AuraEnabled public String actual; @AuraEnabled public Decimal defective;
        @AuraEnabled public String photoId;
        @AuraEnabled public String investigationStatus; @AuraEnabled public Date investigationDue;
        @AuraEnabled public Boolean investigationOpen = false;
        @AuraEnabled public Boolean causeKnown = false; @AuraEnabled public String causeText; @AuraEnabled public String causeCategory;
        @AuraEnabled public String supplier; @AuraEnabled public Boolean supplierCause = false;
        @AuraEnabled public String fieldActionName; @AuraEnabled public String fieldActionLots;
        @AuraEnabled public Boolean functional = false;      // the defect fails a function or is Moderate or worse
        @AuraEnabled public Integer severityNum;
        // Rework and Use As Is before the root cause is known need a reason
        @AuraEnabled public Boolean reasonNeeded = true;
        public List<Past> evidence = new List<Past>();       // every past disposition weighed, newest first
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
                   compliancequest__Due_Date_Disposition__c, compliancequest__Disposition_Approval__c, compliancequest__Is_Disposition_Complete__c,
                   compliancequest__SQX_Investigation__r.compliancequest__Status__c, compliancequest__Due_Date_Investigation__c,
                   compliancequest__Defect_Code__c, compliancequest__Defect_Category__c, toLabel(compliancequest__Defect_Severity__c),
                   compliancequest__Defective_Quantity__c, compliancequest__Type__c, compliancequest__SQX_Supplier__c, compliancequest__SQX_Supplier__r.Name
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
        whatsWrong(v, nc, recordId);

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

        // past dispositions on this part, newest first, from other NCs: the latest are listed; more are weighed for the suggestion
        if (v.partId != null) { pastDispositions(v, recordId); }
        suggest(v);
        if (v.lots.isEmpty()) {
            v.suggestType = null;
            v.suggestWhy = 'This NC has no impacted parts or lots, so there is nothing to dispose.';
        }
        return v;
    }

    /** What's Wrong: the defect (from the NC, else its first Defect / Failure record), the photo, the investigation, a supplier, a field action. */
    static void whatsWrong(View v, compliancequest__SQX_Nonconformance__c nc, Id recordId) {
        v.failureCode = nc.compliancequest__Defect_Code__c; v.failureCategory = nc.compliancequest__Defect_Category__c;
        v.severity = nc.compliancequest__Defect_Severity__c; v.defective = nc.compliancequest__Defective_Quantity__c;
        for (compliancequest__SQX_NC_Defect__c d : [
                SELECT compliancequest__Defect_Code__c, compliancequest__Defect_Category__c, toLabel(compliancequest__Severity__c),
                       compliancequest__Specification__c, compliancequest__Actual__c
                FROM compliancequest__SQX_NC_Defect__c WHERE compliancequest__SQX_Nonconformance__c = :recordId WITH USER_MODE ORDER BY CreatedDate LIMIT 1]) {
            if (String.isBlank(v.failureCode)) { v.failureCode = d.compliancequest__Defect_Code__c; v.failureCategory = d.compliancequest__Defect_Category__c; }
            if (String.isBlank(v.severity)) { v.severity = d.compliancequest__Severity__c; }
            v.spec = d.compliancequest__Specification__c; v.actual = d.compliancequest__Actual__c;
        }
        v.severityNum = leadingNumber(v.severity);
        v.functional = (v.severityNum != null && v.severityNum >= 3) || (String.isNotBlank(v.spec) && String.isNotBlank(v.actual));
        try { v.photoId = CqTriagePhoto.getPhotoVersionId(recordId); } catch (Exception e) { v.photoId = null; }

        if (nc.compliancequest__SQX_Investigation__r != null) {
            v.investigationStatus = nc.compliancequest__SQX_Investigation__r.compliancequest__Status__c;
            v.investigationOpen = v.investigationStatus != 'Completed' && v.investigationStatus != 'Closed' && v.investigationStatus != 'Void';
            v.investigationDue = nc.compliancequest__Due_Date_Investigation__c;
            for (compliancequest__SQX_Root_Cause__c r : [
                    SELECT toLabel(compliancequest__Category__c), compliancequest__SQX_Root_Cause_Code__r.Name, compliancequest__Description__c
                    FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :v.investigationId WITH USER_MODE ORDER BY CreatedDate LIMIT 1]) {
                v.causeKnown = true;
                v.causeCategory = r.compliancequest__Category__c;
                String code = r.compliancequest__SQX_Root_Cause_Code__r == null ? null : r.compliancequest__SQX_Root_Cause_Code__r.Name;
                List<String> bits = new List<String>();
                if (String.isNotBlank(code)) { bits.add(code); }
                if (String.isNotBlank(r.compliancequest__Description__c)) { bits.add(r.compliancequest__Description__c.abbreviate(120)); }
                v.causeText = bits.isEmpty() ? v.causeCategory : String.join(bits, ': ');
            }
        }
        v.reasonNeeded = !v.causeKnown;

        if (nc.compliancequest__SQX_Supplier__r != null) { v.supplier = nc.compliancequest__SQX_Supplier__r.Name; }
        v.supplierCause = nc.compliancequest__Type__c == 'Supplier' || nc.compliancequest__SQX_Supplier__c != null;
    }

    /** An open field action (not Closed) whose approved scope holds one of this NC's lots. */
    static void fieldAction(View v) {
        Set<String> lots = new Set<String>();
        for (Lot l : v.lots) { if (String.isNotBlank(l.lot) && l.left > 0) { lots.add(l.lot); } }
        if (lots.isEmpty()) { return; }
        List<String> hit = new List<String>();
        for (Field_Action_Lot__c f : [
                SELECT Field_Action__r.Name, Lot_Number__c FROM Field_Action_Lot__c
                WHERE Lot_Number__c IN :lots AND Approved_In_Scope__c = true AND Field_Action__r.Status__c != 'Closed'
                WITH USER_MODE ORDER BY Field_Action__r.Name, Lot_Number__c LIMIT 20]) {
            if (v.fieldActionName == null) { v.fieldActionName = f.Field_Action__r.Name; }
            if (f.Field_Action__r.Name == v.fieldActionName) { hit.add(f.Lot_Number__c); }
        }
        if (!hit.isEmpty()) { v.fieldActionLots = String.join(hit, ', '); }
    }

    /** Completed dispositions on this part from other NCs, with each NC's failure code, and whether a Rework was followed by the same defect again. */
    static void pastDispositions(View v, Id recordId) {
        List<compliancequest__SQX_Disposition__c> ds = [
            SELECT compliancequest__SQX_Nonconformance__c, compliancequest__SQX_Nonconformance__r.Name, compliancequest__Disposition_Type__c,
                   compliancequest__Actual_Quantity_Disposed__c, compliancequest__Disposition_Quantity__c, compliancequest__Lot_Number__c,
                   compliancequest__Completed_On__c, compliancequest__SQX_Nonconformance__r.compliancequest__Defect_Code__c
            FROM compliancequest__SQX_Disposition__c
            WHERE compliancequest__SQX_Part__c = :v.partId AND compliancequest__SQX_Nonconformance__c != :recordId
              AND compliancequest__Status__c = 'Complete' AND compliancequest__Disposition_Type__c != null
            WITH USER_MODE ORDER BY compliancequest__Completed_On__c DESC NULLS LAST, CreatedDate DESC LIMIT :EVIDENCE];
        Set<Id> ncIds = new Set<Id>();
        for (compliancequest__SQX_Disposition__c d : ds) { ncIds.add(d.compliancequest__SQX_Nonconformance__c); }
        // an NC's failure code may only be on its Defect / Failure list
        Map<Id, String> listCode = new Map<Id, String>();
        for (compliancequest__SQX_NC_Defect__c d : [
                SELECT compliancequest__SQX_Nonconformance__c, compliancequest__Defect_Code__c FROM compliancequest__SQX_NC_Defect__c
                WHERE compliancequest__SQX_Nonconformance__c IN :ncIds AND compliancequest__Defect_Code__c != null WITH USER_MODE ORDER BY CreatedDate]) {
            if (!listCode.containsKey(d.compliancequest__SQX_Nonconformance__c)) { listCode.put(d.compliancequest__SQX_Nonconformance__c, d.compliancequest__Defect_Code__c); }
        }
        for (compliancequest__SQX_Disposition__c d : ds) {
            Past p = new Past();
            p.ncId = d.compliancequest__SQX_Nonconformance__c; p.ncName = d.compliancequest__SQX_Nonconformance__r.Name;
            p.type = d.compliancequest__Disposition_Type__c; p.lot = d.compliancequest__Lot_Number__c; p.completedOn = d.compliancequest__Completed_On__c;
            p.qty = d.compliancequest__Actual_Quantity_Disposed__c != null ? d.compliancequest__Actual_Quantity_Disposed__c : d.compliancequest__Disposition_Quantity__c;
            p.code = d.compliancequest__SQX_Nonconformance__r.compliancequest__Defect_Code__c;
            if (String.isBlank(p.code)) { p.code = listCode.get(p.ncId); }
            v.evidence.add(p);
            if (v.history.size() < HISTORY) { v.history.add(p); }
        }
        // a Rework with a failure code, after which an NC with the same code was reported on the part (this one included)
        Map<String, Date> firstRework = new Map<String, Date>();
        for (Past p : v.evidence) {
            if (p.type == REWORK && String.isNotBlank(p.code) && p.completedOn != null
                    && (!firstRework.containsKey(p.code) || p.completedOn < firstRework.get(p.code))) { firstRework.put(p.code, p.completedOn); }
        }
        if (firstRework.isEmpty()) { return; }
        Map<String, Datetime> lastReported = new Map<String, Datetime>();
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT compliancequest__Defect_Code__c, CreatedDate FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__SQX_Part__c = :v.partId AND compliancequest__Defect_Code__c IN :firstRework.keySet() WITH USER_MODE]) {
            Datetime was = lastReported.get(n.compliancequest__Defect_Code__c);
            if (was == null || n.CreatedDate > was) { lastReported.put(n.compliancequest__Defect_Code__c, n.CreatedDate); }
        }
        for (Past p : v.evidence) {
            if (p.type != REWORK || String.isBlank(p.code) || p.completedOn == null) { continue; }
            Datetime later = lastReported.get(p.code);
            p.cameBack = later != null && later.date() > p.completedOn;
        }
    }

    /**
     * CQ.AI's suggestion, from fixed rules so it can be traced: a recall and High risk come first, then a supplier cause, then
     * the root cause (wait for it when the defect matters), then what was done before, same defect first, newest counting most.
     * Use As Is is never suggested for a defect that fails a function or is Moderate or worse.
     */
    @TestVisible
    static void suggest(View v) {
        v.suggestFactors = new List<String>(); v.suggestAlt = null;
        if (v.evidence.isEmpty() && !v.history.isEmpty()) { v.evidence = v.history; }   // tests pass history only
        fieldActionLookup(v);
        String risk = v.risk == null ? null : 'Risk ' + v.risk;
        if (v.fieldActionName != null) {
            v.suggestType = SCRAP; v.confidence = 'High';
            v.suggestWhy = v.fieldActionName + ' is recalling ' + (v.fieldActionLots != null && v.fieldActionLots.contains(',') ? 'lots ' : 'lot ') + v.fieldActionLots
                + ', so units on hand follow the recall and are not released.';
            v.suggestFactors.add('Open field action ' + v.fieldActionName + ' covers ' + v.fieldActionLots);
            addCommon(v, risk);
            return;
        }
        if (v.risk == 'High') {
            v.suggestType = SCRAP; v.confidence = 'High';
            v.suggestWhy = 'Risk is High, so releasing these units would need an engineering justification, and rework would need to bring them back to spec.';
            addCommon(v, risk);
            return;
        }
        if (v.supplierCause) {
            v.suggestType = RTV; v.confidence = 'Moderate';
            v.suggestWhy = 'The problem traces to ' + (v.supplier != null ? v.supplier : 'a supplier') + ', so returning the units lets the supplier replace them and answer for the cause.';
            v.suggestFactors.add('Supplier cause: ' + (v.supplier != null ? v.supplier : 'a Supplier NC'));
            addCommon(v, risk);
            return;
        }
        if (!v.causeKnown && v.investigationOpen && v.functional) {
            v.suggestType = HOLD; v.suggestAlt = SCRAP; v.confidence = 'Moderate';
            v.suggestWhy = 'The defect ' + (String.isNotBlank(v.actual) ? 'fails its specification' : 'is ' + (v.severity == null ? 'significant' : v.severity.replaceAll('^\\d+\\s*-\\s*', '')))
                + ', so Rework or Use As Is should wait for ' + v.investigationName + ' to find the root cause. Scrap now is reasonable if you cannot hold the stock.';
            v.suggestFactors.add('Root cause not found yet: ' + v.investigationName + ' is ' + (v.investigationStatus == null ? 'open' : v.investigationStatus));
            weigh(v, true);
            addCommon(v, risk);
            return;
        }
        weigh(v, false);
        addCommon(v, risk);
    }

    /** The field action is looked up once the lots are known (getView); tests set it directly. */
    static void fieldActionLookup(View v) {
        if (v.fieldActionName == null && !v.lots.isEmpty()) {
            try { fieldAction(v); } catch (Exception e) { v.fieldActionName = null; }
        }
    }

    /** What was done before: same defect first, else the part; newest counts most; a Rework that did not hold counts little. */
    static void weigh(View v, Boolean factorsOnly) {
        List<Past> same = new List<Past>();
        if (String.isNotBlank(v.failureCode)) {
            for (Past p : v.evidence) { if (p.code == v.failureCode) { same.add(p); } }
        }
        Boolean bySame = !same.isEmpty();
        List<Past> pool = bySame ? same : v.evidence;
        Map<String, Decimal> score = new Map<String, Decimal>();
        Map<String, Integer> count = new Map<String, Integer>();
        Integer cameBack = 0;
        for (Past p : pool) {
            Decimal w = recency(p.completedOn) * (p.cameBack == true ? 0.3 : 1.0);
            if (p.cameBack == true) { cameBack++; }
            score.put(p.type, (score.containsKey(p.type) ? score.get(p.type) : 0.0) + w);
            count.put(p.type, (count.containsKey(p.type) ? count.get(p.type) : 0) + 1);
        }
        Boolean noUseAsIs = v.functional || (v.severityNum != null && v.severityNum >= 3);
        String top; Decimal topW = 0; Decimal totalW = 0;
        for (String t : score.keySet()) {
            totalW += score.get(t);
            if (t == USE_AS_IS && noUseAsIs) { continue; }
            if (score.get(t) > topW) { top = t; topW = score.get(t); }
        }
        // the history line
        if (!pool.isEmpty()) {
            List<String> mix = new List<String>();
            for (String t : count.keySet()) { mix.add(count.get(t) + ' ' + t); }
            mix.sort();
            String basis = bySame ? 'Same defect on this part (' + v.failureCode + ')' : 'This part' + (String.isNotBlank(v.failureCode) ? ' (no past case with ' + v.failureCode + ')' : '');
            v.suggestFactors.add(basis + ': ' + pool.size() + (pool.size() == 1 ? ' earlier disposition, ' : ' earlier dispositions, ') + String.join(mix, ', '));
        } else {
            v.suggestFactors.add('No earlier dispositions on this part to go by');
        }
        if (cameBack > 0) { v.suggestFactors.add(cameBack + (cameBack == 1 ? ' earlier Rework was' : ' earlier Reworks were') + ' followed by the same defect again, so Rework counts less'); }
        if (noUseAsIs && score.containsKey(USE_AS_IS)) { v.suggestFactors.add('Use As Is is not suggested: the defect ' + (String.isNotBlank(v.actual) ? 'fails its specification' : 'is Moderate or worse')); }
        if (factorsOnly) { return; }

        if (v.causeKnown && v.causeCategory != null) {
            String c = v.causeCategory.toLowerCase();
            String byCause = c.contains('material') ? SCRAP
                : (c.contains('machine') || c.contains('method') || c.contains('process') || c.contains('equipment') || c.contains('tool')) ? REWORK : null;
            if (byCause != null) { v.suggestFactors.add('Root cause: ' + v.causeText + (byCause == REWORK ? ' (a process cause, so rework can fix the units)' : ' (a material cause)')); }
            if (byCause != null && (top == null || pool.size() < 2)) {
                v.suggestType = byCause; v.confidence = 'Moderate';
                v.suggestWhy = 'The root cause is ' + v.causeText + '. ' + (byCause == REWORK ? 'A process cause usually means the units can be reworked to spec.' : 'A material cause usually means the units cannot be brought back to spec.');
                return;
            }
        }
        if (top != null) {
            v.suggestType = top;
            Integer n = count.get(top);
            Decimal share = totalW == 0 ? 0.0 : topW / totalW;
            v.confidence = pool.size() >= 5 && share >= 0.7 ? 'High' : pool.size() >= 2 ? 'Moderate' : 'Low';
            v.suggestWhy = (bySame ? n + ' of ' + pool.size() + ' earlier dispositions with this defect on this part ' : n + ' of the last ' + pool.size() + ' dispositions on this part ')
                + (n == 1 ? 'was ' : 'were ') + top + '.' + (v.risk == null ? '' : ' Risk is ' + v.risk + '.');
            if (pool.size() == 1) { v.suggestWhy = (bySame ? 'The only earlier disposition with this defect on this part was ' : 'The last disposition on this part was ') + top + '.' + (v.risk == null ? '' : ' Risk is ' + v.risk + '.'); }
        } else {
            v.suggestType = SCRAP; v.confidence = 'Low';
            v.suggestWhy = 'There are no past dispositions ' + (pool.isEmpty() ? 'on this part ' : 'that fit ') + 'to go by, so Scrap is the safe choice unless engineering says the units can be used or reworked.';
        }
    }

    static void addCommon(View v, String risk) {
        List<String> bits = new List<String>();
        if (risk != null) { bits.add(risk); }
        bits.add(v.supplierCause ? 'supplier-caused' : 'not supplier-caused');
        if (v.fieldActionName == null) { bits.add('no open field action on these lots'); }
        if (v.causeKnown && v.suggestType != REWORK && v.suggestType != SCRAP) { bits.add('root cause ' + v.causeText); }
        v.suggestFactors.add(String.join(bits, ' · '));
        if (v.confidence == 'Low') { v.suggestFactors.add('Little to go on, so low confidence'); }
    }

    /** Newer counts more: the last 90 days in full, the last year at 0.6, older at 0.3. */
    static Decimal recency(Date d) {
        if (d == null) { return 0.6; }
        Integer age = d.daysBetween(Date.today());
        return age <= 90 ? 1.0 : age <= 365 ? 0.6 : 0.3;
    }
    static Integer leadingNumber(String s) {
        if (String.isBlank(s)) { return null; }
        String d = s.trim().left(1);
        return d.isNumeric() ? Integer.valueOf(d) : null;
    }

    /**
     * Records and completes the dispositions, signed by the dispositioner when CQ's policy for Nonconformance > Completing
     * Disposition asks for it. Every row is checked first; then CQ checks the password and the signature is written, for
     * exactly the rows saved here; then the dispositions are saved. If any of it fails, nothing is changed.
     */
    @AuraEnabled
    public static Result completeDispositions(Id recordId, String payload, String comment, String password) {
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
            if (r.type == REWORK && v.reasonNeeded && String.isBlank(r.justification)) {
                throw new AuraHandledException('Rework on lot ' + l.lot + ' needs a reason: the root cause is not known yet.');
            }
            total.put(r.impactedId, (total.containsKey(r.impactedId) ? total.get(r.impactedId) : 0) + r.qty);
        }
        for (Id k : total.keySet()) {
            Lot l = lots.get(k);
            if (total.get(k) > l.left) { throw new AuraHandledException('Lot ' + l.lot + ' has ' + num(l.left) + ' left to dispose, not ' + num(total.get(k)) + '.'); }
        }

        List<Id> doneIds = new List<Id>();
        Savepoint sp = Database.setSavepoint();
        // the dispositioner signs for exactly these rows, before anything is saved (CqEsign; the password goes straight to CQ)
        CqNcSignable.signing = signedFor(rows, lots);
        try {
            CqEsign.sign(recordId, SIGN_ACTION, comment, password, true);
        } catch (AuraHandledException e) {
            Database.rollback(sp);
            throw e;
        }
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
        } catch (SecurityException e) {
            Database.rollback(sp);
            throw new AuraHandledException('CQ did not complete the disposition: ' + CqSave.DENIED);
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
        } catch (DmlException e) { /* the dispositions are complete; a missing draft for the rest is not worth failing over */ } catch (SecurityException e) { /* as above */ }
        res.ncComplete = [SELECT compliancequest__Is_Disposition_Complete__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId WITH USER_MODE].compliancequest__Is_Disposition_Complete__c == true;
        return res;
    }

    /** What the signature is for: each lot and its split, for example "Lot L26-0908: 3 Rework, 2 Scrap (5 units)". */
    @TestVisible
    static String signedFor(List<Row> rows, Map<Id, Lot> lots) {
        Map<Id, List<String>> byLot = new Map<Id, List<String>>();
        Map<Id, Decimal> totals = new Map<Id, Decimal>();
        List<Id> order = new List<Id>();
        for (Row r : rows) {
            if (!byLot.containsKey(r.impactedId)) { byLot.put(r.impactedId, new List<String>()); totals.put(r.impactedId, 0); order.add(r.impactedId); }
            byLot.get(r.impactedId).add(num(r.qty) + ' ' + r.type);
            totals.put(r.impactedId, totals.get(r.impactedId) + r.qty);
        }
        List<String> out = new List<String>();
        for (Id k : order) {
            Lot l = lots.get(k);
            out.add('Lot ' + (l == null ? '?' : l.lot) + ': ' + String.join(byLot.get(k), ', ') + ' (' + num(totals.get(k)) + (totals.get(k) == 1 ? ' unit)' : ' units)'));
        }
        return String.join(out, '; ');
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

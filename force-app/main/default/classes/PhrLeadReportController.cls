/**
 * PhrLeadReportController
 * ------------------------
 * Controller for the PhrLeadReportPDF page: the lead-package report (design 16.9).
 *
 * Everything is read fresh from the org each time the page renders, so running the
 * report again later gives current information. Nothing is written here.
 *
 *   id       Complaint Id (a Product History Review Id also works)
 *   version  Version number to print in the header (set by PhrLeadReportAction)
 *   format   'html' renders an HTML preview instead of a PDF
 *
 * Contents: header, overall significance, short summary (recommendations and gaps,
 * no record names), top 10 records (Top and Next combined), CQ task progress,
 * related investigations, and a note of data gaps.
 */
public without sharing class PhrLeadReportController {

    public static final Integer MAX_RECORDS = 10;
    public static final Integer MAX_SUMMARY_WORDS = 100;

    public class LeadRow {
        public String colour { get; set; }
        public String colourClass { get; set; }
        public Integer score { get; set; }
        public String recordType { get; set; }
        public String name { get; set; }
        public String title { get; set; }
        public String status { get; set; }
        public String createdDate { get; set; }
        public String matchedOn { get; set; }
    }

    public class InvRow {
        public String name { get; set; }
        public String status { get; set; }
        public String matchedBy { get; set; }
        public String createdDate { get; set; }
    }

    public String renderAs { get; private set; }
    public String errorMessage { get; private set; }
    public Boolean hasComplaint { get; private set; }
    public String complaintName { get; private set; }
    public String phrName { get; private set; }
    public String partLabel { get; private set; }
    public String lotNumber { get; private set; }
    public String generatedAt { get; private set; }
    public String versionLabel { get; private set; }

    public Integer overallScore { get; private set; }
    public String overallRating { get; private set; }
    public String ratingClass { get; private set; }
    public List<String> reasons { get; private set; }
    public String summaryText { get; private set; }
    public Integer summaryWords { get; private set; }
    public String draftSummaryHtml { get; private set; }
    public List<LeadRow> leadRows { get; private set; }
    public Integer totalLeads { get; private set; }
    public List<InvRow> investigationRows { get; private set; }
    public ComplaintTaskProgress.Summary taskSummary { get; private set; }
    public List<String> gaps { get; private set; }

    public Boolean getHasError() { return String.isNotBlank(errorMessage); }
    public Boolean getHasLeads() { return !leadRows.isEmpty(); }
    public Boolean getHasReasons() { return !reasons.isEmpty(); }
    public Boolean getHasInvestigations() { return !investigationRows.isEmpty(); }
    public Boolean getHasTasks() { return taskSummary != null && taskSummary.total > 0; }
    public Boolean getHasOverdueTasks() { return taskSummary != null && taskSummary.overdueCount > 0; }
    public Boolean getHasGaps() { return !gaps.isEmpty(); }
    public Boolean getHasDraftSummary() { return String.isNotBlank(draftSummaryHtml); }
    public Boolean getHasMoreLeads() { return totalLeads > leadRows.size(); }
    public String getLeadsNote() {
        return 'Showing ' + leadRows.size() + ' of ' + totalLeads
            + ' leads (limit ' + MAX_RECORDS + '). Highest score first, Top and Next tiers combined. Set-aside records are not listed.';
    }

    public PhrLeadReportController() {
        hasComplaint = false;
        reasons = new List<String>();
        leadRows = new List<LeadRow>();
        investigationRows = new List<InvRow>();
        gaps = new List<String>();
        totalLeads = 0;
        overallScore = 0;
        overallRating = 'None';
        ratingClass = 'r-none';
        summaryText = '';
        summaryWords = 0;
        taskSummary = ComplaintTaskProgress.summarize(new List<compliancequest__SQX_Complaint_Task__c>(), Date.today());

        Map<String, String> params = ApexPages.currentPage().getParameters();
        renderAs = 'html'.equalsIgnoreCase(params.get('format')) ? null : 'pdf';
        versionLabel = String.isBlank(params.get('version')) ? '1' : params.get('version');
        generatedAt = System.now().format('MMM d, yyyy h:mm a');

        Id recId;
        try { recId = Id.valueOf(params.get('id')); } catch (Exception e) { recId = null; }
        if (recId == null) {
            errorMessage = 'No complaint was specified for this report.';
            return;
        }
        try {
            load(recId);
        } catch (Exception ex) {
            errorMessage = ex.getMessage();
        }
    }

    private void load(Id recId) {
        PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(recId, null);
        if (!d.success) {
            errorMessage = d.errorMessage;
            return;
        }
        hasComplaint = true;
        complaintName = d.complaintName;
        lotNumber = d.lotNumber;
        partLabel = String.isBlank(d.partName) ? null : d.partName + (String.isBlank(d.partNumber) ? '' : ' (' + d.partNumber + ')');

        List<PhrQmsPanelController.Row> leads = new List<PhrQmsPanelController.Row>();
        leads.addAll(d.nonconformances);
        leads.addAll(d.capas);
        leads.addAll(d.changeOrders);
        leads.addAll(d.inspections);

        // The score and rating come from the same action the agent card uses, so they always match.
        PhrLeadPackageAction.Request pr = new PhrLeadPackageAction.Request();
        pr.recordId = recId;
        PhrLeadPackageData pkg = PhrLeadPackageAction.run(new List<PhrLeadPackageAction.Request>{ pr })[0].leadPackage;
        overallScore = pkg.overallScore == null ? 0 : pkg.overallScore;
        overallRating = String.isBlank(pkg.overallRating) ? 'None' : pkg.overallRating;
        ratingClass = 'r-' + overallRating.toLowerCase();

        // Top and Next only, highest score first, ten in total.
        List<PhrQmsPanelController.Row> kept = new List<PhrQmsPanelController.Row>();
        for (PhrQmsPanelController.Row r : leads) {
            if (r.tier == 'Top' || r.tier == 'Next') { kept.add(r); }
        }
        kept = sortByRelevance(kept);
        totalLeads = kept.size();
        Map<Id, String> titles = loadTitles(kept);
        for (Integer i = 0; i < kept.size() && i < MAX_RECORDS; i++) {
            PhrQmsPanelController.Row r = kept[i];
            LeadRow lr = new LeadRow();
            lr.colour = String.isBlank(r.colour) ? '' : r.colour;
            lr.colourClass = 'c-' + (String.isBlank(r.colour) ? 'none' : r.colour.toLowerCase());
            lr.score = r.relevance;
            lr.recordType = r.recordType;
            lr.name = r.name;
            lr.title = titles.get(r.id);
            lr.status = r.status;
            lr.createdDate = r.createdDate == null ? '' : r.createdDate.format('MMM d, yyyy');
            lr.matchedOn = r.criteriaMet;
            leadRows.add(lr);
        }

        for (PhrQmsPanelController.Row r : d.investigations) {
            InvRow ir = new InvRow();
            ir.name = r.name;
            ir.status = r.status;
            ir.matchedBy = r.matchedBy;
            ir.createdDate = r.createdDate == null ? '' : r.createdDate.format('MMM d, yyyy');
            investigationRows.add(ir);
        }

        taskSummary = ComplaintTaskProgress.getForComplaint(d.complaintId, AccessLevel.SYSTEM_MODE);

        loadPhr(d);
        reasons = buildReasons(kept);
        summaryText = buildSummary(kept, gaps.size());
        summaryWords = countWords(summaryText);
        draftSummaryHtml = loadDraftSummary(d.complaintId);
    }

    private void loadPhr(PhrQmsPanelController.PanelData d) {
        if (String.isBlank(d.lotNumber)) {
            gaps.add('The complaint has no lot number, so records were ranked by part only.');
        }
        if (String.isBlank(d.partName)) {
            gaps.add('The complaint has no part, so no related records could be found.');
        }
        if (d.phrId == null) {
            gaps.add('There is no Product History Review yet, so records cannot be added.');
            return;
        }
        List<compliancequest__SQX_Product_History_Review__c> phrs = [
            SELECT Name, compliancequest__Status__c, compliancequest__Completed_By__c
            FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :d.phrId LIMIT 1
        ];
        if (phrs.isEmpty()) { return; }
        phrName = phrs[0].Name;
        if (phrs[0].compliancequest__Status__c == 'Draft' && String.isBlank(phrs[0].compliancequest__Completed_By__c)) {
            gaps.add('The Product History Review is a draft and Completed By is empty.');
        }
        Integer blank = [
            SELECT COUNT() FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :d.phrId AND compliancequest__Answer__c = null
        ];
        if (blank > 0) {
            gaps.add(blank + (blank == 1 ? ' checklist question is' : ' checklist questions are') + ' not answered.');
        }
    }

    /** Titles for NCs, CAPAs and change orders. Inspections and investigations have none. */
    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
            else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [
            SELECT Id, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc
        ]) { m.put(x.Id, x.compliancequest__NC_Title__c); }
        for (compliancequest__SQX_CAPA__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capa
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        for (compliancequest__SQX_Change_Order__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :co
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        return m;
    }

    // ---------- Pure helpers (unit tested directly) ----------

    @TestVisible
    private static List<PhrQmsPanelController.Row> sortByRelevance(List<PhrQmsPanelController.Row> rows) {
        List<PhrQmsPanelController.Row> sorted = new List<PhrQmsPanelController.Row>(rows);
        // Selection sort by relevance desc, then name: the lists are small.
        for (Integer i = 0; i < sorted.size(); i++) {
            Integer best = i;
            for (Integer j = i + 1; j < sorted.size(); j++) {
                Integer a = sorted[j].relevance == null ? -1 : sorted[j].relevance;
                Integer b = sorted[best].relevance == null ? -1 : sorted[best].relevance;
                if (a > b || (a == b && String.valueOf(sorted[j].name) < String.valueOf(sorted[best].name))) { best = j; }
            }
            PhrQmsPanelController.Row t = sorted[i];
            sorted[i] = sorted[best];
            sorted[best] = t;
        }
        return sorted;
    }

    @TestVisible
    private List<String> buildReasons(List<PhrQmsPanelController.Row> leads) {
        List<String> out = new List<String>();
        Integer lot = 0;
        Integer open = 0;
        Integer co = 0;
        for (PhrQmsPanelController.Row r : leads) {
            if (String.isNotBlank(r.criteriaMet) && r.criteriaMet.contains('Lot')) { lot++; }
            if (!isClosed(r.status)) { open++; }
            if (r.recordType == 'Change Order' && !isClosed(r.status)) { co++; }
        }
        if (lot > 0) { out.add('The complaint lot appears on ' + lot + (lot == 1 ? ' other record' : ' other records')); }
        if (open > 0) { out.add(open + (open == 1 ? ' lead is' : ' leads are') + ' still open'); }
        if (co > 0) { out.add(co + ' open change ' + (co == 1 ? 'order touches' : 'orders touch') + ' this product'); }
        if (out.isEmpty() && !leads.isEmpty()) { out.add(leads.size() + ' records are worth reviewing'); }
        while (out.size() > 3) { out.remove(3); }
        return out;
    }

    /** The draft investigation summary saved on the complaint (rich text), made safe for the PDF engine. Null when none is saved. */
    private static String loadDraftSummary(Id complaintId) {
        if (complaintId == null) { return null; }
        List<compliancequest__SQX_Complaint__c> rows = [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Draft_Investigation_Summaries__c)) { return null; }
        return cleanForPdf(rows[0].Draft_Investigation_Summaries__c);
    }

    /** The PDF engine reads XML, so named HTML entities it does not know are written as numbers. */
    @TestVisible
    private static String cleanForPdf(String html) {
        return html.replace('&nbsp;', '&#160;').replace('<br>', '<br/>');
    }

    /** Short summary: recommendations and gaps only. Never names a record. */
    @TestVisible
    private static String buildSummary(List<PhrQmsPanelController.Row> leads, Integer gapCount) {
        List<String> parts = new List<String>();
        Integer top = 0;
        Integer open = 0;
        for (PhrQmsPanelController.Row r : leads) {
            if (r.tier == 'Top') { top++; }
            if (!isClosed(r.status)) { open++; }
        }
        if (leads.isEmpty()) {
            parts.add('No records worth reviewing were found for this complaint.');
        } else {
            Integer n = top > 0 ? top : leads.size();
            parts.add('Review the ' + n + (top > 0 ? ' top' : '') + ' lead' + (n == 1 ? '' : 's') + ' first.');
            if (open > 0) { parts.add('Check the status of the ' + open + ' that ' + (open == 1 ? 'is' : 'are') + ' still open.'); }
        }
        if (gapCount > 0) {
            parts.add('Close the ' + gapCount + ' data ' + (gapCount == 1 ? 'gap' : 'gaps') + ' listed at the end of this report, then run it again for a more accurate result.');
        } else {
            parts.add('No data gaps were found.');
        }
        parts.add('The relevance package has the detail.');
        return limitWords(String.join(parts, ' '), MAX_SUMMARY_WORDS);
    }

    @TestVisible
    private static Integer countWords(String s) {
        if (String.isBlank(s)) { return 0; }
        return s.trim().split('\\s+').size();
    }

    @TestVisible
    private static String limitWords(String s, Integer max) {
        List<String> w = s.trim().split('\\s+');
        if (w.size() <= max) { return s; }
        List<String> cut = new List<String>();
        for (Integer i = 0; i < max; i++) { cut.add(w[i]); }
        return String.join(cut, ' ');
    }

    private static Boolean isClosed(String status) {
        String s = String.isBlank(status) ? '' : status.toLowerCase();
        return s.contains('closed') || s.contains('complete') || s.contains('cancel') || s.contains('void');
    }
}

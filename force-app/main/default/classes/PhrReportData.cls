/**
 * PhrReportData
 * --------------
 * Gathers everything the template-based report shows, with no page involved.
 * It reads the same sources as the Visualforce report (PhrLeadReportController)
 * and gives the same figures, but works anywhere Apex runs: the agent, a queued
 * job, a test. The Visualforce report is untouched and keeps working.
 */
public without sharing class PhrReportData {

    public static final Integer MAX_RECORDS = 10;
    public static final Integer MAX_SUMMARY_WORDS = 100;

    public class LeadRow {
        public String colour;
        public String colourClass;
        public Integer score;
        public String recordType;
        public String name;
        public String title;
        public String status;
        public String createdDate;
        public String matchedOn;
    }

    public class InvRow {
        public String name;
        public String status;
        public String matchedBy;
        public String createdDate;
    }

    public Boolean hasComplaint = false;
    public String errorMessage;
    public String complaintName;
    public String phrName;
    public String partLabel;
    public String lotNumber;
    public String generatedAt;
    public String versionLabel = '1';
    public Integer overallScore = 0;
    public String overallRating = 'None';
    public String ratingClass = 'r-none';
    public List<String> reasons = new List<String>();
    public String summaryText = '';
    public Integer summaryWords = 0;
    public String draftSummaryHtml;
    /** The complaint's Reported Date, formatted for the header ('' when not set). */
    public String reportedDate = '';
    /** True when the report is run from an investigation: it then shows that investigation's summary. */
    public Boolean investigationMode = false;
    public String investigationName;
    /** 'PHR Summary', or 'Investigation Summary' when run from an investigation. */
    public String summaryHeading = 'PHR Summary';
    /** The report's title, from the PHR Report Setting: 'Product History Report' / 'Customer Report' by default. */
    public String reportTitle = 'Product History Report';
    public List<LeadRow> leadRows = new List<LeadRow>();
    public Integer totalLeads = 0;
    public List<InvRow> investigationRows = new List<InvRow>();
    public ComplaintTaskProgress.Summary taskSummary;
    public List<String> gaps = new List<String>();

    public static PhrReportData build(Id complaintId, String versionLabel) {
        return build(complaintId, versionLabel, null);
    }

    /**
     * investigationId: when set (the report was run from an investigation), the summary section shows that
     * investigation's Investigation Summary instead of the PHR Summary.
     */
    public static PhrReportData build(Id complaintId, String versionLabel, Id investigationId) {
        PhrReportData d = new PhrReportData();
        d.reportTitle = PhrReportSettings.phrTitle();
        if (investigationId != null) {
            d.investigationMode = true;
            d.summaryHeading = 'Investigation Summary';
            d.reportTitle = PhrReportSettings.investigationTitle();
        }
        d.taskSummary = ComplaintTaskProgress.summarize(new List<compliancequest__SQX_Complaint_Task__c>(), Date.today());
        d.generatedAt = System.now().format('MMM d, yyyy h:mm a');
        if (String.isNotBlank(versionLabel)) { d.versionLabel = versionLabel; }
        if (complaintId == null) {
            d.errorMessage = 'No complaint was specified for this report.';
            return d;
        }
        try {
            d.load(complaintId);
            d.loadReportedDate(complaintId);
            if (d.investigationMode) { d.loadInvestigationSummary(investigationId); }
        } catch (Exception ex) {
            d.errorMessage = ex.getMessage();
        }
        return d;
    }

    private void load(Id recId) {
        PhrQmsPanelController.PanelData p = PhrQmsPanelController.getPanelData(recId, null);
        if (!p.success) {
            errorMessage = p.errorMessage;
            return;
        }
        hasComplaint = true;
        complaintName = p.complaintName;
        lotNumber = p.lotNumber;
        partLabel = String.isBlank(p.partName) ? null : p.partName + (String.isBlank(p.partNumber) ? '' : ' (' + p.partNumber + ')');

        List<PhrQmsPanelController.Row> leads = new List<PhrQmsPanelController.Row>();
        leads.addAll(p.nonconformances);
        leads.addAll(p.capas);
        leads.addAll(p.changeOrders);
        leads.addAll(p.inspections);

        // Score and rating come from the same action the agent card uses, so they always match.
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

        for (PhrQmsPanelController.Row r : p.investigations) {
            InvRow ir = new InvRow();
            ir.name = r.name;
            ir.status = r.status;
            ir.matchedBy = r.matchedBy;
            ir.createdDate = r.createdDate == null ? '' : r.createdDate.format('MMM d, yyyy');
            investigationRows.add(ir);
        }

        taskSummary = ComplaintTaskProgress.getForComplaint(p.complaintId, AccessLevel.SYSTEM_MODE);

        loadPhr(p);
        reasons = buildReasons(kept);
        summaryText = buildSummary(kept, gaps.size());
        summaryWords = countWords(summaryText);
        draftSummaryHtml = loadPhrSummary(p.phrId, p.complaintId);
    }

    private void loadReportedDate(Id complaintId) {
        for (compliancequest__SQX_Complaint__c c : [
            SELECT compliancequest__Reported_Date__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId LIMIT 1
        ]) {
            Date dt = c.compliancequest__Reported_Date__c;
            reportedDate = dt == null ? '' : Datetime.newInstance(dt.year(), dt.month(), dt.day()).format('MMM d, yyyy');
        }
    }

    private void loadInvestigationSummary(Id investigationId) {
        draftSummaryHtml = null;
        for (compliancequest__SQX_Investigation__c inv : [
            SELECT Name, compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c
            WHERE Id = :investigationId LIMIT 1
        ]) {
            investigationName = inv.Name;
            if (String.isNotBlank(inv.compliancequest__Investigation_Summary__c)) {
                draftSummaryHtml = cleanForXml(inv.compliancequest__Investigation_Summary__c);
            }
        }
    }

    /** The Summary on the Product History Review, or the PHR Summary saved on the complaint when the PHR's is blank. */
    private static String loadPhrSummary(Id phrId, Id complaintId) {
        if (phrId != null) {
            for (compliancequest__SQX_Product_History_Review__c p : [
                SELECT compliancequest__Product_History_Review_Summary__c FROM compliancequest__SQX_Product_History_Review__c
                WHERE Id = :phrId LIMIT 1
            ]) {
                if (String.isNotBlank(p.compliancequest__Product_History_Review_Summary__c)) {
                    return cleanForXml(p.compliancequest__Product_History_Review_Summary__c);
                }
            }
        }
        return loadDraftSummary(complaintId);
    }

    private void loadPhr(PhrQmsPanelController.PanelData p) {
        if (String.isBlank(p.lotNumber)) {
            gaps.add('The complaint has no lot number, so records were ranked by part only.');
        }
        if (String.isBlank(p.partName)) {
            gaps.add('The complaint has no part, so no related records could be found.');
        }
        if (String.isNotBlank(p.windowNote) && p.windowNote.contains('was not applied')) {
            gaps.add(p.windowNote);
        }
        if (p.phrId == null) {
            gaps.add('There is no Product History Review yet, so records cannot be added.');
            return;
        }
        List<compliancequest__SQX_Product_History_Review__c> phrs = [
            SELECT Name, compliancequest__Status__c, compliancequest__Completed_By__c
            FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :p.phrId LIMIT 1
        ];
        if (phrs.isEmpty()) { return; }
        phrName = phrs[0].Name;
        if (phrs[0].compliancequest__Status__c == 'Draft' && String.isBlank(phrs[0].compliancequest__Completed_By__c)) {
            gaps.add('The Product History Review is a draft and Completed By is empty.');
        }
        Integer blank = [
            SELECT COUNT() FROM compliancequest__SQX_Product_History_Answer__c
            WHERE compliancequest__SQX_Product_History_Review__c = :p.phrId AND compliancequest__Answer__c = null
        ];
        if (blank > 0) {
            gaps.add(blank + (blank == 1 ? ' checklist question is' : ' checklist questions are') + ' not answered.');
        }
    }

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

    /** The PHR Summary saved on the complaint (rich text), made safe for an XML-based renderer. */
    private static String loadDraftSummary(Id complaintId) {
        if (complaintId == null) { return null; }
        List<compliancequest__SQX_Complaint__c> rows = [
            SELECT Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId LIMIT 1
        ];
        if (rows.isEmpty() || String.isBlank(rows[0].Draft_Investigation_Summaries__c)) { return null; }
        return cleanForXml(rows[0].Draft_Investigation_Summaries__c);
    }

    @TestVisible
    private static String cleanForXml(String html) {
        return html.replace('&nbsp;', '&#160;').replace('<br>', '<br/>');
    }

    // ---------- Pure helpers (unit tested directly) ----------

    @TestVisible
    private static List<PhrQmsPanelController.Row> sortByRelevance(List<PhrQmsPanelController.Row> rows) {
        List<PhrQmsPanelController.Row> sorted = new List<PhrQmsPanelController.Row>(rows);
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
    private static List<String> buildReasons(List<PhrQmsPanelController.Row> leads) {
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
        if (open > 0) { out.add(open + (open == 1 ? ' record is' : ' records are') + ' still open'); }
        if (co > 0) { out.add(co + ' open change ' + (co == 1 ? 'order touches' : 'orders touch') + ' this product'); }
        if (out.isEmpty() && !leads.isEmpty()) { out.add(leads.size() + ' records are worth reviewing'); }
        while (out.size() > 3) { out.remove(3); }
        return out;
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
            parts.add('Review the ' + n + (top > 0 ? ' most relevant' : '') + ' record' + (n == 1 ? '' : 's') + ' first.');
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

/**
 * ComplaintReportPDFController
 * ------------------------------
 * Controller for the ComplaintInvestigationReportPDF Visualforce page.
 *
 * The page is driven entirely by URL parameters, so it renders correctly
 * when fetched through PageReference.getContent() from Apex or opened in a
 * browser (it does NOT depend on static variables set by the caller, which
 * are not shared with the separate request getContent() makes):
 *
 *   id         Complaint Id (required)
 *   startDate  yyyy-MM-dd, optional  -- Created Date range for related records
 *   endDate    yyyy-MM-dd, optional
 *   format     'html' renders as an HTML preview instead of a PDF
 *
 * Content:
 *   - Investigation summary: the Complaint's saved Draft Investigation
 *     Summary field, with record numbers bolded.
 *   - Associated items: AssociatedItemsReportAction (part, BOM, NCs, CAPAs,
 *     Change Orders, Inspections, Lot Number matching, date range).
 *   - Most relevant nonconformances, ranked from real signals only: Lot
 *     Number match, being named in the saved summary, terms shared with the
 *     complaint, open status, and being filed against the primary part.
 */
public without sharing class ComplaintReportPDFController {

    // ---------- Row types exposed to the page ----------

    public class RecRow {
        public String name { get; set; }
        public String createdDate { get; set; }
    }

    public class LineRow {
        public String assemblyName { get; set; }
        public String partName { get; set; }
        public String partNumber { get; set; }
        public String lotMatch { get; set; }
        public Boolean lotHit { get; set; }
    }

    public class InvRow {
        public String name { get; set; }
        public String sourceName { get; set; }
        public String status { get; set; }
        public String matchedBy { get; set; }
        public String createdDate { get; set; }
    }

    public class InspectionRow {
        public String name { get; set; }
        public String partName { get; set; }
        public String lotNumber { get; set; }
        public String matchedBy { get; set; }
        public String createdDate { get; set; }
    }

    public class NcRow implements Comparable {
        public String name { get; set; }
        public String title { get; set; }
        public String status { get; set; }
        public String partName { get; set; }
        public String lotNumber { get; set; }
        public String matchedBy { get; set; }
        public String createdDate { get; set; }
        public String why { get; set; }
        public Integer score { get; set; }
        // Position of the NC number in the saved summary; -1 when not named.
        public Integer mentionPos { get; set; }
        // True when at least one real relevance signal exists.
        public Boolean qualifies { get; set; }

        public Integer compareTo(Object other) {
            NcRow o = (NcRow) other;
            if (score != o.score) {
                return score > o.score ? -1 : 1;
            }
            Integer a = mentionPos < 0 ? 999999 : mentionPos;
            Integer b = o.mentionPos < 0 ? 999999 : o.mentionPos;
            if (a != b) {
                return a < b ? -1 : 1;
            }
            if (name == o.name) {
                return 0;
            }
            // Later (higher-numbered) NC first on a full tie.
            return name > o.name ? -1 : 1;
        }
    }

    // ---------- Page state ----------

    public String renderAs { get; private set; }
    public Boolean hasComplaint { get; private set; }
    public String errorMessage { get; private set; }

    public String complaintName { get; private set; }
    public String complaintTitle { get; private set; }
    public String complaintCreated { get; private set; }
    public String lotNumber { get; private set; }
    public String dateRangeLabel { get; private set; }
    public String generatedAt { get; private set; }

    public Boolean hasSummary { get; private set; }
    public List<String> summaryParagraphs { get; private set; }

    public Boolean hasPrimaryPart { get; private set; }
    public String partName { get; private set; }
    public String partNumber { get; private set; }
    public String partType { get; private set; }
    public String partFamily { get; private set; }
    public String assemblyNames { get; private set; }

    public List<LineRow> lineRows { get; private set; }
    public List<NcRow> ncRows { get; private set; }
    public List<NcRow> relevantNcs { get; private set; }
    public List<RecRow> capaRows { get; private set; }
    public List<RecRow> changeOrderRows { get; private set; }
    public List<InspectionRow> inspectionRows { get; private set; }
    public List<InvRow> investigationRows { get; private set; }
    public ComplaintTaskProgress.Summary taskSummary { get; private set; }

    public Boolean getHasLot() {
        return String.isNotBlank(lotNumber);
    }

    public Boolean getHasDateRange() {
        return String.isNotBlank(dateRangeLabel);
    }

    public Boolean getHasError() {
        return String.isNotBlank(errorMessage);
    }

    public Boolean getHasTasks() {
        return taskSummary != null && taskSummary.total > 0;
    }

    public Boolean getHasOverdueTasks() {
        return taskSummary != null && taskSummary.overdueCount > 0;
    }

    public Boolean getHasInvestigations() {
        return !investigationRows.isEmpty();
    }

    public Boolean getHasLotMatchColumn() {
        return String.isNotBlank(lotNumber);
    }

    public Boolean getHasRelevantNcs() {
        return !relevantNcs.isEmpty();
    }

    // ---------- Load ----------

    public ComplaintReportPDFController() {
        hasComplaint = false;
        hasSummary = false;
        hasPrimaryPart = false;
        summaryParagraphs = new List<String>();
        lineRows = new List<LineRow>();
        ncRows = new List<NcRow>();
        relevantNcs = new List<NcRow>();
        capaRows = new List<RecRow>();
        changeOrderRows = new List<RecRow>();
        inspectionRows = new List<InspectionRow>();
        investigationRows = new List<InvRow>();
        taskSummary = ComplaintTaskProgress.summarize(new List<compliancequest__SQX_Complaint_Task__c>(), Date.today());

        Map<String, String> params = ApexPages.currentPage().getParameters();
        renderAs = 'html'.equalsIgnoreCase(params.get('format')) ? null : 'pdf';

        Id complaintId = parseId(params.get('id'));
        if (complaintId == null) {
            errorMessage = 'No complaint was specified for this report.';
            return;
        }
        try {
            load(complaintId, parseDate(params.get('startDate')), parseDate(params.get('endDate')));
        } catch (Exception ex) {
            errorMessage = ex.getMessage();
        }
    }

    private void load(Id complaintId, Date startDate, Date endDate) {
        List<compliancequest__SQX_Complaint__c> complaints = [
            SELECT Name, CreatedDate, compliancequest__Complaint_Title__c, compliancequest__Description__c,
                   compliancequest__Lot_Number__c, Draft_Investigation_Summaries__c
            FROM compliancequest__SQX_Complaint__c
            WHERE Id = :complaintId
            LIMIT 1
        ];
        if (complaints.isEmpty()) {
            errorMessage = 'The complaint was not found.';
            return;
        }
        compliancequest__SQX_Complaint__c complaint = complaints[0];
        hasComplaint = true;
        complaintName = complaint.Name;
        complaintTitle = complaint.compliancequest__Complaint_Title__c;
        complaintCreated = complaint.CreatedDate.format('MMM d, yyyy');

        String summary = complaint.Draft_Investigation_Summaries__c;
        summaryParagraphs = richSummaryToHtml(summary);
        hasSummary = !summaryParagraphs.isEmpty();

        AssociatedItemsReportAction.Request req = new AssociatedItemsReportAction.Request();
        req.targetRecordId = complaintId;
        req.startDate = startDate;
        req.endDate = endDate;
        List<AssociatedItemsReportAction.ActionResponse> out =
            AssociatedItemsReportAction.getAssociatedItemsReport(new List<AssociatedItemsReportAction.Request>{ req });
        AssociatedItemsReportData data = out[0].report;
        if (data.success != true) {
            errorMessage = data.errorMessage;
            return;
        }

        generatedAt = data.generatedAt;
        lotNumber = data.lotNumber;
        dateRangeLabel = data.dateRangeLabel;

        if (data.primaryPart != null) {
            hasPrimaryPart = true;
            partName = data.primaryPart.name;
            partNumber = data.primaryPart.partNumber;
            partType = data.primaryPart.partType;
            partFamily = data.primaryPart.partFamily;
        }

        List<String> asmNames = new List<String>();
        for (AssociatedItemsAssemblyInfo a : data.assemblies) {
            asmNames.add(a.name);
        }
        assemblyNames = String.join(asmNames, ', ');

        for (AssociatedItemsLineItemInfo li : data.assemblyLineItems) {
            LineRow row = new LineRow();
            row.assemblyName = li.assemblyName;
            row.partName = li.partName;
            row.partNumber = li.partNumber;
            row.lotMatch = li.lotMatch;
            row.lotHit = String.isNotBlank(li.lotMatch) && li.lotMatch != 'None';
            lineRows.add(row);
        }
        for (AssociatedItemsInvestigationInfo inv : data.investigations) {
            InvRow row = new InvRow();
            row.name = inv.name;
            row.sourceName = inv.sourceName;
            row.status = inv.status;
            row.matchedBy = inv.matchedBy;
            row.createdDate = inv.createdDate;
            investigationRows.add(row);
        }
        // Tasks are read here, in the same request, because the page is
        // driven entirely by URL parameters.
        taskSummary = ComplaintTaskProgress.getForComplaint(complaintId, AccessLevel.SYSTEM_MODE);
        for (AssociatedItemsRecordInfo r : data.capas) {
            capaRows.add(toRecRow(r));
        }
        for (AssociatedItemsRecordInfo r : data.changeOrders) {
            changeOrderRows.add(toRecRow(r));
        }

        loadNonconformances(data, complaint, summary);
        loadInspections(data);
    }

    private void loadNonconformances(
        AssociatedItemsReportData data,
        compliancequest__SQX_Complaint__c complaint,
        String summary
    ) {
        Map<Id, String> matchedById = new Map<Id, String>();
        for (AssociatedItemsRecordInfo r : data.nonconformances) {
            matchedById.put(r.id, r.matchedBy);
        }
        if (matchedById.isEmpty()) {
            return;
        }

        Set<String> complaintTerms = tokens(complaint.compliancequest__Complaint_Title__c + ' ' + complaint.compliancequest__Description__c);
        String summaryLower = summary == null ? '' : summary.toLowerCase();
        Id primaryPartId = data.primaryPart != null ? data.primaryPart.id : null;

        for (compliancequest__SQX_Nonconformance__c nc : [
            SELECT Id, Name, compliancequest__Status__c, compliancequest__NC_Title__c,
                   compliancequest__Description__c, compliancequest__Lot_Number__c,
                   compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.Name, CreatedDate
            FROM compliancequest__SQX_Nonconformance__c
            WHERE Id IN :matchedById.keySet()
            ORDER BY Name
        ]) {
            String matchedBy = matchedById.get(nc.Id);
            Boolean lotMatch = matchedBy != null && matchedBy.contains('Lot');
            Integer pos = summaryLower.indexOf(nc.Name.toLowerCase());
            Boolean named = pos >= 0;
            List<String> shared = sharedTerms(
                complaintTerms,
                tokens(nc.compliancequest__NC_Title__c + ' ' + nc.compliancequest__Description__c)
            );
            Boolean isOpen = nc.compliancequest__Status__c == 'Open';
            Boolean onPrimary = primaryPartId != null && nc.compliancequest__SQX_Part__c == primaryPartId;

            NcRow row = new NcRow();
            row.name = nc.Name;
            row.title = String.isNotBlank(nc.compliancequest__NC_Title__c) ? nc.compliancequest__NC_Title__c : nc.Name;
            row.status = nc.compliancequest__Status__c;
            row.partName = nc.compliancequest__SQX_Part__r != null ? nc.compliancequest__SQX_Part__r.Name : null;
            row.lotNumber = nc.compliancequest__Lot_Number__c;
            row.matchedBy = matchedBy;
            row.createdDate = nc.CreatedDate.format('MMM d, yyyy');
            row.mentionPos = pos;
            row.score = score(lotMatch, named, shared.size(), isOpen, onPrimary);
            row.qualifies = lotMatch || named || !shared.isEmpty();
            row.why = buildWhy(lotMatch, named, shared, nc.compliancequest__Status__c, onPrimary);
            ncRows.add(row);
        }

        List<NcRow> ranked = new List<NcRow>(ncRows);
        ranked.sort();
        for (NcRow r : ranked) {
            if (r.qualifies && relevantNcs.size() < 3) {
                relevantNcs.add(r);
            }
        }
    }

    private void loadInspections(AssociatedItemsReportData data) {
        Map<Id, String> matchedById = new Map<Id, String>();
        for (AssociatedItemsRecordInfo r : data.inspections) {
            matchedById.put(r.id, r.matchedBy);
        }
        if (matchedById.isEmpty()) {
            return;
        }
        for (compliancequest__SQX_Inspection__c insp : [
            SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__r.Name, CreatedDate
            FROM compliancequest__SQX_Inspection__c
            WHERE Id IN :matchedById.keySet()
            ORDER BY Name
        ]) {
            InspectionRow row = new InspectionRow();
            row.name = insp.Name;
            row.partName = insp.compliancequest__SQX_Part__r != null ? insp.compliancequest__SQX_Part__r.Name : null;
            row.lotNumber = insp.compliancequest__Lot_Number__c;
            row.matchedBy = matchedById.get(insp.Id);
            row.createdDate = insp.CreatedDate.format('MMM d, yyyy');
            inspectionRows.add(row);
        }
    }

    private static RecRow toRecRow(AssociatedItemsRecordInfo r) {
        RecRow row = new RecRow();
        row.name = r.name;
        row.createdDate = r.createdDate;
        return row;
    }

    // ---------- Pure helpers (unit tested directly) ----------

    @TestVisible
    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    @TestVisible
    private static Date parseDate(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Date.valueOf(value);
        } catch (Exception ex) {
            return null;
        }
    }

    /** Rich text field -> one sanitized, XHTML-safe block for the PDF page. */
    @TestVisible
    private static List<String> richSummaryToHtml(String html) {
        List<String> out = new List<String>();
        if (String.isBlank(html)) {
            return out;
        }
        String clean = SummaryRichText.sanitize(html).replace('&nbsp;', '&#160;').trim();
        if (String.isNotBlank(clean.replaceAll('<[^>]*>', '').trim())) {
            out.add(clean);
        }
        return out;
    }

    /**
     * Splits the saved plain-text summary into paragraphs at blank lines,
     * HTML-escapes each one, keeps single line breaks, and bolds record
     * numbers such as COM-0000000001, NC-000067, PHR-000001, CAPA-000000,
     * CHG-000000 and INS-0000000001. The result is safe to output with
     * escape="false" because all text is escaped first.
     */
    @TestVisible
    private static List<String> summaryToHtml(String summary) {
        List<String> paragraphs = new List<String>();
        if (String.isBlank(summary)) {
            return paragraphs;
        }
        String normalized = summary.replace('\r\n', '\n').replace('\r', '\n');
        Pattern recordNumber = Pattern.compile('\\b((?:COM|NC|PHR|CAPA|CHG|INS)-\\d+)\\b');
        for (String raw : normalized.split('\n\\s*\n')) {
            String text = raw.trim();
            if (String.isBlank(text)) {
                continue;
            }
            String html = text.escapeHtml4().replace('\n', '<br/>');
            html = recordNumber.matcher(html).replaceAll('<strong>$1</strong>');
            paragraphs.add(html);
        }
        return paragraphs;
    }

    private static final Set<String> STOP_WORDS = new Set<String>{
        'this', 'that', 'with', 'from', 'have', 'been', 'were', 'will', 'when', 'which',
        'their', 'there', 'than', 'then', 'them', 'into', 'onto', 'about', 'after', 'before',
        'over', 'under', 'also', 'only', 'more', 'most', 'such', 'some', 'these', 'those',
        'other', 'part', 'test', 'testing', 'null', 'keeps', 'back', 'take', 'turn'
    };

    @TestVisible
    private static Set<String> tokens(String text) {
        Set<String> out = new Set<String>();
        if (String.isBlank(text)) {
            return out;
        }
        for (String t : text.toLowerCase().split('[^a-z0-9]+')) {
            if (t.length() >= 4 && !STOP_WORDS.contains(t) && !t.isNumeric()) {
                out.add(t);
            }
        }
        return out;
    }

    @TestVisible
    private static List<String> sharedTerms(Set<String> a, Set<String> b) {
        List<String> hits = new List<String>();
        for (String t : a) {
            if (b.contains(t)) {
                hits.add(t);
            }
        }
        hits.sort();
        return hits;
    }

    @TestVisible
    private static Integer score(Boolean lotMatch, Boolean named, Integer sharedTermCount, Boolean isOpen, Boolean onPrimaryPart) {
        Integer s = 0;
        if (lotMatch) {
            s += 4;
        }
        if (named) {
            s += 3;
        }
        s += Math.min(sharedTermCount, 2);
        if (isOpen) {
            s += 1;
        }
        if (onPrimaryPart) {
            s += 1;
        }
        return s;
    }

    @TestVisible
    private static String buildWhy(Boolean lotMatch, Boolean named, List<String> shared, String status, Boolean onPrimaryPart) {
        List<String> reasons = new List<String>();
        if (lotMatch) {
            reasons.add('Lot number matches the complaint');
        }
        if (named) {
            reasons.add('Named in the investigation summary');
        }
        if (!shared.isEmpty()) {
            List<String> top = new List<String>();
            for (Integer i = 0; i < shared.size() && i < 3; i++) {
                top.add(shared[i]);
            }
            reasons.add('Shares terms with the complaint: ' + String.join(top, ', '));
        }
        if (String.isNotBlank(status)) {
            reasons.add(status);
        }
        if (onPrimaryPart) {
            reasons.add('Filed against the primary part');
        }
        return String.join(reasons, ' · ');
    }
}

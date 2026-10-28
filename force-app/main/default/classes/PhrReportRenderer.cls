/**
 * PhrReportRenderer
 * ------------------
 * Turns PhrReportData into a PDF without a Visualforce page.
 *
 * The layout comes from an XHTML template with {{placeholders}}:
 *   1. the file attached as primary content to the Current controlled document
 *      named in the PHR Report Setting (Template Controlled Document: a Document Number or a record Id;
 *      blank means TEMPLATE_DOC_NUMBER), if it is Current and valid;
 *   2. otherwise the static resource PHR_Report_Default_Template.
 *
 * Sections can be kept or dropped by where the report was run from: see applyConditions.
 *
 * A template is only used if it is well-formed XML both before and after it is filled.
 * Every value is escaped. Only the placeholders listed in buildValues are filled; any other
 * {{word}} is removed. This class does not change any record.
 */
public without sharing class PhrReportRenderer {

    @TestVisible public static String TEMPLATE_DOC_NUMBER = 'PHR-TEMPLATE-001';
    public static final String DEFAULT_RESOURCE = 'PHR_Report_Default_Template';
    /** Used only when the data has no title of its own. */
    public static final String REPORT_TITLE = 'Product History Report';
    /** The note under section 2. */
    public static final String SUMMARY_NOTE = 'Next steps and data gaps only. The records are listed in section 3.';
    public static final String FOOTER_NOTE = 'Records worth reviewing are not confirmed causes.';

    public class Result {
        public Blob pdf;
        public String source;   // where the layout came from
        public String warning;  // set when the controlled document template could not be used
    }

    public static Result render(PhrReportData d) {
        Result res = new Result();
        String custom = null;
        String defaultText = loadDefault();

        TemplateLookup lk = findControlledTemplate();
        res.warning = lk.problem;
        custom = lk.text;

        String html = null;
        if (custom != null) {
            html = fill(custom, d, false);
            if (html == null) { html = fill(custom, d, true); } // retry with the draft summary as plain text
            if (html != null) {
                res.source = 'Controlled document ' + lk.label;
            } else {
                res.warning = 'The controlled document template did not produce valid XML, so the built-in template was used.';
            }
        }
        if (html == null) {
            html = fill(defaultText, d, false);
            if (html == null) { html = fill(defaultText, d, true); }
            if (html == null) { throw new PhrReportException('The built-in report template could not be filled.'); }
            res.source = 'Built-in default template';
        }
        res.pdf = Blob.toPdf(html);
        return res;
    }

    public class PhrReportException extends Exception {}

    // ---------- Template lookup ----------

    public class TemplateLookup {
        public String text;
        public String problem;
        public String label;   // Document Number of the controlled document that was used
    }

    /** The template named in the PHR Report Setting, or the default Document Number when it is blank. */
    @TestVisible
    private static String templateRef() {
        String v = PhrReportSettings.get().templateDocument;
        return String.isBlank(v) ? TEMPLATE_DOC_NUMBER : v.trim();
    }

    /** True when the text is a record Id of a controlled document (rather than a Document Number). */
    @TestVisible
    private static Boolean isControlledDocumentId(String v) {
        if (String.isBlank(v) || (v.length() != 15 && v.length() != 18)) { return false; }
        try {
            return Id.valueOf(v).getSObjectType() == compliancequest__SQX_Controlled_Document__c.SObjectType;
        } catch (Exception ex) {
            return false;
        }
    }

    @TestVisible
    private static TemplateLookup findControlledTemplate() {
        TemplateLookup lk = new TemplateLookup();
        String want = templateRef();
        Boolean chosen = want != TEMPLATE_DOC_NUMBER;
        try {
            List<compliancequest__SQX_Controlled_Document__c> docs;
            if (isControlledDocumentId(want)) {
                docs = [
                    SELECT compliancequest__Document_Number__c, compliancequest__Valid_Content_Reference__c, compliancequest__Content_Reference__c
                    FROM compliancequest__SQX_Controlled_Document__c
                    WHERE Id = :want AND compliancequest__Document_Status__c = 'Current' LIMIT 1
                ];
            } else {
                docs = [
                    SELECT compliancequest__Document_Number__c, compliancequest__Valid_Content_Reference__c, compliancequest__Content_Reference__c
                    FROM compliancequest__SQX_Controlled_Document__c
                    WHERE compliancequest__Document_Number__c = :want
                    AND compliancequest__Document_Status__c = 'Current'
                    ORDER BY CreatedDate DESC LIMIT 1
                ];
            }
            if (docs.isEmpty()) {
                // Not an error when nobody has set one up; a problem when the setting names one that cannot be used.
                if (chosen) { lk.problem = 'The controlled document ' + want + ' named in the PHR Report Setting was not found or is not Current, so the built-in template was used.'; }
                return lk;
            }
            String label = String.isNotBlank(docs[0].compliancequest__Document_Number__c) ? docs[0].compliancequest__Document_Number__c : want;
            String ref = String.isNotBlank(docs[0].compliancequest__Valid_Content_Reference__c)
                ? docs[0].compliancequest__Valid_Content_Reference__c
                : docs[0].compliancequest__Content_Reference__c;
            if (String.isBlank(ref) || !ref.startsWith('069')) {
                lk.problem = 'The controlled document ' + label + ' has no Salesforce file as its primary content, so the built-in template was used.';
                return lk;
            }
            List<ContentVersion> cvs = [
                SELECT VersionData FROM ContentVersion WHERE ContentDocumentId = :ref AND IsLatest = true LIMIT 1
            ];
            if (cvs.isEmpty()) {
                lk.problem = 'The primary content file of ' + label + ' could not be read, so the built-in template was used.';
                return lk;
            }
            String text = cvs[0].VersionData.toString();
            if (!isWellFormed(text) || !text.contains('<html')) {
                lk.problem = 'The template file on ' + label + ' is not valid XHTML, so the built-in template was used.';
                return lk;
            }
            lk.text = text;
            lk.label = label;
        } catch (Exception ex) {
            lk.problem = 'The controlled document template could not be loaded (' + ex.getMessage() + '), so the built-in template was used.';
        }
        return lk;
    }

    private static String loadDefault() {
        List<StaticResource> srs = [SELECT Body FROM StaticResource WHERE Name = :DEFAULT_RESOURCE LIMIT 1];
        if (srs.isEmpty()) { throw new PhrReportException('The default report template (static resource ' + DEFAULT_RESOURCE + ') is missing.'); }
        return srs[0].Body.toString();
    }

    @TestVisible
    private static Boolean isWellFormed(String xml) {
        try {
            Dom.Document doc = new Dom.Document();
            doc.load(xml);
            return doc.getRootElement() != null;
        } catch (Exception ex) {
            return false;
        }
    }

    // ---------- Filling ----------

    /**
     * Conditional sections in a template:
     *   <!--IF:phr--> ... <!--END:phr-->                     kept when run from the complaint or PHR
     *   <!--IF:investigation--> ... <!--END:investigation-->  kept when run from an investigation
     * The markers are removed; the section they wrap is kept or dropped.
     */
    @TestVisible
    private static String applyConditions(String template, PhrReportData d) {
        if (template == null) { return null; }
        String keep = d.investigationMode ? 'investigation' : 'phr';
        String drop = d.investigationMode ? 'phr' : 'investigation';
        String out = template.replaceAll('(?is)<!--\\s*IF:' + drop + '\\s*-->.*?<!--\\s*END:' + drop + '\\s*-->', '');
        out = out.replaceAll('(?i)<!--\\s*(?:IF|END):' + keep + '\\s*-->', '');
        return out;
    }

    /**
     * Brings an older template (such as an earlier PHR-TEMPLATE-001 file) up to date, so it does not have to be
     * revised for these to show:
     *   - the complaint's Report Date in the header, after the complaint number;
     *   - the investigation number in the header when run from an investigation;
     *   - the summary heading: "PHR Summary", or "Investigation Summary" when run from an investigation,
     *     in place of the old fixed "Draft investigation summary" label.
     * A template that already uses these placeholders is left as it is.
     */
    @TestVisible
    private static String upgradeTemplate(String template) {
        if (template == null) { return null; }
        String out = template;
        if (!out.contains('{{reportedDate')) {
            out = out.replaceFirst('\\{\\{complaintName\\}\\}</strong>', '{{complaintName}}</strong>{{reportedDateBlock}}');
        }
        if (!out.contains('{{investigationName')) {
            out = out.replaceFirst('\\{\\{phrBlock\\}\\}', '{{phrBlock}}{{investigationNameBlock}}');
        }
        out = out.replaceAll('(?i)>\\s*Draft investigation summary\\s*<', '>{{summaryHeading}}<');
        // An older template may have the title typed in instead of {{reportTitle}}.
        out = out.replaceAll('(?i)<h1>\\s*Product History Review\\s*</h1>', '<h1>{{reportTitle}}</h1>');
        // Old wording in the summary note and footer.
        out = out.replaceAll('\\{\\{summaryWords\\}\\}\\s*words\\.\\s*Recommendations and gaps only; records are not named here\\.', SUMMARY_NOTE);
        out = out.replaceAll('(?i)Leads are records worth reviewing, not confirmed causes\\.', FOOTER_NOTE);
        // The records worth reviewing always start on a new page (page 2 when the summary fits on page 1).
        if (!out.contains('page-break-before')) {
            out = out.replaceFirst('(?i)<h2>(\\s*3\\.\\s*Top records worth reviewing)', '<h2 style="page-break-before: always;">$1');
        }
        return out;
    }

    /** Returns the filled template, or null if the result is not well-formed. */
    @TestVisible
    private static String fill(String template, PhrReportData d, Boolean plainDraft) {
        Map<String, String> v = buildValues(d, plainDraft);
        String out = applyConditions(upgradeTemplate(template), d);
        for (String k : v.keySet()) {
            out = out.replace('{{' + k + '}}', v.get(k));
        }
        out = out.replaceAll('\\{\\{[A-Za-z0-9_]+\\}\\}', '');
        return isWellFormed(out) ? out : null;
    }

    @TestVisible
    private static Map<String, String> buildValues(PhrReportData d, Boolean plainDraft) {
        Map<String, String> v = new Map<String, String>();
        v.put('reportTitle', esc(String.isBlank(d.reportTitle) ? REPORT_TITLE : d.reportTitle));
        v.put('footerNote', esc(FOOTER_NOTE));
        v.put('generatedAt', esc(d.generatedAt));
        v.put('versionLabel', esc(d.versionLabel));
        v.put('complaintName', esc(d.complaintName));
        v.put('phrName', esc(d.phrName));
        v.put('partLabel', esc(d.partLabel));
        v.put('lotNumber', esc(d.lotNumber));
        v.put('phrBlock', String.isBlank(d.phrName) ? '' : ' &#183; Product History Review <strong>' + esc(d.phrName) + '</strong>');
        v.put('partBlock', String.isBlank(d.partLabel) ? '' : ' &#183; ' + esc(d.partLabel));
        v.put('lotBlock', String.isBlank(d.lotNumber) ? '' : ' &#183; Lot ' + esc(d.lotNumber));
        v.put('reportedDate', esc(d.reportedDate));
        v.put('reportedDateBlock', String.isBlank(d.reportedDate) ? '' : ' &#183; Reported ' + esc(d.reportedDate));
        v.put('summaryHeading', esc(d.summaryHeading));
        v.put('investigationName', esc(d.investigationName));
        v.put('investigationNameBlock', String.isBlank(d.investigationName) ? '' : ' &#183; Investigation <strong>' + esc(d.investigationName) + '</strong>');
        v.put('overallScore', String.valueOf(d.overallScore));
        v.put('overallRating', esc(d.overallRating));
        v.put('ratingClass', esc(d.overallRating == null ? 'none' : d.overallRating.toLowerCase()));
        v.put('summaryText', esc(d.summaryText));
        v.put('summaryWords', String.valueOf(d.summaryWords));
        v.put('errorBlock', String.isBlank(d.errorMessage) ? '' : '<div class="error">' + esc(d.errorMessage) + '</div>');

        v.put('reasonRows', reasonRows(d));
        v.put('draftSummaryHtml', draftHtml(d, plainDraft));
        v.put('draftSummaryBlock', draftBlock(d, plainDraft));
        // Mode-specific copies: each is empty when the report is run from the other kind of record.
        v.put('phrSummaryBlock', d.investigationMode ? '' : draftBlock(d, plainDraft));
        v.put('investigationSummaryBlock', d.investigationMode ? draftBlock(d, plainDraft) : '');
        v.put('leadRows', leadRows(d));
        v.put('leadBlock', leadBlock(d));
        v.put('leadChartBlock', leadChartBlock(d));
        v.put('progressBlock', progressBlock(d));
        v.put('taskRows', taskRows(d));
        v.put('investigationRows', investigationRows(d));
        v.put('investigationBlock', investigationBlock(d));
        v.put('gapRows', gapRows(d));
        v.put('gapBlock', gapBlock(d));

        if (!d.hasComplaint) { // nothing to show but the error message
            for (String k : new List<String>{'reasonRows', 'leadBlock', 'leadChartBlock', 'progressBlock', 'investigationBlock', 'gapBlock', 'draftSummaryBlock', 'phrSummaryBlock', 'investigationSummaryBlock'}) { v.put(k, ''); }
        }
        return v;
    }

    private static String reasonRows(PhrReportData d) {
        if (d.reasons.isEmpty()) { return '<span class="empty">No records worth reviewing to base a rating on.</span>'; }
        String s = '';
        for (String r : d.reasons) { s += '<div>&#8226; ' + esc(r) + '</div>'; }
        return s;
    }

    private static String draftHtml(PhrReportData d, Boolean plain) {
        if (String.isBlank(d.draftSummaryHtml)) { return ''; }
        return plain ? esc(d.draftSummaryHtml.stripHtmlTags()) : d.draftSummaryHtml;
    }

    private static String draftBlock(PhrReportData d, Boolean plain) {
        if (String.isBlank(d.draftSummaryHtml)) {
            if (d.investigationMode) {
                return '<p class="empty">No Investigation Summary has been written on this investigation yet.</p>';
            }
            return '<p class="empty">No PHR Summary has been saved yet. Ask the agent to draft the summary and save it, then run this report again.</p>';
        }
        return '<div class="draft">' + draftHtml(d, plain) + '</div>';
    }

    private static String leadRows(PhrReportData d) {
        String s = '';
        for (PhrReportData.LeadRow r : d.leadRows) {
            s += '<tr>'
                + '<td><table class="chip ' + esc(r.colourClass) + '" style="width: 48px;"><tr><td class="chipcell">' + esc(r.colour) + '</td></tr></table></td>'
                + '<td>' + (r.score == null ? '' : String.valueOf(r.score)) + '</td>'
                + '<td>' + esc(r.recordType) + '</td>'
                + '<td><strong>' + esc(r.name) + '</strong></td>'
                + '<td>' + esc(r.title) + '</td>'
                + '<td>' + esc(r.status) + '</td>'
                + '<td>' + esc(r.createdDate) + '</td>'
                + '<td>' + esc(r.matchedOn) + '</td>'
                + '</tr>';
        }
        return s;
    }

    private static String leadBlock(PhrReportData d) {
        if (d.leadRows.isEmpty()) { return '<p class="empty">No records worth reviewing were found.</p>'; }
        String note = d.totalLeads > d.leadRows.size()
            ? 'Showing the top ' + d.leadRows.size() + ' of ' + d.totalLeads + ' records worth reviewing.'
            : 'Showing ' + d.leadRows.size() + (d.leadRows.size() == 1 ? ' record' : ' records') + ' worth reviewing.';
        return '<table class="grid"><tr><th>Match</th><th>Score</th><th>Type</th><th>Record</th><th>Title</th><th>Status</th><th>Date</th><th>Matched on</th></tr>'
            + leadRows(d) + '</table><div class="note">' + esc(note) + '</div>';
    }

    /** Small bar chart for the "Match breakdown" card: the top records by match colour, and how many are still open. */
    private static String leadChartBlock(PhrReportData d) {
        if (d.leadRows.isEmpty()) { return ''; }
        Map<String, Integer> byColour = new Map<String, Integer>{ 'Red' => 0, 'Yellow' => 0, 'Grey' => 0 };
        Integer open = 0;
        for (PhrReportData.LeadRow r : d.leadRows) {
            String c = String.isBlank(r.colour) ? 'Grey' : r.colour;
            if (!byColour.containsKey(c)) { byColour.put(c, 0); }
            byColour.put(c, byColour.get(c) + 1);
            if (!isClosed(r.status)) { open++; }
        }
        Integer total = d.leadRows.size();
        String s = '<table class="chart"><tr><td>';
        for (String c : new List<String>{ 'Red', 'Yellow', 'Grey' }) {
            s += chartBar(c, 'lbl-' + c.toLowerCase(), 'c-' + c.toLowerCase(), byColour.get(c), total);
        }
        s += '<div class="divider"></div>';
        s += chartBar('Still open', 'lbl-open', 'bar-done', open, total);
        s += '<div class="chartnote">' + d.totalLeads + ' records worth reviewing; the top ' + total
            + ' are listed in section 3.</div>';
        return s + '</td></tr></table>';
    }

    /** One chart row: coloured label, proportional bar, count on the right. */
    private static String chartBar(String label, String labelCls, String barCls, Integer n, Integer total) {
        Integer p = pct(n, total);
        return '<table class="row"><tr><td class="lbl ' + labelCls + '">' + esc(label) + '</td><td><table class="bar"><tr>'
            + (p > 0 ? '<td class="' + barCls + '" style="width: ' + p + '%;"></td>' : '')
            + '<td class="rest"></td></tr></table></td><td class="n">' + n + '</td></tr></table>';
    }

    private static Integer pct(Integer n, Integer total) {
        return total == 0 ? 0 : Integer.valueOf(Math.round(n * 100.0 / total));
    }

    private static Boolean isClosed(String status) {
        if (String.isBlank(status)) { return false; }
        String s = status.toLowerCase();
        return s.contains('closed') || s.contains('complete') || s.contains('cancel') || s.contains('void');
    }

    private static String taskRows(PhrReportData d) {
        String s = '';
        for (ComplaintTaskProgress.TaskRow t : d.taskSummary.rows) {
            s += '<tr>'
                + '<td>' + (t.step == null ? '' : String.valueOf(t.step)) + '</td>'
                + '<td><strong>' + esc(t.taskName) + '</strong></td>'
                + '<td>' + esc(t.linkedRecord) + '</td>'
                + '<td>' + esc(t.assignee) + '</td>'
                + '<td><span class="pill ' + esc(t.statusClass) + '">' + esc(t.status) + '</span></td>'
                + '<td>' + esc(t.startDate) + '</td>'
                + '<td><span class="' + (t.overdue == true ? 'late' : '') + '">' + esc(t.dueDate) + '</span>'
                + (t.overdue == true ? '<div class="late-note">' + esc(t.overdueLabel) + '</div>' : '') + '</td>'
                + '<td>' + esc(String.isBlank(t.completionDate) ? 'Not completed' : t.completionDate) + '</td>'
                + '</tr>';
        }
        return s;
    }

    private static String progressBlock(PhrReportData d) {
        ComplaintTaskProgress.Summary ts = d.taskSummary;
        if (ts == null || ts.total == null || ts.total == 0) {
            return '<p class="empty">No CQ Tasks are recorded on this complaint.</p>';
        }
        String bar = '';
        if (ts.completePct > 0) { bar += '<td class="bar-done" style="width: ' + ts.completePct + '%;"></td>'; }
        if (ts.remainingPct > 0) { bar += '<td class="bar-rest" style="width: ' + ts.remainingPct + '%;"></td>'; }
        String overdue = (ts.overdueCount != null && ts.overdueCount > 0)
            ? '<span class="badge-overdue">' + esc(ts.overdueLabel) + '</span>' : '';
        String pills = '';
        for (ComplaintTaskProgress.StatusCount c : ts.counts) {
            pills += '<span class="pill ' + esc(c.statusClass) + '">' + esc(c.status + ' ' + c.total) + '</span>';
        }
        return '<table class="progress"><tr>'
            + '<td style="width: 150px;"><div class="big">' + esc(ts.progressLabel) + '</div></td>'
            + '<td><table class="bar"><tr>' + bar + '</tr></table></td>'
            + '<td style="width: 110px; text-align: right;">' + overdue + '</td>'
            + '</tr></table>'
            + '<div style="margin-top: 6px;">' + pills + '</div>'
            + '<h3>Tasks on this complaint (' + ts.total + ')</h3>'
            + '<table class="grid"><tr><th>Step</th><th>Task</th><th>Linked record</th><th>Assignee</th><th>Status</th><th>Started</th><th>Due</th><th>Completed</th></tr>'
            + taskRows(d) + '</table>';
    }

    private static String investigationRows(PhrReportData d) {
        String s = '';
        for (PhrReportData.InvRow r : d.investigationRows) {
            s += '<tr><td><strong>' + esc(r.name) + '</strong></td><td>' + esc(r.status) + '</td><td>' + esc(r.matchedBy) + '</td><td>' + esc(r.createdDate) + '</td></tr>';
        }
        return s;
    }

    private static String investigationBlock(PhrReportData d) {
        if (d.investigationRows.isEmpty()) { return ''; }
        return '<h2>5. Related investigations</h2><table class="grid"><tr><th>Investigation</th><th>Status</th><th>Why related</th><th>Created</th></tr>'
            + investigationRows(d) + '</table>';
    }

    private static String gapRows(PhrReportData d) {
        String s = '';
        for (String g : d.gaps) { s += '<div>&#8226; ' + esc(g) + '</div>'; }
        return s;
    }

    private static String gapBlock(PhrReportData d) {
        if (d.gaps.isEmpty()) { return '<p class="empty">No data gaps were found.</p>'; }
        return '<div class="gap"><strong>Scored without:</strong>' + gapRows(d) + '</div>';
    }

    /** XML-safe text. Not escapeHtml4, which can emit named entities the PDF engine does not know. */
    @TestVisible
    private static String esc(String s) {
        if (s == null) { return ''; }
        return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;').replace('"', '&quot;').replace('\'', '&#39;');
    }
}

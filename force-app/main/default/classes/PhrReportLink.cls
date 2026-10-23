/**
 * Links the Product History Review Report PDF (the file PhrTemplateReportAction attaches to the complaint)
 * to the PHR Summary (complaint and PHR) and shares the same file with the complaint's primary investigation.
 *
 * - withReportLink(): adds (or refreshes) one line at the end of a summary:
 *       Attached report: Product History Review Report   (a link to the file)
 *   so the link travels with the summary when it is copied to the investigation.
 * - shareWithInvestigations(): shares the report file with the complaint's primary investigation (only that one),
 *   so the link opens for their users and the PDF shows under the investigation's Files. It is the same file,
 *   so a newer report version shows there automatically.
 * - afterReportGenerated(): called by PhrTemplateReportAction after a report is created. Shares the file and adds
 *   the link line to the complaint's draft summary and the primary investigation's summary when they have text and no link yet.
 *
 * Nothing here ever stops a summary save or a report: problems are reported back as text.
 */
public with sharing class PhrReportLink {

    /** Default title; the PHR Report Setting (PHR Report Title) can change it. */
    public static final String REPORT_TITLE = PhrReportSettings.DEFAULT_PHR_TITLE;
    /** The file's earlier name; files with it are still found, and renamed on their next version. */
    public static final String OLD_REPORT_TITLE = PhrReportSettings.OLDEST_PHR_TITLE;
    @TestVisible static final String LINE_LABEL = 'Attached report:';
    /** Tests set this to stand in for the complaint's primary investigation (CQ's scope rules block setting one in test data). */
    @TestVisible static Id testPrimaryInvestigationId;
    static final Pattern LINK_LINE = Pattern.compile('(?is)\\s*<p>\\s*<strong>\\s*Attached report:\\s*</strong>.*?</p>');

    /** ContentDocument Id of the report attached to the complaint, or null. */
    public static Id reportDocumentId(Id complaintId) {
        if (complaintId == null) { return null; }
        List<String> titles = PhrReportSettings.phrTitles();
        for (ContentDocumentLink l : [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :complaintId AND ContentDocument.Title IN :titles
            ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
        ]) {
            return l.ContentDocumentId;
        }
        return null;
    }

    /** Removes any existing report line and, when the complaint has a report, appends a fresh one. */
    public static String withReportLink(Id complaintId, String html) {
        String base = stripLink(html);
        Id docId;
        try { docId = reportDocumentId(complaintId); } catch (Exception e) { docId = null; }
        if (docId == null) { return base; }
        return (base == null ? '' : base) + line(docId);
    }

    @TestVisible
    static String stripLink(String html) {
        if (html == null) { return null; }
        return LINK_LINE.matcher(html).replaceAll('');
    }

    @TestVisible
    static Boolean hasLink(String html) {
        return html != null && LINK_LINE.matcher(html).find();
    }

    @TestVisible
    static String line(Id docId) {
        return '<p><strong>' + LINE_LABEL + '</strong> <a href="/lightning/r/ContentDocument/' + docId
            + '/view" target="_blank">' + PhrReportSettings.phrTitle().replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;') + '</a></p>';
    }

    /** The complaint's primary investigation, as a set (empty when none is set). Other linked investigations are not used. */
    public static Set<Id> investigationIds(Id complaintId) {
        Set<Id> ids = new Set<Id>();
        if (complaintId == null) { return ids; }
        if (testPrimaryInvestigationId != null) { ids.add(testPrimaryInvestigationId); return ids; }
        for (compliancequest__SQX_Complaint__c c : [
            SELECT compliancequest__SQX_Primary_Investigation__c FROM compliancequest__SQX_Complaint__c
            WHERE Id = :complaintId
            WITH USER_MODE
        ]) {
            if (c.compliancequest__SQX_Primary_Investigation__c != null) { ids.add(c.compliancequest__SQX_Primary_Investigation__c); }
        }
        return ids;
    }

    /** Shares the report with the complaint's investigations. Returns a short sentence for the user ('' when nothing to do). */
    public static String shareWithInvestigations(Id complaintId) {
        try {
            Id docId = reportDocumentId(complaintId);
            if (docId == null) { return ''; }
            Set<Id> invIds = investigationIds(complaintId);
            if (invIds.isEmpty()) { return ''; }
            for (ContentDocumentLink l : [
                SELECT LinkedEntityId FROM ContentDocumentLink
                WHERE ContentDocumentId = :docId AND LinkedEntityId IN :invIds
            ]) {
                invIds.remove(l.LinkedEntityId);
            }
            if (invIds.isEmpty()) { return ' The report was already shared with the primary investigation.'; }
            List<ContentDocumentLink> links = new List<ContentDocumentLink>();
            for (Id invId : invIds) {
                links.add(new ContentDocumentLink(
                    ContentDocumentId = docId, LinkedEntityId = invId, ShareType = 'V', Visibility = 'AllUsers'));
            }
            Integer ok = 0;
            List<String> problems = new List<String>();
            List<Database.SaveResult> rs = Database.insert(links, false);
            for (Database.SaveResult r : rs) {
                if (r.isSuccess()) { ok++; } else { for (Database.Error e : r.getErrors()) { problems.add(e.getMessage()); } }
            }
            String msg = ok > 0 ? ' The report was shared with the primary investigation.' : '';
            if (!problems.isEmpty()) { msg += ' The report could not be shared: ' + String.join(problems, '; '); }
            return msg;
        } catch (Exception e) {
            return ' The report could not be shared with the investigation: ' + e.getMessage();
        }
    }

    /** After a new report: share it and add the link line where a summary has text but no link yet. */
    public static String afterReportGenerated(Id complaintId) {
        String msg = shareWithInvestigations(complaintId);
        try {
            Id docId = reportDocumentId(complaintId);
            if (docId == null) { return msg; }
            Integer updated = 0;

            List<compliancequest__SQX_Complaint__c> cs = [
                SELECT Id, Draft_Investigation_Summaries__c FROM compliancequest__SQX_Complaint__c
                WHERE Id = :complaintId WITH USER_MODE LIMIT 1
            ];
            if (!cs.isEmpty() && !String.isBlank(cs[0].Draft_Investigation_Summaries__c)
                    && !hasLink(cs[0].Draft_Investigation_Summaries__c)) {
                Database.update(new compliancequest__SQX_Complaint__c(
                    Id = complaintId,
                    Draft_Investigation_Summaries__c = cs[0].Draft_Investigation_Summaries__c + line(docId)
                ), true, AccessLevel.USER_MODE);
                updated++;
            }

            Id phrId = PhrRecordContext.phrIdFor(complaintId);
            if (phrId != null) {
                for (compliancequest__SQX_Product_History_Review__c p : [
                    SELECT compliancequest__Product_History_Review_Summary__c FROM compliancequest__SQX_Product_History_Review__c
                    WHERE Id = :phrId WITH USER_MODE LIMIT 1
                ]) {
                    String s = p.compliancequest__Product_History_Review_Summary__c;
                    if (!String.isBlank(s) && !hasLink(s)) {
                        Database.SaveResult sr = Database.update(new compliancequest__SQX_Product_History_Review__c(
                            Id = phrId, compliancequest__Product_History_Review_Summary__c = s + line(docId)), false, AccessLevel.USER_MODE);
                        if (sr.isSuccess()) { updated++; }
                    }
                }
            }

            Set<Id> invIds = investigationIds(complaintId);
            if (!invIds.isEmpty()) {
                List<compliancequest__SQX_Investigation__c> invUpdates = new List<compliancequest__SQX_Investigation__c>();
                for (compliancequest__SQX_Investigation__c inv : [
                    SELECT Id, compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c
                    WHERE Id IN :invIds WITH USER_MODE
                ]) {
                    if (!String.isBlank(inv.compliancequest__Investigation_Summary__c)
                            && !hasLink(inv.compliancequest__Investigation_Summary__c)) {
                        invUpdates.add(new compliancequest__SQX_Investigation__c(
                            Id = inv.Id,
                            compliancequest__Investigation_Summary__c = inv.compliancequest__Investigation_Summary__c + line(docId)));
                    }
                }
                if (!invUpdates.isEmpty()) {
                    Database.update(invUpdates, false, AccessLevel.USER_MODE);
                    updated += invUpdates.size();
                }
            }
            if (updated > 0) { msg += ' A link to the report was added to the summary.'; }
        } catch (Exception e) {
            msg += ' The link to the report could not be added to the summary: ' + e.getMessage();
        }
        return msg;
    }
}

/**
 * PhrTemplateReportAction
 * ------------------------
 * Builds the Product History Review report from a template (no Visualforce page) and
 * attaches it to the Complaint as a PDF. This is an ADDITION to PhrLeadReportAction
 * (the Interim Report), which is unchanged.
 *
 * Uses its own file title, so it never touches the Interim Report file. The first run
 * attaches a new file; every later run adds a version to that same file.
 */
global with sharing class PhrTemplateReportAction {

    /** Run from a complaint or PHR: one file on the complaint, a new version each run. */
    @TestVisible private static final String FILE_TITLE = PhrReportLink.REPORT_TITLE;
    @TestVisible private static final String OLD_FILE_TITLE = PhrReportLink.OLD_REPORT_TITLE;
    /** Run from an investigation: a separate file on the investigation (also shown on the complaint). */
    @TestVisible private static final String CUSTOMER_FILE_TITLE = 'Customer Report';

    global class Request {
        @InvocableVariable(label='Complaint, PHR or Investigation Id' description='The record the agent is open on: the Complaint, its Product History Review, or an Investigation. The PDF is attached to the Complaint (and to the Investigation when run from one).' required=true)
        global Id recordId;
    }

    global class Response {
        @InvocableVariable(label='Success') global Boolean success;
        @InvocableVariable(label='Message' description='Plain-language result for the user.') global String message;
        @InvocableVariable(label='Version' description='Version number of the report file.') global Integer version;
        @InvocableVariable(label='ContentDocument Id') global Id contentDocumentId;
        @InvocableVariable(label='Template used' description='Which template produced the layout: the controlled document or the built-in default.') global String templateSource;
    }

    @InvocableMethod(
        label='Generate Product History Report PDF'
        description='Run from a Complaint or its Product History Review: builds the Product History Report (overall significance, short summary, PHR Summary, top records worth reviewing, task progress, related investigations, data gaps) and attaches it to the Complaint as a PDF. Run from an Investigation: builds the Customer Report with the Investigation Summary and attaches it to the Investigation and the Complaint. Running it again adds a new version of the same file.'
    )
    global static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(generate(req));
        }
        return out;
    }

    private static Response generate(Request req) {
        Response res = new Response();
        try {
            if (req == null || req.recordId == null) {
                res.success = false;
                res.message = 'I could not tell which complaint to report on.';
                return res;
            }
            Id complaintId = resolveComplaint(req.recordId);
            if (complaintId == null) {
                res.success = false;
                res.message = 'I could not find the complaint for this record.';
                return res;
            }

            Id investigationId = PhrRecordContext.isInvestigation(req.recordId) ? req.recordId : null;
            // Titles come from the PHR Report Setting (PHR Report Title / Investigation Report Title).
            String title = investigationId == null ? PhrReportSettings.phrTitle() : PhrReportSettings.investigationTitle();
            Id docId = investigationId == null
                ? findExistingDocument(complaintId)
                : findDocument(investigationId, PhrReportSettings.investigationTitles());
            Integer next = docId == null ? 1 : nextVersion(docId);

            PhrReportData data = PhrReportData.build(complaintId, String.valueOf(next), investigationId);
            if (!data.hasComplaint) {
                res.success = false;
                res.message = 'I could not create the report: ' + data.errorMessage;
                return res;
            }
            PhrReportRenderer.Result rendered = PhrReportRenderer.render(data);

            ContentVersion cv = new ContentVersion();
            cv.Title = title;
            cv.PathOnClient = title.replace(' ', '_') + '.pdf';
            cv.VersionData = rendered.pdf;
            if (docId == null) {
                cv.FirstPublishLocationId = investigationId == null ? complaintId : investigationId;
            } else {
                cv.ContentDocumentId = docId;
            }
            insert cv;

            res.success = true;
            res.version = next;
            res.templateSource = rendered.source;
            res.contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            String note = String.isBlank(rendered.warning) ? '' : ' Note: ' + rendered.warning;
            String fresh = ' It uses the information in the org right now, so you can run it again later for an updated version.';
            if (investigationId == null) {
                res.message = (next == 1
                    ? 'I attached the ' + title + ' to the complaint as a new file.'
                    : 'I added version ' + next + ' to the ' + title + ' on the complaint.')
                    + ' It shows the PHR Summary.' + fresh + note
                    + PhrReportLink.afterReportGenerated(complaintId);
            } else {
                String invLabel = String.isBlank(data.investigationName) ? 'the investigation' : data.investigationName;
                res.message = (next == 1
                    ? 'I attached the ' + title + ' to ' + invLabel + ' as a new file.'
                    : 'I added version ' + next + ' to the ' + title + ' on ' + invLabel + '.')
                    + ' It shows the Investigation Summary.'
                    + alsoOnComplaint(res.contentDocumentId, complaintId) + fresh + note;
            }
        } catch (Exception ex) {
            res.success = false;
            res.message = 'I could not create the report: ' + ex.getMessage();
        }
        return res;
    }

    /** Makes the Customer Report show on the complaint too (the same file, so it always shows the latest version). */
    @TestVisible
    private static String alsoOnComplaint(Id docId, Id complaintId) {
        try {
            if ([SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :docId AND LinkedEntityId = :complaintId] > 0) {
                return ' The same file is on the complaint, so it shows this version too.';
            }
            insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = complaintId, ShareType = 'V', Visibility = 'AllUsers');
            return ' I also attached it to the complaint.';
        } catch (Exception ex) {
            return ' It could not be attached to the complaint: ' + ex.getMessage();
        }
    }

    /** The Product History Report on the complaint (also finds it under its earlier name). */
    @TestVisible
    private static Id findExistingDocument(Id complaintId) {
        return findDocument(complaintId, PhrReportSettings.phrTitles());
    }

    @TestVisible
    private static Id findDocument(Id recordId, List<String> titles) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :recordId AND ContentDocument.Title IN :titles
            ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocumentId;
    }

    @TestVisible
    private static Integer nextVersion(Id docId) {
        return [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :docId] + 1;
    }

    /** Accepts a Complaint Id, or a Product History Review Id and returns its Complaint. */
    @TestVisible
    private static Id resolveComplaint(Id recordId) {
        return PhrRecordContext.complaintIdFor(recordId);
    }
}

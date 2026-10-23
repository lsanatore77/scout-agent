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

    @TestVisible private static final String FILE_TITLE = 'Product History Review Report';

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
        label='Generate Product History Review Report PDF'
        description='Builds the Product History Review report from the report template (overall significance, short summary, the PHR Summary - or the Investigation Summary when run from an investigation - top records worth reviewing, task progress, related investigations, data gaps) and attaches it to the Complaint as a PDF, and to the Investigation when run from one. Running it again adds a new version of the same file.'
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

            Id docId = findExistingDocument(complaintId);
            Integer next = docId == null ? 1 : nextVersion(docId);

            Id investigationId = PhrRecordContext.isInvestigation(req.recordId) ? req.recordId : null;
            PhrReportData data = PhrReportData.build(complaintId, String.valueOf(next), investigationId);
            if (!data.hasComplaint) {
                res.success = false;
                res.message = 'I could not create the report: ' + data.errorMessage;
                return res;
            }
            PhrReportRenderer.Result rendered = PhrReportRenderer.render(data);

            ContentVersion cv = new ContentVersion();
            cv.Title = FILE_TITLE;
            cv.PathOnClient = FILE_TITLE.replace(' ', '_') + '.pdf';
            cv.VersionData = rendered.pdf;
            if (docId == null) {
                cv.FirstPublishLocationId = complaintId;
            } else {
                cv.ContentDocumentId = docId;
            }
            insert cv;

            res.success = true;
            res.version = next;
            res.templateSource = rendered.source;
            res.contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            String onInvestigation = investigationId == null ? '' : attachToInvestigation(res.contentDocumentId, investigationId, data.investigationName);
            res.message = (next == 1
                ? 'I attached the report to the complaint as a new file.'
                : 'I added version ' + next + ' to the report already attached to the complaint.')
                + (investigationId == null
                    ? ' It shows the PHR Summary.'
                    : ' It shows the Investigation Summary of ' + (String.isBlank(data.investigationName) ? 'this investigation' : data.investigationName) + '.' + onInvestigation)
                + ' It uses the information in the org right now, so you can run it again later for an updated version.'
                + (String.isBlank(rendered.warning) ? '' : ' Note: ' + rendered.warning)
                + PhrReportLink.afterReportGenerated(complaintId);
        } catch (Exception ex) {
            res.success = false;
            res.message = 'I could not create the report: ' + ex.getMessage();
        }
        return res;
    }

    /** Makes the same report file show on the investigation too (one file, so both records always show the latest version). */
    @TestVisible
    private static String attachToInvestigation(Id docId, Id investigationId, String invName) {
        String label = String.isBlank(invName) ? 'the investigation' : invName;
        try {
            if ([SELECT COUNT() FROM ContentDocumentLink WHERE ContentDocumentId = :docId AND LinkedEntityId = :investigationId] > 0) {
                return ' The same file is on ' + label + ', so it shows this version too.';
            }
            insert new ContentDocumentLink(ContentDocumentId = docId, LinkedEntityId = investigationId, ShareType = 'V', Visibility = 'AllUsers');
            return ' I also attached it to ' + label + '.';
        } catch (Exception ex) {
            return ' It could not be attached to ' + label + ': ' + ex.getMessage();
        }
    }

    @TestVisible
    private static Id findExistingDocument(Id complaintId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :complaintId AND ContentDocument.Title = :FILE_TITLE
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

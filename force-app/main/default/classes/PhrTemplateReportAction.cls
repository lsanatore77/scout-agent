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
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) the report is for. The PDF is attached to the Complaint.' required=true)
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
        description='Builds the Product History Review report from the report template (overall significance, short summary, draft investigation summary, top records worth reviewing, task progress, related investigations, data gaps) and attaches it to the Complaint as a PDF. Running it again adds a new version of the same file.'
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

            PhrReportData data = PhrReportData.build(complaintId, String.valueOf(next));
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
            res.message = (next == 1
                ? 'I attached the report to the complaint as a new file.'
                : 'I added version ' + next + ' to the report already attached to the complaint.')
                + ' It uses the information in the org right now, so you can run it again later for an updated version.'
                + (String.isBlank(rendered.warning) ? '' : ' Note: ' + rendered.warning)
                + PhrReportLink.afterReportGenerated(complaintId);
        } catch (Exception ex) {
            res.success = false;
            res.message = 'I could not create the report: ' + ex.getMessage();
        }
        return res;
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
        String t = String.valueOf(recordId.getSobjectType());
        if (t == 'compliancequest__SQX_Complaint__c') { return recordId; }
        if (t == 'compliancequest__SQX_Product_History_Review__c') {
            List<compliancequest__SQX_Product_History_Review__c> p = [
                SELECT compliancequest__SQX_Complaint__c FROM compliancequest__SQX_Product_History_Review__c
                WHERE Id = :recordId LIMIT 1
            ];
            return p.isEmpty() ? null : p[0].compliancequest__SQX_Complaint__c;
        }
        return null;
    }
}

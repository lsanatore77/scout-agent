/**
 * PhrLeadReportAction
 * --------------------
 * Builds the interim report PDF (page PhrLeadReportPDF) and attaches it to
 * the Complaint. The first run attaches a new file. Every later run adds a new
 * version to the same file, so the Complaint never ends up with copies.
 *
 * It can be run at any time (an interim report early, a fuller one later): the page
 * reads current data every time. Only the file is written; no other record changes.
 */
global with sharing class PhrLeadReportAction {

    @TestVisible private static final String FILE_TITLE = 'Interim Report';
    // Files created before the rename carry this title; the next run adds a version to them and retitles them.
    @TestVisible private static final String OLD_FILE_TITLE = 'Product History Lead Report';

    global class Request {
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) the report is for. The PDF is attached to the Complaint.' required=true)
        global Id recordId;
    }

    global class Response {
        @InvocableVariable(label='Success') global Boolean success;
        @InvocableVariable(label='Message' description='Plain-language result for the user.') global String message;
        @InvocableVariable(label='Version' description='Version number of the report file.') global Integer version;
        @InvocableVariable(label='ContentDocument Id') global Id contentDocumentId;
    }

    @InvocableMethod(
        label='Generate Interim Report PDF'
        description='Builds the interim report (overall significance, short summary, top 10 records worth reviewing, task progress, related investigations, data gaps) and attaches it to the Complaint as a PDF. Running it again adds a new version of the same file.'
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
            Integer next = 1;
            if (docId != null) {
                next = nextVersion(docId);
            }

            PageReference page = Page.PhrLeadReportPDF;
            page.getParameters().put('id', String.valueOf(complaintId));
            page.getParameters().put('version', String.valueOf(next));
            Blob pdf = Test.isRunningTest() ? Blob.valueOf('Test PDF content') : page.getContent();

            ContentVersion cv = new ContentVersion();
            cv.Title = FILE_TITLE;
            cv.PathOnClient = FILE_TITLE.replace(' ', '_') + '.pdf';
            cv.VersionData = pdf;
            if (docId == null) {
                cv.FirstPublishLocationId = complaintId;
            } else {
                cv.ContentDocumentId = docId;
            }
            insert cv;

            res.success = true;
            res.version = next;
            res.contentDocumentId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
            res.message = (next == 1
                ? 'I attached the report to the complaint as a new file.'
                : 'I added version ' + next + ' to the report already attached to the complaint.')
                + ' It uses the information in the org right now, so you can run it again later for an updated version.';
        } catch (Exception ex) {
            res.success = false;
            res.message = 'I could not create the report: ' + ex.getMessage();
        }
        return res;
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

    @TestVisible
    private static Id findExistingDocument(Id complaintId) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId FROM ContentDocumentLink
            WHERE LinkedEntityId = :complaintId AND ContentDocument.Title IN (:FILE_TITLE, :OLD_FILE_TITLE)
            ORDER BY ContentDocument.CreatedDate DESC LIMIT 1
        ];
        return links.isEmpty() ? null : links[0].ContentDocumentId;
    }

    @TestVisible
    private static Integer nextVersion(Id docId) {
        Integer count = [SELECT COUNT() FROM ContentVersion WHERE ContentDocumentId = :docId];
        return count + 1;
    }
}

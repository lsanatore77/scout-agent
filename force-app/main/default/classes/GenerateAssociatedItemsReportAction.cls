/**
 * GenerateAssociatedItemsReportAction
 * ------------------------------------
 * Flow-callable action: renders the Complaint Investigation Report PDF
 * (saved Draft Investigation Summary + associated items) and attaches it to
 * the target Complaint.
 *
 * The page (ComplaintInvestigationReportPDF) loads all of its own data from
 * the Complaint Id passed as a URL parameter. Earlier versions of this action
 * filled static variables on a controller and then called getContent(), but
 * getContent() renders the page in a separate request that does not see
 * those statics, so the PDF came out empty.
 *
 * The Request keeps every input the existing Flow already passes
 * (Nonconformance/CAPA/Change Order/Inspection Ids and Primary Part Id) so
 * the Flow does not need to change; those lists are no longer used because
 * the report resolves related records itself. Start Date and End Date are
 * new, optional inputs.
 */
public without sharing class GenerateAssociatedItemsReportAction {

    public class ReportException extends Exception {}

    public class Request {
        @InvocableVariable(label='Target Record Id' description='The Complaint to report on. The PDF is attached to this record.' required=true)
        public Id targetRecordId;

        @InvocableVariable(label='Report Title' required=false)
        public String reportTitle;

        @InvocableVariable(label='Start Date' description='Optional. Only include related records created on or after this date.' required=false)
        public Date startDate;

        @InvocableVariable(label='End Date' description='Optional. Only include related records created on or before this date.' required=false)
        public Date endDate;

        // ---- Retained so existing Flows keep working; no longer used. ----
        @InvocableVariable(label='Nonconformance Ids' description='No longer used. Related records are resolved from the Complaint.' required=false)
        public List<Id> nonconformanceIds;

        @InvocableVariable(label='CAPA Ids' description='No longer used. Related records are resolved from the Complaint.' required=false)
        public List<Id> capaIds;

        @InvocableVariable(label='Change Order Ids' description='No longer used. Related records are resolved from the Complaint.' required=false)
        public List<Id> changeOrderIds;

        @InvocableVariable(label='Inspection Ids' description='No longer used. Related records are resolved from the Complaint.' required=false)
        public List<Id> inspectionIds;

        @InvocableVariable(label='Primary Part Id' description='No longer used. The Primary Part is resolved from the Complaint.' required=false)
        public Id primaryPartId;
    }

    public class Response {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='ContentDocument Id')
        public Id contentDocumentId;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    @InvocableMethod(label='Generate Associated Items Report PDF' description='Builds the Complaint Investigation Report PDF (saved Draft Investigation Summary plus associated items) and attaches it to the Complaint')
    public static List<Response> generateReport(List<Request> requests) {
        List<Response> results = new List<Response>();

        for (Request req : requests) {
            Response res = new Response();
            try {
                if (req.targetRecordId == null) {
                    throw new ReportException('Target Record Id is required.');
                }

                PageReference reportPage = Page.ComplaintInvestigationReportPDF;
                reportPage.getParameters().put('id', String.valueOf(req.targetRecordId));
                if (req.startDate != null) {
                    reportPage.getParameters().put('startDate', String.valueOf(req.startDate));
                }
                if (req.endDate != null) {
                    reportPage.getParameters().put('endDate', String.valueOf(req.endDate));
                }

                Blob pdfBlob;
                if (Test.isRunningTest()) {
                    // getContent() on a PDF-rendered page isn't supported in
                    // test execution; use a placeholder so tests can still
                    // exercise the ContentVersion creation logic.
                    pdfBlob = Blob.valueOf('Test PDF content');
                } else {
                    pdfBlob = reportPage.getContent();
                }

                ContentVersion cv = new ContentVersion();
                cv.Title = String.isNotBlank(req.reportTitle) ? req.reportTitle : 'Complaint Investigation Report';
                cv.PathOnClient = cv.Title.replace(' ', '_') + '.pdf';
                cv.VersionData = pdfBlob;
                // Setting FirstPublishLocationId attaches the file directly
                // to the target record's Files related list in one step.
                cv.FirstPublishLocationId = req.targetRecordId;
                insert cv;

                ContentVersion inserted = [
                    SELECT ContentDocumentId
                    FROM ContentVersion
                    WHERE Id = :cv.Id
                    LIMIT 1
                ];

                res.success = true;
                res.contentDocumentId = inserted.ContentDocumentId;
            } catch (Exception ex) {
                res.success = false;
                res.errorMessage = ex.getMessage();
            }
            results.add(res);
        }
        return results;
    }
}

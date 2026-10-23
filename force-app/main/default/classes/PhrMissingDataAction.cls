/**
 * PhrMissingDataAction
 * ---------------------
 * Invocable action for the reviewer persona (Draft stage). Checks a Complaint, its
 * part and lot, and its Product History Review for gaps and returns one line per
 * check, each a warning or a tick with a one-line explanation, as typed data for the
 * phrMissingDataType renderer.
 *
 * Read only: it writes nothing and sends nothing.
 *
 * Checks (design section 4):
 *   1 lot number on the complaint
 *   2 part on the complaint
 *   3 Product History Review exists
 *   4 PHR is not a draft with Completed By empty
 *   5 linked investigations have a summary
 *      (the investigation has no title field, so the summary is checked instead)
 *   6 the complaint description: details it mentions (lot or serial, part, catalog or model number,
 *     a date, a quantity, a patient or injury) that are missing from, or differ from, the complaint fields.
 *     See PhrDescriptionCheck. These are suggestions only.
 *
 * The checklist is not checked here: it is filled in at a later step of the workflow.
 */
global with sharing class PhrMissingDataAction {

    @TestVisible private static final String WARN = 'warn';
    @TestVisible private static final String OK = 'ok';

    global class Request {
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review, CQ Task or Investigation) currently open in the conversation.' required=true)
        global Id recordId;
    }

    global class ActionResponse {
        @InvocableVariable(label='Missing Data Check' description='One line per check, each a warning or a tick with a one-line explanation.')
        global PhrMissingDataResult result;
    }

    @InvocableMethod(
        label='Find Missing Data'
        description='Checks a Complaint, its part and lot, and its Product History Review for gaps (no lot, no part, no review, draft review with Completed By empty, linked investigations with no summary), and reads the complaint description for details it mentions that are missing from the complaint (lot or serial, part, catalog or model number, date, quantity, patient or injury). Returns one line per check as a warning or a tick. Read only: it creates and changes nothing.'
    )
    global static List<ActionResponse> run(List<Request> requests) {
        List<ActionResponse> out = new List<ActionResponse>();
        for (Request req : requests) {
            ActionResponse r = new ActionResponse();
            r.result = check(req == null ? null : req.recordId);
            out.add(r);
        }
        return out;
    }

    @TestVisible
    private static PhrMissingDataResult check(Id recordId) {
        PhrMissingDataResult res = new PhrMissingDataResult();
        try {
            if (recordId == null) {
                return fail(res, 'I could not tell which complaint to check.');
            }
            Id complaintId = PhrRecordContext.complaintIdFor(recordId);
            if (complaintId == null) {
                return fail(res, 'I could not find the complaint for this record.');
            }
            List<compliancequest__SQX_Complaint__c> cs = [
                SELECT Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c,
                       compliancequest__SQX_Lot_Info__r.compliancequest__Manufacturing_Date__c,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__SQX_Part__r.Name,
                       compliancequest__Catalog_Number__c, compliancequest__Model_Name__c,
                       compliancequest__Occurrence_Date__c, compliancequest__Complaint_Quantity__c,
                       compliancequest__SQX_Patient_Data__c, compliancequest__Description__c,
                       compliancequest__Description_As_Reported__c
                FROM compliancequest__SQX_Complaint__c WHERE Id = :complaintId LIMIT 1
            ];
            if (cs.isEmpty()) {
                return fail(res, 'I could not find the complaint for this record.');
            }
            compliancequest__SQX_Complaint__c c = cs[0];

            res.checks.add(String.isBlank(c.compliancequest__Lot_Number__c)
                ? line('Lot number', WARN, 'No lot number on the complaint, so records are ranked by part only.')
                : line('Lot number', OK, 'Lot ' + c.compliancequest__Lot_Number__c + ' is on the complaint.'));

            res.checks.add(c.compliancequest__SQX_Part__c == null
                ? line('Part', WARN, 'No part on the complaint, so no related records can be found.')
                : line('Part', OK, 'A part is on the complaint.'));

            // Only when the optional manufacture date window is turned on.
            if (PhrReportSettings.get().useWindow) {
                Boolean hasDate = c.compliancequest__SQX_Lot_Info__r != null
                    && c.compliancequest__SQX_Lot_Info__r.compliancequest__Manufacturing_Date__c != null;
                res.checks.add(hasDate
                    ? line('Manufacture date window', OK, 'The Lot Info manufactured date is set, so the date window is applied.')
                    : line('Manufacture date window', WARN, 'The date window is on, but the complaint has no Lot Info with a manufactured date, so it was not applied.'));
            }

            List<compliancequest__SQX_Product_History_Review__c> phrs = [
                SELECT Id, compliancequest__Status__c, compliancequest__Completed_By__c
                FROM compliancequest__SQX_Product_History_Review__c
                WHERE compliancequest__SQX_Complaint__c = :complaintId ORDER BY CreatedDate LIMIT 1
            ];
            if (phrs.isEmpty()) {
                res.checks.add(line('Product History Review', WARN, 'There is no Product History Review yet, so records cannot be added.'));
                res.checks.add(line('Review status', WARN, 'Not checked: there is no Product History Review.'));
            } else {
                compliancequest__SQX_Product_History_Review__c phr = phrs[0];
                res.checks.add(line('Product History Review', OK, 'A Product History Review exists.'));
                res.checks.add(phr.compliancequest__Status__c == 'Draft' && String.isBlank(phr.compliancequest__Completed_By__c)
                    ? line('Review status', WARN, 'The review is a draft and Completed By is empty. Next step: complete it.')
                    : line('Review status', OK, 'The review status and Completed By need no action.'));
            }
            res.checks.add(investigations(complaintId));

            for (PhrDescriptionCheck.Finding f : PhrDescriptionCheck.check(c)) {
                res.checks.add(line(f.label, f.isGap ? WARN : OK, f.detail));
            }

            Integer gaps = 0;
            for (PhrMissingCheck k : res.checks) { if (k.status == WARN) { gaps++; } }
            res.intro = gaps == 0
                ? 'I checked ' + c.Name + ' and found no gaps.'
                : 'I checked ' + c.Name + ' and found ' + gaps + (gaps == 1 ? ' gap' : ' gaps') + ' to look at. Nothing was changed.';
            res.success = true;
        } catch (Exception ex) {
            return fail(res, 'Could not complete the check: ' + ex.getMessage());
        }
        return res;
    }

    private static PhrMissingCheck investigations(Id complaintId) {
        // The summary is a long text field and cannot be filtered in a query, so it is checked here.
        Integer total = 0;
        Integer blank = 0;
        for (compliancequest__SQX_Investigation__c i : [
            SELECT Id, compliancequest__Investigation_Summary__c FROM compliancequest__SQX_Investigation__c
            WHERE compliancequest__SQX_Complaint__c = :complaintId LIMIT 200
        ]) {
            total++;
            if (String.isBlank(i.compliancequest__Investigation_Summary__c)) { blank++; }
        }
        if (total == 0) {
            return line('Investigation summaries', OK, 'No investigations are linked to the complaint.');
        }
        if (blank > 0) {
            return line('Investigation summaries', WARN, blank + (blank == 1 ? ' linked investigation has' : ' linked investigations have') + ' no summary.');
        }
        return line('Investigation summaries', OK, 'Every linked investigation has a summary.');
    }

    private static PhrMissingCheck line(String label, String status, String detail) {
        PhrMissingCheck c = new PhrMissingCheck();
        c.label = label;
        c.status = status;
        c.detail = detail;
        return c;
    }

    private static PhrMissingDataResult fail(PhrMissingDataResult res, String msg) {
        res.success = false;
        res.errorMessage = msg;
        return res;
    }
}

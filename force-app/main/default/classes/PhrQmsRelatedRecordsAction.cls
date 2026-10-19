/**
 * PhrQmsRelatedRecordsAction
 * ----------------------------
 * Invocable action for Agentforce. Finds the Nonconformances, CAPAs, Change
 * Orders, Inspections and Investigations related to a Complaint's part (its
 * assembly components included) and lot, and optionally adds them to the
 * Complaint's Product History Review (Related Products) and Linked
 * Investigations.
 *
 * Mode:
 *   Preview (default) - lists the most relevant records (top 3 of each type)
 *                       and the question to ask; writes nothing.
 *   Apply             - after the user says yes: adds the top 3 most relevant
 *                       records of each type (including Linked Investigations).
 *                       The rest stay available in the PHR QMS Records panel.
 *   ApplyAll          - adds every record not already present.
 *
 * Intended agent flow: show the Associated Items table, call with Preview, ask
 * "Do you want to create the most relevant records?", and call with Apply only
 * if the user answers yes. On no, do nothing; the panel lists everything.
 */
global with sharing class PhrQmsRelatedRecordsAction {

    /** "Yes" creates at most this many records of each type. */
    @TestVisible private static final Integer AUTO_CREATE_PER_TYPE = 3;

    global class Request {
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) currently open in the conversation.' required=true)
        global Id recordId;

        @InvocableVariable(label='Mode' description='Preview (default) lists the top 3 most relevant records of each type and writes nothing. Apply creates those top 3 per type, only after the user answers yes. ApplyAll adds every related record.' required=false)
        global String mode;

        @InvocableVariable(label='Lot Number Override' description='Optional. Search this lot instead of the Complaint\'s own lot.' required=false)
        global String lotNumber;

        @InvocableVariable(label='Include Investigations' description='Also add the most relevant investigations as Linked Investigations on the Complaint. Defaults to true.' required=false)
        global Boolean includeInvestigations;
    }

    global class Response {
        @InvocableVariable(label='Success')
        global Boolean success;

        @InvocableVariable(label='Applied' description='True when records were written, false for a preview.')
        global Boolean applied;

        @InvocableVariable(label='Summary' description='Plain-text result to relay to the user.')
        global String summary;
    }

    @InvocableMethod(
        label='Add Related QMS Records to PHR'
        description='Finds NCs, CAPAs, Change Orders, Inspections and Investigations related to the Complaint part (including assembly components) and lot. Preview mode lists the top 3 per type and reports only; Apply mode adds those top 3 per type to the Product History Review and Linked Investigations.'
    )
    global static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            out.add(runOne(req));
        }
        return out;
    }

    private static Response runOne(Request req) {
        Response res = new Response();
        res.applied = false;
        try {
            Boolean includeInv = req.includeInvestigations == null ? true : req.includeInvestigations;
            String mode = String.isBlank(req.mode) ? 'preview' : req.mode.trim().toLowerCase();
            Boolean applyAll = mode == 'applyall' || mode == 'apply all';
            Boolean apply = applyAll || mode == 'apply';
            Integer top = AUTO_CREATE_PER_TYPE;

            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(req.recordId, req.lotNumber);
            if (!d.success) {
                res.success = false;
                res.summary = 'Could not read related records: ' + d.errorMessage;
                return res;
            }

            if (!apply) {
                String topList = summarizeTop(d, includeInv, top);
                res.success = true;
                res.summary = String.isBlank(topList)
                    ? 'There are no further related records to add right now. Preview only; nothing was changed.'
                    : 'The most relevant records (up to ' + top + ' of each type) are: ' + topList
                        + '. Preview only; nothing was changed. Ask the user: "Do you want to create the most relevant records?" '
                        + 'Run again with Mode = Apply only if they answer yes. If they answer no, change nothing and tell them '
                        + 'all related records are available in the PHR QMS Records panel.';
                return res;
            }

            PhrQmsPanelController.CreateResult cr = applyAll
                ? PhrQmsPanelController.createRelatedRecords(
                    req.recordId,
                    newIds(d.nonconformances), newIds(d.capas), newIds(d.changeOrders), newIds(d.inspections),
                    includeInv ? newIds(d.investigations) : new List<Id>())
                : PhrQmsPanelController.createRelatedRecords(
                    req.recordId,
                    topIds(d.nonconformances, top),
                    topIds(d.capas, top),
                    topIds(d.changeOrders, top),
                    topIds(d.inspections, top),
                    includeInv ? topIds(d.investigations, top) : new List<Id>());
            res.success = cr.success;
            res.applied = true;
            res.summary = cr.message + (applyAll ? '' : ' The remaining related records are available in the PHR QMS Records panel.');
        } catch (Exception ex) {
            res.success = false;
            res.summary = 'Could not complete the request: ' + ex.getMessage();
        }
        return res;
    }

    private static List<Id> newIds(List<PhrQmsPanelController.Row> rows) {
        List<Id> ids = new List<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (!r.alreadyAdded) {
                ids.add(r.id);
            }
        }
        return ids;
    }

    /**
     * The first n rows not yet on the PHR / Complaint. Rows come back from
     * getPanelData already ranked best first, so these are the most relevant.
     */
    @TestVisible
    private static List<Id> topIds(List<PhrQmsPanelController.Row> rows, Integer n) {
        List<Id> ids = new List<Id>();
        if (rows == null) { return ids; }
        for (PhrQmsPanelController.Row r : rows) {
            if (ids.size() >= n) { break; }
            if (!r.alreadyAdded) { ids.add(r.id); }
        }
        return ids;
    }

    /** "NC-000055 (Open), NC-000106 (Draft)" for the top n rows not yet added; blank when none. */
    private static String describeTop(String label, List<PhrQmsPanelController.Row> rows, Integer n) {
        Set<Id> top = new Set<Id>(topIds(rows, n));
        List<String> parts = new List<String>();
        for (PhrQmsPanelController.Row r : rows) {
            if (top.contains(r.id)) {
                parts.add(r.name + (String.isNotBlank(r.status) ? ' (' + r.status + ')' : ''));
            }
        }
        return parts.isEmpty() ? '' : label + ': ' + String.join(parts, ', ');
    }

    /** Plain-text list of what a "yes" would create: the top n of each type. */
    private static String summarizeTop(PhrQmsPanelController.PanelData d, Boolean includeInvestigations, Integer n) {
        List<String> lines = new List<String>();
        for (String s : new List<String>{
            describeTop('Nonconformances', d.nonconformances, n),
            describeTop('CAPAs', d.capas, n),
            describeTop('Change Orders', d.changeOrders, n),
            describeTop('Inspections', d.inspections, n),
            includeInvestigations ? describeTop('Investigations', d.investigations, n) : ''
        }) {
            if (String.isNotBlank(s)) { lines.add(s); }
        }
        return String.join(lines, '; ');
    }
}

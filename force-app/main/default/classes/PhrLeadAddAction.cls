/**
 * PhrLeadAddAction
 * ------------------
 * Invocable action for Agentforce. Run after the user has looked at the
 * "worth reviewing" card and confirmed.
 *
 * 1. Adds the records the user left ticked as formal records (Related Products
 *    on the PHR, Linked Investigations on the Complaint), using the same
 *    logic as the existing panel and PhrQmsRelatedRecordsAction.
 * 2. Stores EVERY record found (Top, Next and Set aside) as a PHR Lead row on
 *    the PHR, so each one shows in the three tier lists. Ticked rows are marked
 *    Added. Unticked and set-aside rows stay Not added and can be added later.
 *
 * Leave Selected Record Ids empty to add everything that is worth reviewing
 * (the default: everything ticked, set-aside records unticked).
 * A new search updates the same lead rows (by PHR and record); it does not
 * duplicate them and never turns an Added row back into Not added.
 */
global with sharing class PhrLeadAddAction {

    private static final String TIER_NEXT = 'Next';

    global class Request {
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) currently open in the conversation.' required=true)
        global Id recordId;

        @InvocableVariable(label='Selected Record Ids' description='Ids of the records the user left ticked. Leave empty to add every record that is worth reviewing.' required=false)
        global List<String> selectedRecordIds;

        @InvocableVariable(label='Lot Number Override' description='Optional. Search this lot instead of the Complaint\'s own lot.' required=false)
        global String lotNumber;
    }

    global class Response {
        @InvocableVariable(label='Success')
        global Boolean success;

        @InvocableVariable(label='Records Added' description='Formal records created (Related Products and Linked Investigations).')
        global Integer recordsAdded;

        @InvocableVariable(label='Leads Stored' description='Lead rows now on the PHR, added or not.')
        global Integer leadsStored;

        @InvocableVariable(label='Summary' description='Plain-text result to relay to the user.')
        global String summary;
    }

    @InvocableMethod(
        label='Add Selected Leads to PHR'
        description='Adds the records the user left ticked to the Product History Review (and Linked Investigations to the Complaint), and stores every record found as a PHR Lead row in the Top, Next or Set aside list. Run only after the user confirms.'
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
        res.recordsAdded = 0;
        res.leadsStored = 0;
        try {
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(req.recordId, req.lotNumber);
            if (!d.success) {
                res.success = false;
                res.summary = 'Could not read related records: ' + d.errorMessage;
                return res;
            }
            if (d.phrId == null) {
                res.success = false;
                res.summary = 'This Complaint has no Product History Review yet, so nothing could be added.';
                return res;
            }

            // Every record found, with its tier. Investigations are not scored, so they go in Next.
            List<PhrQmsPanelController.Row> leads = new List<PhrQmsPanelController.Row>();
            leads.addAll(d.nonconformances);
            leads.addAll(d.capas);
            leads.addAll(d.changeOrders);
            leads.addAll(d.inspections);
            leads.addAll(d.investigations);
            List<PhrQmsPanelController.Row> all = new List<PhrQmsPanelController.Row>(leads);
            all.addAll(d.setAside);

            Set<Id> selected = selectedIds(req.selectedRecordIds, leads, all);

            List<Id> nc = new List<Id>();
            List<Id> capa = new List<Id>();
            List<Id> co = new List<Id>();
            List<Id> insp = new List<Id>();
            List<Id> inv = new List<Id>();
            for (PhrQmsPanelController.Row r : all) {
                if (!selected.contains(r.id)) { continue; }
                String t = String.valueOf(r.id.getSobjectType());
                if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
                else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
                else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
                else if (t == 'compliancequest__SQX_Inspection__c') { insp.add(r.id); }
                else if (t == 'compliancequest__SQX_Investigation__c') { inv.add(r.id); }
            }

            PhrQmsPanelController.CreateResult cr = PhrQmsPanelController.createRelatedRecords(
                req.recordId, nc, capa, co, insp, inv);
            if (!cr.success) {
                res.success = false;
                res.summary = 'Could not add the selected records: ' + cr.message;
                return res;
            }
            res.recordsAdded = cr.relatedProductsCreated + cr.linkedInvestigationsCreated;

            res.leadsStored = storeLeads(d.phrId, all, selected, loadTitles(all));

            Integer notAdded = res.leadsStored - selected.size();
            res.success = true;
            res.summary = 'Added ' + res.recordsAdded + ' record(s) to the Product History Review'
                + (cr.skipped > 0 ? ' (' + cr.skipped + ' were already there)' : '') + '. '
                + 'All ' + res.leadsStored + ' records found are listed on the PHR under Top, Next and Set aside'
                + (notAdded > 0 ? '; ' + notAdded + ' are marked Not added and can be added later.' : '.');
        } catch (Exception ex) {
            res.success = false;
            res.summary = 'Could not complete the request: ' + ex.getMessage();
        }
        return res;
    }

    /** Blank selection = every record worth reviewing (set-aside records stay unticked). */
    @TestVisible
    private static Set<Id> selectedIds(List<String> requested, List<PhrQmsPanelController.Row> leads,
                                       List<PhrQmsPanelController.Row> all) {
        Set<Id> known = new Set<Id>();
        for (PhrQmsPanelController.Row r : all) { known.add(r.id); }
        Set<Id> out = new Set<Id>();
        if (requested == null || requested.isEmpty()) {
            for (PhrQmsPanelController.Row r : leads) { out.add(r.id); }
            return out;
        }
        for (String s : requested) {
            if (String.isBlank(s)) { continue; }
            try {
                Id i = Id.valueOf(s.trim());
                if (known.contains(i)) { out.add(i); }
            } catch (Exception ex) {
                // not an Id: ignore
            }
        }
        return out;
    }

    /** Upserts one PHR Lead per record. Returns how many lead rows the PHR now holds for this search. */
    private static Integer storeLeads(Id phrId, List<PhrQmsPanelController.Row> all, Set<Id> selected,
                                      Map<Id, String> titles) {
        Map<String, PHR_Lead__c> existing = new Map<String, PHR_Lead__c>();
        for (PHR_Lead__c l : [
            SELECT Id, Lead_Key__c, Added__c FROM PHR_Lead__c WHERE PHR__c = :phrId
        ]) {
            existing.put(l.Lead_Key__c, l);
        }
        List<PHR_Lead__c> rows = new List<PHR_Lead__c>();
        for (PhrQmsPanelController.Row r : all) {
            String key = String.valueOf(phrId) + '-' + String.valueOf(r.id);
            PHR_Lead__c old = existing.get(key);
            Boolean nowAdded = selected.contains(r.id) || r.alreadyAdded == true;
            PHR_Lead__c l = new PHR_Lead__c();
            if (old != null) {
                l.Id = old.Id;
            } else {
                l.PHR__c = phrId;
                l.Lead_Key__c = key;
            }
            l.Tier__c = String.isBlank(r.tier) ? TIER_NEXT : r.tier;
            l.Colour__c = r.colour;
            l.Relevance__c = r.relevance;
            l.Reason__c = r.reason == null ? null : r.reason.left(255);
            l.Related_By__c = r.relatedBy;
            l.Record_Id__c = String.valueOf(r.id);
            l.Record_Number__c = r.name;
            l.Record_Type__c = String.isBlank(r.recordType) ? typeLabel(r.id) : r.recordType;
            l.Record_Status__c = r.status;
            String title = titles.get(r.id);
            l.Record_Title__c = title == null ? null : title.left(255);
            if (old == null || old.Added__c != true) {
                l.Added__c = nowAdded;
                if (nowAdded) { l.Added_On__c = System.now(); }
            }
            rows.add(l);
        }
        upsert rows;
        return rows.size();
    }

    private static String typeLabel(Id i) {
        String t = String.valueOf(i.getSobjectType());
        if (t == 'compliancequest__SQX_Nonconformance__c') { return 'Nonconformance'; }
        if (t == 'compliancequest__SQX_CAPA__c') { return 'CAPA'; }
        if (t == 'compliancequest__SQX_Change_Order__c') { return 'Change Order'; }
        if (t == 'compliancequest__SQX_Inspection__c') { return 'Inspection'; }
        if (t == 'compliancequest__SQX_Investigation__c') { return 'Investigation'; }
        return t;
    }

    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            String t = String.valueOf(r.id.getSobjectType());
            if (t == 'compliancequest__SQX_Nonconformance__c') { nc.add(r.id); }
            else if (t == 'compliancequest__SQX_CAPA__c') { capa.add(r.id); }
            else if (t == 'compliancequest__SQX_Change_Order__c') { co.add(r.id); }
        }
        Map<Id, String> m = new Map<Id, String>();
        for (compliancequest__SQX_Nonconformance__c x : [
            SELECT Id, compliancequest__NC_Title__c FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :nc
        ]) { m.put(x.Id, x.compliancequest__NC_Title__c); }
        for (compliancequest__SQX_CAPA__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c WHERE Id IN :capa
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        for (compliancequest__SQX_Change_Order__c x : [
            SELECT Id, compliancequest__Title__c FROM compliancequest__SQX_Change_Order__c WHERE Id IN :co
        ]) { m.put(x.Id, x.compliancequest__Title__c); }
        return m;
    }
}

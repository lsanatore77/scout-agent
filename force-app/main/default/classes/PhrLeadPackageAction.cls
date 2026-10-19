/**
 * PhrLeadPackageAction
 * ----------------------
 * Invocable action for Agentforce. Returns the "worth reviewing" lead package
 * for a Complaint as typed data, so the phrLeadPackageType renderer can show it
 * as a card in the conversation.
 *
 * Read only: it writes nothing and sends nothing. It uses the relevance model
 * (PhrQmsRelevance) through PhrQmsPanelController.getPanelData, so the ranking,
 * the tiers and the set-aside list are the same ones the panel and the existing
 * action use. It does not change PhrQmsRelatedRecordsAction.
 *
 * Titles are looked up here because the ranked rows do not carry them.
 * Overall score: placeholder numbers from the design (section 15.3); the
 * "pattern" row is not calculated yet.
 */
global with sharing class PhrLeadPackageAction {

    @TestVisible private static final Integer SHOWN_PER_SECTION = 3;

    global class Request {
        @InvocableVariable(label='Complaint or PHR Id' description='The Complaint (or its Product History Review) currently open in the conversation.' required=true)
        global Id recordId;

        @InvocableVariable(label='Lot Number Override' description='Optional. Search this lot instead of the Complaint\'s own lot.' required=false)
        global String lotNumber;
    }

    global class ActionResponse {
        @InvocableVariable(label='Relevance Package' description='What is worth reviewing for this complaint, ranked, with the overall rating.')
        global PhrLeadPackageData leadPackage;
    }

    @InvocableMethod(
        label='Get Relevance Package (Worth Reviewing)'
        description='Returns the records worth reviewing for a Complaint (nonconformances, CAPAs, change orders, inspections, investigations), ranked by relevance with a colour for how many of the three criteria were met, an overall High/Medium/Low rating, and the records set aside with the reason. Read only: it creates and sends nothing.'
    )
    global static List<ActionResponse> run(List<Request> requests) {
        List<ActionResponse> out = new List<ActionResponse>();
        for (Request req : requests) {
            ActionResponse r = new ActionResponse();
            r.leadPackage = build(req);
            out.add(r);
        }
        return out;
    }

    private static PhrLeadPackageData build(Request req) {
        PhrLeadPackageData pkg = new PhrLeadPackageData();
        try {
            PhrQmsPanelController.PanelData d = PhrQmsPanelController.getPanelData(req.recordId, req.lotNumber);
            if (!d.success) {
                pkg.success = false;
                pkg.errorMessage = 'Could not read related records: ' + d.errorMessage;
                return pkg;
            }

            List<PhrQmsPanelController.Row> all = new List<PhrQmsPanelController.Row>();
            all.addAll(d.nonconformances);
            all.addAll(d.capas);
            all.addAll(d.changeOrders);
            all.addAll(d.inspections);
            all.addAll(d.investigations);
            all.addAll(d.setAside);
            Map<Id, String> titles = loadTitles(all);

            addSection(pkg, 'Nonconformances', d.nonconformances, titles);
            addSection(pkg, 'CAPAs', d.capas, titles);
            addSection(pkg, 'Change Orders', d.changeOrders, titles);
            addSection(pkg, 'Inspections', d.inspections, titles);
            addSection(pkg, 'Investigations', d.investigations, titles);
            for (PhrQmsPanelController.Row r : d.setAside) {
                pkg.setAside.add(toRecord(r, titles));
            }

            List<PhrQmsPanelController.Row> leads = new List<PhrQmsPanelController.Row>();
            leads.addAll(d.nonconformances);
            leads.addAll(d.capas);
            leads.addAll(d.changeOrders);
            leads.addAll(d.inspections);
            pkg.overallScore = overallScore(leads);
            pkg.overallRating = rating(pkg.overallScore);
            pkg.intro = intro(d, pkg, leads.size(), d.investigations.size());
            pkg.success = true;
        } catch (Exception ex) {
            pkg.success = false;
            pkg.errorMessage = 'Could not complete the request: ' + ex.getMessage();
        }
        return pkg;
    }

    private static void addSection(PhrLeadPackageData pkg, String title,
                                   List<PhrQmsPanelController.Row> rows, Map<Id, String> titles) {
        if (rows == null || rows.isEmpty()) { return; }
        PhrLeadSection s = new PhrLeadSection();
        s.title = title;
        s.shownCount = SHOWN_PER_SECTION;
        for (PhrQmsPanelController.Row r : rows) {
            s.rows.add(toRecord(r, titles));
        }
        pkg.sections.add(s);
    }

    private static PhrLeadRecord toRecord(PhrQmsPanelController.Row r, Map<Id, String> titles) {
        PhrLeadRecord rec = new PhrLeadRecord();
        rec.id = r.id;
        rec.recordType = r.recordType;
        rec.name = r.name;
        rec.status = r.status;
        rec.title = titles.get(r.id);
        rec.colour = r.colour;
        rec.relevance = r.relevance;
        rec.reason = r.reason;
        if (r.relatedBy == PhrQmsRelevance.KIND_OTHER || r.relatedBy == PhrQmsRelevance.KIND_COMPONENT) {
            rec.note = r.relatedBy;
        }
        return rec;
    }

    /** Titles for NCs, CAPAs and change orders. Inspections and investigations have none. */
    private static Map<Id, String> loadTitles(List<PhrQmsPanelController.Row> rows) {
        Set<Id> nc = new Set<Id>();
        Set<Id> capa = new Set<Id>();
        Set<Id> co = new Set<Id>();
        for (PhrQmsPanelController.Row r : rows) {
            if (r.id == null) { continue; }
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

    /** Placeholder overall score (design 15.3), capped at 100. Uses the best match. */
    @TestVisible
    private static Integer overallScore(List<PhrQmsPanelController.Row> leads) {
        if (leads == null || leads.isEmpty()) { return 0; }
        Integer best = 0;
        Boolean lot = false;
        Boolean open = false;
        Boolean other = false;
        for (PhrQmsPanelController.Row r : leads) {
            if (r.relevance != null && r.relevance > best) { best = r.relevance; }
            if (String.isNotBlank(r.criteriaMet) && r.criteriaMet.contains('Lot')) { lot = true; }
            if (r.relatedBy == PhrQmsRelevance.KIND_OTHER) { other = true; }
            String s = String.isBlank(r.status) ? '' : r.status.toLowerCase();
            if (!(s.contains('closed') || s.contains('complete') || s.contains('cancel') || s.contains('void'))) { open = true; }
        }
        Integer n = leads.size();
        Integer score = Math.min(40, (best * 40) / 100)
            + (lot ? 20 : 0)
            + (n >= 6 ? 15 : (n >= 3 ? 10 : 5))
            + (open ? 10 : 0)
            + (other ? 10 : 0);
        return Math.min(100, score);
    }

    @TestVisible
    private static String rating(Integer score) {
        if (score == null || score <= 0) { return 'None'; }
        if (score >= 60) { return 'High'; }
        if (score >= 40) { return 'Medium'; }
        return 'Low';
    }

    private static String intro(PhrQmsPanelController.PanelData d, PhrLeadPackageData pkg, Integer leadCount, Integer invCount) {
        if (leadCount == 0 && invCount == 0) {
            return 'I found nothing worth reviewing for ' + d.complaintName + '.'
                + (d.setAside.isEmpty() ? '' : ' I set aside ' + d.setAside.size() + ' records that did not look related.');
        }
        String s = 'I found ' + (leadCount + invCount) + ' records worth reviewing for ' + d.complaintName + '. ';
        if (String.isBlank(d.lotNumber)) {
            s += 'This complaint has no lot number, so I ranked by product link, symptom match and recency. ';
        }
        if (!d.setAside.isEmpty()) {
            s += 'I set aside ' + d.setAside.size() + ' that did not look related. ';
        }
        s += 'Nothing was added or changed.';
        return s;
    }
}

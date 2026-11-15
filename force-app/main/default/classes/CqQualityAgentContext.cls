/**
 * CqQualityAgentContext
 * ---------------------
 * Invocable action for the CQ.AI Quality agent. Given a Nonconformance, returns what the triage
 * workspace shows as plain text, so the agent answers from the same facts the user sees: the problem,
 * each CQ.AI Triage step (Containment, Data Check, Risk, Investigation Links) with what CQ.AI Suggests
 * and what the triager chose, the Field Action Review suggestion and decision, and the relevant
 * records on the part (other NCs, complaints, CAPAs, field actions), already sorted.
 *
 * Read only: everything runs inside a savepoint that is rolled back, so the action changes nothing.
 */
global with sharing class CqQualityAgentContext {

    @TestVisible static final Integer MAX_ROWS = 10;
    @TestVisible static final List<String> STEP_NAMES = new List<String>{ 'Triage at a Glance', 'Containment', 'Data Check', 'Risk', 'Next Steps' };

    global class Request {
        @InvocableVariable(label='Record Id' description='The Nonconformance currently open in the conversation.' required=true)
        global Id recordId;
    }

    global class Response {
        @InvocableVariable(label='Nonconformance Facts' description='Everything the triage workspace shows for this nonconformance, as plain text sections. Answer only from this.')
        global String facts;
    }

    @InvocableMethod(
        label='Get Nonconformance Facts'
        description='Reads a Nonconformance and returns what its triage workspace shows: the problem, part and lot, where triage stands, each triage step (containment, data check, risk, investigation links) with what CQ.AI Suggests and what was chosen, lot stock and shipments, the Field Action Review suggestion and decision, and the relevant records on the part. Read only: it creates and changes nothing.'
    )
    global static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.facts = factsFor(req == null ? null : req.recordId);
            out.add(r);
        }
        return out;
    }

    public static String factsFor(Id recordId) {
        if (recordId == null) { return 'No record was given, so I cannot tell which nonconformance to read.'; }
        if (recordId.getSObjectType() != compliancequest__SQX_Nonconformance__c.SObjectType) {
            return 'This record is a ' + recordId.getSObjectType().getDescribe().getLabel()
                + ', not a Nonconformance. The Quality agent only reads nonconformances for now.';
        }
        List<String> lines = new List<String>();
        Savepoint sp = Database.setSavepoint();
        try {
            build(lines, recordId);
        } catch (Exception e) {
            lines.add('The record could not be read: ' + e.getMessage());
        } finally {
            Database.rollback(sp);
        }
        return String.join(lines, '\n');
    }

    // ---------------------------------------------------------------- build

    static void build(List<String> l, Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT Id, Name, Triage_Draft__c, Triage_Risk__c, Triage_Path__c, Triage_Notes__c, Triage_By__r.Name, Triage_On__c,
                   compliancequest__Containment_Required__c, compliancequest__Investigation_Required__c, compliancequest__Disposition_Required__c,
                   compliancequest__Record_Stage__c, compliancequest__Due_Date_Disposition__c, compliancequest__Disposition_Approval__c,
                   compliancequest__Due_Date_Investigation__c, compliancequest__Investigation_Approval__c, compliancequest__SQX_Approval_Matrix__r.Name
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
        CqTriageController.Glance g = CqTriageController.getGlance(recordId);
        CqTriageRisk.Risk rr = CqTriageRisk.getRisk(recordId);
        CqTriageLinks.Links lk = CqTriageLinks.getLinks(recordId);
        Map<String, Object> draft = parseDraft(nc.Triage_Draft__c);
        Boolean complete = nc.Triage_Risk__c != null && nc.Triage_Path__c != null;
        Map<String, String> chose = complete ? notesMap(nc.Triage_Notes__c) : new Map<String, String>();
        Boolean hasPhoto = false;
        try { hasPhoto = CqTriagePhoto.getPhotoVersionId(recordId) != null; } catch (Exception e) { hasPhoto = false; }

        // ---- the record
        l.add('NONCONFORMANCE ' + link(g.name, recordId, 'compliancequest__SQX_Nonconformance__c') + ': ' + s(g.title));
        l.add('Status: ' + s(g.status) + '. Stage: ' + stage(nc.compliancequest__Record_Stage__c) + '. Owner: ' + s(g.owner) + '. Type: ' + s(g.ncType) + '. Occurred: ' + d(g.occurred) + '.');
        l.add('Part: ' + s(g.partNumber != null ? g.partNumber : g.partName) + (g.partNumber != null && g.partName != null && g.partName != g.partNumber ? ' (' + g.partName + ')' : '')
            + '. Lot: ' + s(g.lot) + '. Lot quantity: ' + n(g.lotQuantity) + '. Defective quantity: ' + n(g.defectiveQuantity) + '.');
        l.add('The problem: ' + (String.isBlank(g.description) ? 'no description is recorded.' : g.description.abbreviate(1200)));

        // ---- where triage stands
        l.add('');
        l.add('TRIAGE');
        Integer step = draft == null ? 0 : intOf(draft.get('step'));
        Integer maxStep = draft == null ? 0 : intOf(draft.get('maxStep'));
        if (complete) {
            l.add('Triage is complete: risk ' + nc.Triage_Risk__c + ', path ' + nc.Triage_Path__c + ', by ' + s(nc.Triage_By__r?.Name) + ' on ' + d(nc.Triage_On__c) + '.');
            if (!String.isBlank(nc.Triage_Notes__c)) { l.add('Triage notes: ' + nc.Triage_Notes__c.abbreviate(800)); }
            l.add('Required in CQ: containment ' + yn(nc.compliancequest__Containment_Required__c) + ', investigation ' + yn(nc.compliancequest__Investigation_Required__c)
                + ', disposition ' + yn(nc.compliancequest__Disposition_Required__c) + '.');
        } else if (draft == null || maxStep == 0) {
            l.add('Triage has not started. Every step below shows what CQ.AI Suggests; nothing has been chosen yet.');
        } else {
            l.add('Triage is in progress, not complete. The step open now is ' + STEP_NAMES[Math.min(step, STEP_NAMES.size() - 1)] + '.');
            for (Integer i = 1; i < STEP_NAMES.size(); i++) {
                String st = i == step ? 'open now' : i < maxStep || i < step ? 'gone through' : i == maxStep ? 'reached' : 'not started';
                l.add('- ' + STEP_NAMES[i] + ': ' + st + '.');
            }
            l.add('Triage is finished with Complete triage on the Next Steps step, which moves the NC to Disposition / Investigate.');
        }

        // ---- containment
        Map<String, Object> acts = draft == null ? null : (Map<String, Object>) draft.get('acts');
        CqTriageController.Card cont = card(g, 'cont');
        Boolean contained = cont.headline == 'Contained' || cont.headline == 'Containment raised';
        l.add('');
        l.add('CONTAINMENT STEP');
        l.add('On this NC now: ' + cont.headline + '. ' + s(cont.why));
        l.add('Containment records: ' + factOf(cont, 'Containment') + '.');
        String sug = contained ? 'No further action, because containment is already raised on this NC'
            : g.lot != null ? 'Hold lot ' + g.lot + ', because no containment is recorded on this NC yet'
            : 'Hold the affected stock, because no containment is recorded and no lot is set';
        if (complete) {
            l.add('Chosen at triage: ' + s(chose.get('Containment')) + '.');
            List<String> fromTriage = new List<String>();
            for (compliancequest__SQX_Containment__c c : [SELECT Name, compliancequest__Status__c, compliancequest__Description__c FROM compliancequest__SQX_Containment__c
                                                         WHERE compliancequest__SQX_Nonconformance__c = :recordId ORDER BY Name LIMIT 50]) {
                if (c.compliancequest__Description__c != null && c.compliancequest__Description__c.startsWith('Raised at triage')) { fromTriage.add(c.Name + ' (' + c.compliancequest__Status__c + ')'); }
            }
            if (!fromTriage.isEmpty()) { l.add('Containment records raised by that triage: ' + String.join(fromTriage, ', ') + '.'); }
            l.add('CQ.AI Suggests now, after triage: ' + sug + '.');
        } else {
            l.add('CQ.AI Suggests: ' + sug + '.');
        }
        l.add('Options on this step: Hold (' + (g.lot != null ? 'hold lot ' + g.lot : 'hold the affected stock') + '); Check (100% inspect remaining stock of this part); Stop (stop the process until the cause is known); No action.');
        if (g.lot != null) {
            CqLotStock.Stock st = CqLotStock.forLots(new Set<String>{ g.lot }).get(g.lot);
            if (st == null || st.hasRecord != true) {
                l.add('Stock on hand for lot ' + g.lot + ': no stock record.');
            } else {
                List<String> spots = new List<String>();
                for (CqLotStock.Place p : st.places) { spots.add(n(p.units) + ' at ' + s(p.location)); }
                l.add('Stock on hand for lot ' + g.lot + ': ' + n(st.total) + ' units' + (spots.isEmpty() ? '' : ' (' + String.join(spots, ', ') + ')')
                    + (st.asOf == null ? '' : ', as of ' + d(st.asOf)) + '.');
            }
            List<CqLotShipments.Consignee> sent = CqLotShipments.customers(new Set<String>{ g.lot });
            Decimal units = 0;
            List<String> who = new List<String>();
            for (CqLotShipments.Consignee k : sent) { units += k.units == null ? 0 : k.units; if (who.size() < 5) { who.add(k.name + ' (' + n(k.units) + ')'); } }
            l.add(sent.isEmpty() ? 'Shipments of lot ' + g.lot + ': none recorded.'
                : 'Shipped from lot ' + g.lot + ': ' + n(units) + ' units to ' + sent.size() + ' customer(s): ' + String.join(who, ', ') + (sent.size() > 5 ? ', and ' + (sent.size() - 5) + ' more' : '') + '.');
        } else {
            l.add('No lot is recorded, so stock on hand and shipments cannot be looked up.');
        }
        if (!complete && acts != null && !acts.isEmpty()) {
            List<String> chosen = new List<String>();
            if (acts.get('hold') == true) { chosen.add(g.lot != null ? 'Hold lot ' + g.lot : 'Hold the affected stock'); }
            if (acts.get('check') == true) { chosen.add('100% inspect remaining stock of this part'); }
            if (acts.get('stop') == true) { chosen.add('Stop the process until the cause is known'); }
            if (acts.get('none') == true) {
                String why = draft.get('noActionWhy') == null ? '' : String.valueOf(draft.get('noActionWhy'));
                chosen.add('No action' + (String.isBlank(why) ? '' : ', because: ' + why));
            }
            l.add('Chosen in triage so far: ' + (chosen.isEmpty() ? 'nothing yet' : String.join(chosen, '; ')) + (draft.get('due') == null || chosen.isEmpty() ? '' : '. Due ' + draft.get('due')) + '.');
        } else if (!complete) {
            l.add('Chosen in triage so far: nothing yet.');
        }
        List<Object> added = draft == null ? null : (List<Object>) draft.get('added');
        if (added != null && !added.isEmpty()) {
            List<String> names = new List<String>();
            for (Object o : added) { Map<String, Object> m = (Map<String, Object>) o; names.add(m.get('name') + ' (' + m.get('title') + ')'); }
            l.add('Containment created during this triage: ' + String.join(names, ', ') + '.');
        }

        // ---- data check
        l.add('');
        l.add('DATA CHECK STEP');
        CqTriageController.Card riskCard = card(g, 'risk');
        String part = g.partNumber != null ? g.partNumber : g.partName;
        List<String> missing = new List<String>();
        l.add('- Description: ' + (String.isBlank(g.description) ? 'none' : 'recorded') + '.');
        if (String.isBlank(g.description)) { missing.add('description'); }
        l.add('- Photo: ' + (hasPhoto ? 'attached' : 'none attached') + '.');
        if (!hasPhoto) { missing.add('photo'); }
        l.add('- Part and lot: ' + (part == null ? 'no part' : part) + ', ' + (g.lot == null ? 'no lot' : 'lot ' + g.lot) + '.');
        if (part == null || g.lot == null) { missing.add(part == null ? 'part' : 'lot'); }
        l.add('- How many: ' + (g.defectiveQuantity == null ? 'defective quantity not set' : n(g.defectiveQuantity) + ' of ' + (g.lotQuantity == null ? 'an unknown lot quantity' : n(g.lotQuantity))) + '.');
        if (g.defectiveQuantity == null) { missing.add('defective quantity'); }
        l.add('- Severity: ' + (rr.severityAssumed ? 'not set, CQ.AI assumes Moderate' : CqTriageRisk.SEV[rr.severity - 1]) + '.');
        if (rr.severityAssumed) { missing.add('severity'); }
        l.add(missing.isEmpty() ? 'CQ.AI Suggests: Good enough, send on, because every item is recorded.'
            : 'Missing: ' + String.join(missing, ', ') + '. CQ.AI does not suggest sending it on until these are recorded; the triager can still choose Good enough, send on, or Request more information.');
        if (complete) { l.add('Chosen at triage: ' + s(chose.get('Data Check')) + '.'); }
        if (!complete && draft != null) {
            String data = draft.get('data') == null ? '' : String.valueOf(draft.get('data'));
            if (data == 'ok') { l.add('Chosen in triage: Good enough, send on.'); }
            else if (data == 'ask') {
                List<String> asks = new List<String>();
                Map<String, Object> am = (Map<String, Object>) draft.get('asks');
                if (am != null) { for (String k : am.keySet()) { if (am.get(k) == true) { asks.add(k); } } }
                asks.sort();
                String note = draft.get('askNote') == null ? '' : String.valueOf(draft.get('askNote'));
                l.add('Chosen in triage: Request more information' + (asks.isEmpty() ? '' : ' (' + String.join(asks, ', ') + ')') + (String.isBlank(note) ? '' : '. Note: ' + note) + '.');
            } else { l.add('Chosen in triage: nothing yet.'); }
        }

        // ---- risk
        l.add('');
        l.add('RISK STEP');
        Integer score = rr.severity * rr.likelihood;
        String level = rr.escaped ? 'High' : CqTriageRisk.band(score);
        l.add('CQ.AI Suggests' + (complete ? ' now, after triage,' : '') + ' risk ' + level + ': severity ' + CqTriageRisk.SEV[rr.severity - 1] + ' x likelihood ' + CqTriageRisk.LIK[rr.likelihood - 1] + ' = score ' + score + ' of 25'
            + (rr.escaped ? ', raised to High because ' + s(rr.escapedWhy) : '') + '.');
        l.add('Bands: Low below 6, Medium 6 to 14, High 15 and above.');
        l.add('- Severity ' + rr.severity + ' (' + CqTriageRisk.SEV[rr.severity - 1].substringAfter(' - ') + '): ' + s(rr.severityWhy) + '.');
        l.add('- Likelihood ' + rr.likelihood + ' (' + CqTriageRisk.LIK[rr.likelihood - 1].substringAfter(' - ') + '): ' + s(rr.likelihoodWhy) + '.');
        if (rr.recent != null && !rr.recent.isEmpty()) { l.add('Recent NCs counted for likelihood (last ' + CqTriageRisk.WINDOW_DAYS + ' days): ' + String.join(rr.recent, ', ') + '.'); }
        l.add('Same lot: ' + factOf(riskCard, 'Same lot') + '. Complaints: ' + factOf(riskCard, 'Complaints') + '.');
        if (complete) {
            if (chose.get('Risk') != null) { l.add('Recorded at triage: ' + chose.get('Risk') + '.'); }
            l.add('Risk chosen at triage: ' + nc.Triage_Risk__c + '. The CQ.AI risk above is worked out today; the line recorded at triage says what CQ.AI suggested then.');
        } else if (draft != null && draft.get('sev') != null && draft.get('lik') != null) {
            Integer ds = intOf(draft.get('sev')); Integer dl = intOf(draft.get('lik'));
            if (ds != rr.severity || dl != rr.likelihood) {
                Integer s2 = ds * dl;
                l.add('Changed in triage to severity ' + ds + ' x likelihood ' + dl + ' = score ' + s2 + ', ' + (rr.escaped ? 'High' : CqTriageRisk.band(s2)) + '.');
            }
        }
        for (String gap : g.gaps) { if (!gap.startsWith('No ERP')) { l.add('Gap: ' + gap); } }

        // ---- investigation links
        l.add('');
        l.add('NEXT STEPS STEP');
        CqTriageNext.Next nx = CqTriageNext.getNext(recordId);
        l.add('Disposition: CQ.AI Suggests' + (complete ? ' now, after triage,' : '') + ' ' + (nx.dispSuggest == 'req' ? 'Required' : 'Not required') + '. Why: ' + nx.dispWhy);
        l.add('Investigation: CQ.AI Suggests' + (complete ? ' now, after triage,' : '') + ' ' + (nx.invSuggest == 'inv' ? 'Investigate' : 'Log Only') + '. Why: ' + nx.invWhy);
        l.add('Defaults: disposition due in ' + CqTriageNext.DISPOSITION_DAYS + ' days, investigation due in ' + CqTriageNext.INVESTIGATION_DAYS
            + ' days, approvals off. Approvals use an approval matrix; the default is ' + CqTriageNext.DEFAULT_MATRIX + '.');
        if (complete) {
            l.add('Chosen at triage: disposition ' + (nc.compliancequest__Disposition_Required__c == true
                    ? 'required, due ' + d(nc.compliancequest__Due_Date_Disposition__c) + (nc.compliancequest__Disposition_Approval__c == true ? ', needs approval' : '') : 'not required')
                + '; investigation ' + (nc.compliancequest__Investigation_Required__c == true
                    ? 'required, due ' + d(nc.compliancequest__Due_Date_Investigation__c) + (nc.compliancequest__Investigation_Approval__c == true ? ', needs approval' : '') : 'not required (log only)')
                + (nc.compliancequest__SQX_Approval_Matrix__r == null ? '' : '; approval matrix ' + nc.compliancequest__SQX_Approval_Matrix__r.Name) + '.');
        } else if (draft != null && (draft.get('disp') != null || draft.get('inv') != null)) {
            String dsp = draft.get('disp') == null ? '' : String.valueOf(draft.get('disp'));
            String iv = draft.get('inv') == null ? '' : String.valueOf(draft.get('inv'));
            l.add('Chosen in triage so far: disposition ' + (dsp == 'req' ? 'required, due ' + draft.get('dispDue') + (draft.get('dispAppr') == true ? ', needs approval' : '') : dsp == 'no' ? 'not required' : 'not chosen yet')
                + '; investigation ' + (iv == 'inv' ? 'investigate, due ' + draft.get('invDue') + (draft.get('invAppr') == true ? ', needs approval' : '') : iv == 'log' ? 'log only' : 'not chosen yet') + '.');
        } else if (!complete) {
            l.add('Chosen in triage so far: nothing yet.');
        }
        l.add('Investigation links (shown only when Investigate is chosen):');
        l.add('This NC\'s own investigation: ' + (lk.ownName != null ? lk.ownName : 'not started') + (lk.due == null ? '' : ', due ' + d(lk.due)) + '.');
        Map<String, Object> picks = draft == null ? null : (Map<String, Object>) draft.get('picks');
        List<String> sugL = new List<String>(); List<String> linkedL = new List<String>(); List<String> otherL = new List<String>();
        for (CqTriageLinks.Inv v : lk.items) {
            String line = '- ' + link(v.name, v.id, 'compliancequest__SQX_Investigation__c') + (v.ncName == null ? '' : ' (from ' + v.ncName + ')') + ', ' + s(v.status)
                + (String.isBlank(v.why) ? '' : '. Why: ' + v.why) + (picks != null && picks.get(v.id) == true && !v.linked ? '. Picked in this triage' : '')
                + (String.isBlank(v.summary) ? '.' : '. Summary: ' + dot(v.summary.abbreviate(200)));
            if (v.linked) { linkedL.add(line); } else if (v.suggested) { sugL.add(line); } else { otherL.add(line); }
        }
        if (complete) { l.add('Chosen at triage: investigation ' + s(chose.get('Investigation')) + '; links ' + s(chose.get('Links')) + '.'); }
        l.add(sugL.isEmpty() ? 'CQ.AI Suggests linking: none.' : 'CQ.AI Suggests linking these for research (' + sugL.size() + '):');
        l.addAll(sugL);
        if (!linkedL.isEmpty()) { l.add('Already linked (' + linkedL.size() + '):'); l.addAll(linkedL); }
        if (!otherL.isEmpty()) { l.add('Other investigations on this part, not suggested: ' + otherL.size() + '.'); }

        // ---- field action review
        CqTriageController.FieldAction fa = g.fieldAction;
        l.add('');
        l.add('FIELD ACTION REVIEW');
        l.add('CQ.AI Suggests: ' + s(fa.suggestion) + '. Why: ' + s(fa.suggestionWhy));
        if (fa.status == null) { l.add(fa.reviewName == null ? 'Decision: not made yet. It is made in the Field Action Review section of the NC page.' : 'Decision: not recorded on this NC, but a review was opened for it.'); }
        else { l.add('Decision: ' + fa.status + ' by ' + s(fa.setBy) + ' on ' + d(fa.setOn) + (String.isBlank(fa.reason) ? '' : '. Reason: ' + fa.reason) + '.'); }
        if (fa.reviewName != null) {
            l.add('Review ' + link(fa.reviewName, fa.reviewId, 'Field_Action_Review__c') + ': ' + s(fa.reviewStatus) + (fa.reviewOutcome == null ? '' : ', outcome ' + fa.reviewOutcome)
                + (fa.faName == null ? '' : '. Field action ' + link(fa.faName, fa.faId, 'Field_Action__c') + ' was opened from it') + '.');
        }

        // ---- relevant records on the part
        partHistory(l, g, recordId);
    }

    static void partHistory(List<String> l, CqTriageController.Glance g, Id recordId) {
        l.add('');
        l.add('RELEVANT RECORDS ON THE PART');
        if (g.partId == null) { l.add('No part is recorded, so relevant records cannot be found.'); return; }
        Date since = Date.today().addDays(-CqTriageController.REPEAT_DAYS);

        List<Row> ncs = new List<Row>();
        for (compliancequest__SQX_Nonconformance__c o : [
                SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Status__c, compliancequest__Lot_Number__c, CreatedDate
                FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__SQX_Part__c = :g.partId AND Id != :recordId AND CreatedDate >= :since
                ORDER BY CreatedDate DESC LIMIT 200]) {
            ncs.add(new Row(o.Id, o.Name, o.compliancequest__NC_Title__c, o.compliancequest__Status__c, o.compliancequest__Lot_Number__c, o.CreatedDate, g.lot, 'compliancequest__SQX_Nonconformance__c'));
        }
        section(l, 'Other NCs on the part in the last ' + CqTriageController.REPEAT_DAYS + ' days', ncs, g.lot);

        List<Row> comps = new List<Row>();
        for (compliancequest__SQX_Complaint__c c : [
                SELECT Id, Name, compliancequest__Complaint_Title__c, compliancequest__Status__c, compliancequest__Lot_Number__c, CreatedDate
                FROM compliancequest__SQX_Complaint__c WHERE compliancequest__SQX_Part__c = :g.partId ORDER BY CreatedDate DESC LIMIT 200]) {
            comps.add(new Row(c.Id, c.Name, c.compliancequest__Complaint_Title__c, c.compliancequest__Status__c, c.compliancequest__Lot_Number__c, c.CreatedDate, g.lot, 'compliancequest__SQX_Complaint__c'));
        }
        section(l, 'Complaints on the part', comps, g.lot);

        List<Row> capas = new List<Row>();
        for (compliancequest__SQX_CAPA__c c : [
                SELECT Id, Name, compliancequest__Title__c, compliancequest__Status__c, CreatedDate
                FROM compliancequest__SQX_CAPA__c WHERE compliancequest__SQX_Part__c = :g.partId ORDER BY CreatedDate DESC LIMIT 200]) {
            capas.add(new Row(c.Id, c.Name, c.compliancequest__Title__c, c.compliancequest__Status__c, null, c.CreatedDate, null, 'compliancequest__SQX_CAPA__c'));
        }
        section(l, 'CAPAs on the part', capas, null);

        List<Row> fas = new List<Row>();
        for (Field_Action__c f : [
                SELECT Id, Name, Title__c, Status__c, CreatedDate FROM Field_Action__c WHERE Part__c = :g.partId ORDER BY CreatedDate DESC LIMIT 200]) {
            fas.add(new Row(f.Id, f.Name, f.Title__c, f.Status__c, null, f.CreatedDate, null, 'Field_Action__c'));
        }
        section(l, 'Field actions on the part', fas, null);
    }

    /** One relevant record; sorts same lot first, then open, then newest. */
    public class Row implements Comparable {
        public String text; public Boolean sameLot; public Boolean open; public Datetime created;
        public Row(Id id, String name, String title, String status, String lot, Datetime created, String ncLot, String obj) {
            this.sameLot = ncLot != null && lot == ncLot;
            this.open = !CLOSED.contains(status == null ? '' : status.toLowerCase());
            this.created = created;
            this.text = '- ' + link(name, id, obj) + (String.isBlank(title) ? '' : ': ' + title) + '. ' + s(status)
                + (lot == null ? '' : ', lot ' + lot + (this.sameLot ? ' (same lot)' : '')) + ', created ' + created.date().format() + '.';
        }
        public Integer compareTo(Object o) {
            Row r = (Row) o;
            if (sameLot != r.sameLot) { return sameLot ? -1 : 1; }
            if (open != r.open) { return open ? -1 : 1; }
            return created == r.created ? 0 : created > r.created ? -1 : 1;
        }
    }
    static final Set<String> CLOSED = new Set<String>{ 'closed', 'complete', 'completed', 'void', 'cancelled', 'canceled' };

    @TestVisible
    static void section(List<String> l, String heading, List<Row> rows, String lot) {
        Integer same = 0; Integer open = 0;
        for (Row r : rows) { if (r.sameLot) { same++; } if (r.open) { open++; } }
        l.add(heading + ': ' + rows.size() + (rows.isEmpty() ? '.' : ' (' + open + ' open' + (lot == null ? '' : ', ' + same + ' on lot ' + lot) + '), most relevant first:'));
        rows.sort();
        for (Integer i = 0; i < Math.min(rows.size(), MAX_ROWS); i++) { l.add(rows[i].text); }
        if (rows.size() > MAX_ROWS) { l.add('and ' + (rows.size() - MAX_ROWS) + ' more.'); }
    }

    // ---------------------------------------------------------------- helpers

    static Map<String, Object> parseDraft(String json) {
        if (String.isBlank(json)) { return null; }
        try {
            Map<String, Object> m = (Map<String, Object>) System.JSON.deserializeUntyped(json);
            return m != null && intOf(m.get('v')) == 1 ? m : null;
        } catch (Exception e) { return null; }
    }
    /** The triage notes, one "Step: choice" line per step, as a map. */
    @TestVisible
    static Map<String, String> notesMap(String notes) {
        Map<String, String> m = new Map<String, String>();
        if (String.isBlank(notes)) { return m; }
        for (String line : notes.split('\n')) {
            if (line.contains(': ')) { m.put(line.substringBefore(': ').trim(), line.substringAfter(': ').trim().removeEnd('.')); }
        }
        return m;
    }
    static CqTriageController.Card card(CqTriageController.Glance g, String id) {
        for (CqTriageController.Card c : g.cards) { if (c.id == id) { return c; } }
        return new CqTriageController.Card();
    }
    static String factOf(CqTriageController.Card c, String k) {
        for (CqTriageController.Fact f : c.facts) { if (f.k == k) { return f.v; } }
        return 'not known';
    }
    static Integer intOf(Object o) { return o == null ? 0 : Integer.valueOf(String.valueOf(o)); }
    static String link(String label, Id id, String obj) { return id == null ? s(label) : '[' + label + '](/lightning/r/' + obj + '/' + id + '/view)'; }
    static String dot(String v) { return v.endsWith('.') ? v : v + '.'; }
    static String stage(String v) { return v == null ? 'not set' : v == 'Disposition_Investigate' ? 'Disposition / Investigate' : v; }
    static String yn(Boolean b) { return b == true ? 'yes' : 'no'; }
    static String s(String v) { return String.isBlank(v) ? 'not set' : v; }
    static String n(Decimal v) { return v == null ? 'not known' : v.stripTrailingZeros().toPlainString(); }
    static String d(Date v) { return v == null ? 'not set' : v.format(); }
    static String d(Datetime v) { return v == null ? 'not set' : v.date().format(); }
}

/**
 * CqFieldActionAgentContext
 * -------------------------
 * Invocable action for the CQ.AI Field Action agent. Given a Field Action Review or a Field Action,
 * returns everything the workspace shows as plain text, so the agent answers from the same facts
 * the user sees: the review (risk, CQ.AI suggestion, decision, committee), and for a field action
 * its Scope, Strategy, Recovery, tasks and Closure checklist.
 *
 * Read only. The workspace views keep some records in step as they load (customers, tasks, holds);
 * here all of that runs inside a savepoint that is rolled back, so the action changes nothing.
 */
global with sharing class CqFieldActionAgentContext {

    @TestVisible static final Integer MAX_ROWS = 20;

    global class Request {
        @InvocableVariable(label='Record Id' description='The Field Action Review or Field Action currently open in the conversation.' required=true)
        global Id recordId;
    }

    global class Response {
        @InvocableVariable(label='Field Action Facts' description='Everything the workspace shows for this record, as plain text sections. Answer only from this.')
        global String facts;
    }

    @InvocableMethod(
        label='Get Field Action Facts'
        description='Reads a Field Action Review or a Field Action and returns what its workspace shows: for a review, the source record, part and lot, risk score and factors, the CQ.AI suggestion and why, the decision, the committee approval, signals and related records; for a field action, Scope (lots, shipped, on hand, locations), Strategy (action type, depth, customer instruction, key message, effectiveness check, holds), Recovery (customers, responses, units recovered, verdict), tasks, and the Closure checklist. Read only: it creates and changes nothing.'
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
        if (recordId == null) { return 'No record was given, so I cannot tell which field action to read.'; }
        String type = String.valueOf(recordId.getSObjectType());
        List<String> lines = new List<String>();
        Savepoint sp = Database.setSavepoint();
        try {
            if (type == 'Field_Action_Review__c') {
                CqFieldActionReview.View rv = CqFieldActionReview.getView(recordId);
                review(lines, rv);
                if (rv.faId != null) {
                    lines.add('');
                    lines.add('The field action opened from this review follows.');
                    fieldAction(lines, rv.faId);
                }
            } else if (type == 'Field_Action__c') {
                fieldAction(lines, recordId);
            } else {
                lines.add('This record is a ' + recordId.getSObjectType().getDescribe().getLabel()
                    + ', not a Field Action Review or Field Action. The Field Action agent only reads those two.');
            }
        } catch (Exception e) {
            lines.add('The record could not be read: ' + e.getMessage());
        } finally {
            Database.rollback(sp);
        }
        return String.join(lines, '\n');
    }

    // ---------------------------------------------------------------- review

    static void review(List<String> l, CqFieldActionReview.View v) {
        l.add('FIELD ACTION REVIEW ' + v.name + ': ' + s(v.title));
        l.add('Status: ' + s(v.status) + '. Reason for review: ' + dot(s(v.reason)));
        l.add('Requested by ' + s(v.requestedBy) + ' on ' + d(v.requestedOn) + '. Reviewer: ' + s(v.reviewer) + '. Due: ' + d(v.due) + '.');
        if (v.sourceName != null) { l.add('Raised from ' + s(v.sourceKind) + ' ' + v.sourceName + ': ' + s(v.sourceTitle) + '.'); }
        if (v.problem != null) { l.add('The problem: ' + v.problem); }
        l.add('Part: ' + s(v.partName) + '. Lot: ' + s(v.lot) + '. Quantity affected: ' + n(v.qtyAffected) + '. Quantity shipped: ' + n(v.qtyShipped) + '.');
        l.add('Reached the field: ' + (v.reachedField ? 'yes' : 'no, as far as the records show') + '.');

        l.add('');
        l.add('RISK');
        l.add('Risk score ' + v.score + ' of 100 (' + s(v.band) + '). Risk level set on the review: ' + s(v.riskLevel) + '.');
        for (CqFieldActionReview.Factor f : v.factors) { l.add('- ' + f.name + ': ' + f.pts + ' of ' + f.max + ' points. ' + s(f.detail)); }
        if (v.hazard != null) { l.add('Health hazard summary: ' + v.hazard); }

        l.add('');
        l.add('WHAT IS KNOWN');
        for (CqFieldActionReview.Know k : v.know) {
            l.add('- ' + k.q + ' ' + (k.a == null || k.unknown == true ? 'Not known' : k.a) + (k.src == null ? '' : ' (from ' + k.src + ')'));
        }

        l.add('');
        l.add('CQ.AI SUGGESTS: ' + s(v.suggestedOutcome) + '. Why: ' + s(v.suggestedWhy));
        if (v.outcome != null) {
            l.add('Decision: ' + v.outcome + ', by ' + s(v.decidedBy) + ' on ' + d(v.decidedOn) + '. Rationale: ' + s(v.rationale));
        } else {
            l.add('Decision: not made yet.');
        }
        if (v.committee != null && v.committee.approvalName != null) {
            CqFarCommittee.Info c = v.committee;
            l.add('Committee approval ' + c.approvalName + ': ' + s(c.approvalStatus) + (c.emergency ? ' (emergency approval: ' + s(c.emergencyReason) + ')' : '') + '.');
            for (CqFarCommittee.Step st : c.steps) {
                l.add('- ' + s(st.seat) + ': ' + s(st.person) + ', ' + s(st.status) + (st.doneOn == null ? '' : ' on ' + d(st.doneOn)) + (st.comment == null ? '' : '. Comment: ' + st.comment));
            }
            if (c.sentBack != null) { l.add('Sent back with: ' + c.sentBack); }
        }
        if (v.faName != null) { l.add('Field action opened: ' + v.faName + '.'); }
        if (!v.fieldActions.isEmpty()) {
            l.add('Field actions on this part:');
            for (CqFieldActionReview.Fa f : v.fieldActions) {
                l.add('- ' + f.name + ': ' + s(f.title) + ', ' + s(f.status) + ', ' + s(f.actionType) + ', lots ' + s(f.lots) + (f.suggested ? '. CQ.AI Suggests linking it: ' + s(f.why) : ''));
            }
        }

        if (!v.signals.isEmpty()) {
            l.add('');
            l.add('SIGNALS');
            for (CqFieldActionReview.Sig g : v.signals) {
                l.add('- ' + g.name + ': ' + s(g.label) + ', ' + s(g.strength) + ', trend ' + s(g.trend) + (g.thisLot ? ', on this lot' : '') + '. ' + s(g.why));
            }
        }

        if (!v.records.isEmpty()) {
            l.add('');
            l.add('RELEVANT RECORDS (' + v.records.size() + ')');
            Integer i = 0;
            for (CqFieldActionReview.Rec r : v.records) {
                if (i++ == MAX_ROWS) { l.add('- and ' + (v.records.size() - MAX_ROWS) + ' more'); break; }
                l.add('- ' + r.name + ' (' + s(r.kind) + ', ' + s(r.status) + '): ' + s(r.title) + (r.lot == null ? '' : ', lot ' + r.lot) + (r.sameLot ? ', same lot' : '') + (r.suggested ? '. ' + s(r.why) : ''));
            }
        }

        if (!v.trend.isEmpty() && !v.trendMonths.isEmpty()) {
            List<String> parts = new List<String>();
            for (CqFieldActionReview.Series sr : v.trend) {
                Integer t = 0; for (Integer c : sr.counts) { t += c == null ? 0 : c; }
                parts.add(t + ' ' + sr.name);
            }
            l.add('');
            l.add('On this part over the last 12 months (' + v.trendMonths[0] + ' to ' + v.trendMonths[v.trendMonths.size() - 1] + '): ' + String.join(parts, ', ') + '.');
        }
    }

    // ---------------------------------------------------------------- field action

    static void fieldAction(List<String> l, Id faId) {
        CqFieldActionScope.View sc = CqFieldActionScope.getView(faId);
        l.add('FIELD ACTION ' + sc.name + ': ' + s(sc.title));
        l.add('Status: ' + s(sc.status) + '. Action type: ' + s(sc.actionType) + '. Recall class: ' + s(sc.recallClass) + '.');
        l.add('Part: ' + s(sc.partNumber) + (sc.partName == null ? '' : ' (' + sc.partName + ')') + '. Quantity affected: ' + n(sc.qtyAffected) + '. Quantity shipped: ' + n(sc.qtyShipped) + '.');
        if (sc.description != null) { l.add('Description: ' + sc.description); }
        if (sc.rationale != null) { l.add('Decision rationale: ' + sc.rationale + ' (decided by ' + s(sc.decidedBy) + ' on ' + d(sc.decidedOn) + ')'); }
        for (CqFieldActionScope.Review r : sc.reviews) {
            l.add('From review ' + r.name + ' (source ' + s(r.source) + ', lot ' + s(r.lot) + '): ' + s(r.outcome) + ', risk ' + s(r.risk)
                + ', decided by ' + s(r.decidedBy) + (r.approvalName == null ? '' : ', committee approval ' + r.approvalName + (r.approvedBy == null ? '' : ' approved by ' + r.approvedBy))
                + (r.emergency ? ', emergency' : '') + '.');
        }

        // Scope
        l.add('');
        l.add('SCOPE (step 1)');
        l.add('Scope: ' + s(sc.scope) + '. Scope status: ' + s(sc.scopeStatus)
            + (sc.scopeConfirmedBy == null ? '' : ', confirmed by ' + sc.scopeConfirmedBy + ' on ' + d(sc.scopeConfirmedOn)) + '.');
        if (sc.pendingAdds > 0 || sc.pendingRemoves > 0) {
            l.add('Changes waiting to be confirmed: ' + sc.pendingAdds + ' lots to add, ' + sc.pendingRemoves + ' to remove.');
        }
        List<String> inScope = new List<String>(); List<String> suggested = new List<String>();
        for (CqFieldActionScope.LotRow r : sc.lots) {
            String row = '- ' + r.name + ': built ' + n(r.built) + ', shipped ' + n(r.shipped) + ', on hand ' + n(r.onHand)
                + (r.location == null ? '' : ' at ' + r.location) + ', ' + r.records + ' related records, ' + r.signals + ' signals'
                + (r.inScope && !r.confirmed ? ' (added, not confirmed yet)' : '') + (r.reason == null ? '' : '. Reason: ' + r.reason);
            if (r.inScope) { inScope.add(row); }
            else if (r.suggested) { suggested.add('- ' + r.name + ': ' + s(r.why)); }
        }
        l.add('Lots in scope (' + inScope.size() + '):');
        l.addAll(cap(inScope));
        if (!suggested.isEmpty()) { l.add('CQ.AI Suggests these lots too, not in scope:'); l.addAll(cap(suggested)); }
        if (!sc.changes.isEmpty()) {
            l.add('Recent scope changes:');
            Integer i = 0;
            for (CqFieldActionScope.Change c : sc.changes) {
                if (i++ == 5) { break; }
                l.add('- ' + c.lot + ' ' + s(c.change) + ' by ' + s(c.doneBy) + ' on ' + d(c.doneAt) + (c.reason == null ? '' : ': ' + c.reason));
            }
        }

        // Strategy
        CqFieldActionStrategy.View st = CqFieldActionStrategy.getView(faId);
        l.add('');
        l.add('STRATEGY (step 2)');
        if (!st.scopeConfirmed) {
            l.add('Not open yet: the scope must be confirmed first.');
        } else {
            l.add('Strategy status: ' + s(st.status) + (st.confirmedBy == null ? '' : ', confirmed by ' + st.confirmedBy + ' on ' + d(st.confirmedOn)) + '.');
            l.add('Lots: ' + st.lotCount + '. Built: ' + n(st.built) + '. Shipped: ' + n(st.shipped) + '.');
            l.add('Action type: ' + s(st.action) + pick(st.sAction, st.action) + '.' + (st.whyAction == null ? '' : ' Why: ' + st.whyAction));
            l.add('Depth: ' + s(st.depth) + pick(st.sDepth, st.depth) + '.');
            l.add('Customer instruction: ' + s(st.instruction) + pick(st.sInstruction, st.instruction) + '.');
            l.add('Key message to customers: ' + s(st.message) + (st.message == null && st.sMessage != null ? ' CQ.AI Suggests: ' + st.sMessage : ''));
            l.add('Effectiveness check level: ' + s(st.level) + pick(st.sLevel, st.level) + (st.percent == null ? '' : ', ' + st.percent + '% of customers')
                + '.' + (st.whyLevel == null ? '' : ' Why: ' + st.whyLevel));
            l.add('Check method: ' + s(st.method) + pick(st.sMethod, st.method) + '. Check by: ' + d(st.checkBy) + (st.checkBy == null && st.sCheckBy != null ? ' (CQ.AI Suggests ' + d(st.sCheckBy) + ')' : '') + '.');
            l.add('Holds (' + st.holds.size() + '):');
            List<String> holds = new List<String>();
            for (CqFieldActionStrategy.HoldRow h : st.holds) {
                List<String> spots = new List<String>();
                for (CqLotStock.Place p : h.places) { spots.add(n(p.units) + ' at ' + s(p.location)); }
                holds.add('- ' + h.lot + ' (' + s(h.kind) + (h.part == null ? '' : ', ' + h.part) + '): '
                    + (h.held ? 'on hold since ' + d(h.heldOn) : h.hold ? 'hold chosen, not placed yet' : 'not held')
                    + ', on hand ' + n(h.onHand) + (spots.isEmpty() ? '' : ' (' + String.join(spots, '; ') + ')')
                    + (h.suggested && !h.hold ? '. CQ.AI Suggests holding it: ' + s(h.reason) : '')
                    + (h.outOfScope ? '. No longer in scope.' : ''));
            }
            l.addAll(cap(holds));
        }

        // Recovery, tasks and closure
        CqFieldActionRecovery.View rc = CqFieldActionRecovery.getView(faId);
        l.add('');
        l.add('RECOVERY (step 3)');
        if (!rc.strategyConfirmed) {
            l.add('Not open yet: the strategy must be confirmed first.');
        } else {
            l.add('Recovery status: ' + s(rc.recovery) + '. Effectiveness level ' + s(rc.level) + ', target ' + n(rc.target) + '% of customers responding, check by ' + d(rc.checkBy) + '.');
            l.add('Customers responded: ' + rc.acked + ' of ' + rc.total + '. Target met: ' + (rc.targetMet ? 'yes' : 'no') + '.');
            l.add('Units shipped: ' + (rc.shippedKnown ? n(rc.shipped) : 'not known') + '. Units recovered (returned, destroyed or corrected): ' + n(rc.recovered) + '.');
            for (CqFieldActionRecovery.LotRec r : rc.lots) {
                l.add('- Lot ' + r.lot + ': shipped ' + n(r.shipped) + ', returned ' + z(r.returned) + ', destroyed ' + z(r.destroyed) + ', corrected ' + z(r.corrected)
                    + ', still in the field ' + n(r.field) + (r.pct == null ? '' : ' (' + r.pct + '% recovered)'));
            }
            l.add('Customers (' + rc.customers.size() + '):');
            List<String> cust = new List<String>();
            for (CqFieldActionRecovery.Cust c : rc.customers) {
                cust.add('- ' + c.name + ': ' + n(c.units) + ' units of ' + s(c.lots) + ', ' + s(c.status)
                    + (c.respondedOn == null ? '' : ', responded ' + d(c.respondedOn)) + (c.followUps == null || c.followUps == 0 ? '' : ', ' + n(c.followUps) + ' follow-ups'));
            }
            l.addAll(cap(cust));
            if (!rc.holds.isEmpty()) {
                l.add('Held stock disposition:');
                for (CqFieldActionRecovery.HoldDisp h : rc.holds) {
                    l.add('- ' + h.lot + ', ' + n(h.onHand) + ' on hand: ' + (h.disposition == null ? 'not decided' : h.disposition)
                        + (h.disposition == null && h.suggested != null ? '. CQ.AI Suggests ' + h.suggested + ': ' + s(h.reason) : ''));
                }
            }
            if (rc.aiVerdict != null) { l.add('CQ.AI Suggests the verdict: ' + rc.aiVerdict + '. ' + s(rc.aiLine)); }
            l.add('Verdict: ' + (rc.verdict == null ? 'not chosen yet' : rc.verdict + (rc.nextStep == null ? '' : ', next step ' + rc.nextStep)
                + (rc.verdictBy == null ? ', chosen but not confirmed yet' : ', confirmed by ' + rc.verdictBy + ' on ' + d(rc.verdictOn))) + '.');
        }

        if (rc.tasks != null) {
            CqFieldActionTasks.Board b = rc.tasks;
            l.add('');
            l.add('TASKS');
            l.add(b.open + ' open, ' + b.completed + ' completed, ' + b.overdue + ' overdue, ' + b.dueWeek + ' due this week.');
            List<String> open = new List<String>();
            for (CqFieldActionTasks.TaskRow t : b.tasks) {
                if (t.done) { continue; }
                open.add('- ' + t.subject + ' (' + s(t.type) + '), owner ' + s(t.owner) + ', due ' + d(t.due) + (t.overdue ? ', OVERDUE' : ''));
            }
            l.addAll(cap(open));
            if (!b.suggestions.isEmpty()) { l.add('CQ.AI Suggests ' + b.suggestions.size() + ' more tasks. ' + s(b.suggestLine)); }
        }

        l.add('');
        l.add('CLOSURE (step 4)');
        if (rc.closed) {
            l.add('Closed by ' + s(rc.closedBy) + ' on ' + d(rc.closedOn) + '.');
        }
        for (CqFieldActionRecovery.Check c : rc.checks) {
            l.add('- ' + c.text + ': ' + (c.state == 'ok' ? 'done' : c.state == 'na' ? 'not needed' : 'open') + (c.blocks ? ', blocks closing' : '') + (c.detail == null ? '' : '. ' + c.detail));
        }
        if (!rc.closed) { l.add('Can close now: ' + (rc.canClose ? 'yes' : 'no') + '.'); }
        l.add('CAPA: ' + (rc.capaName == null ? 'none linked' : rc.capaName) + '. Closure summary: ' + (rc.summary == null ? 'not written' : rc.summary));
        if (rc.summary == null && rc.sSummary != null) { l.add('CQ.AI Suggests this closure summary: ' + rc.sSummary); }
    }

    // ---------------------------------------------------------------- helpers

    static List<String> cap(List<String> rows) {
        if (rows.size() <= MAX_ROWS) { return rows; }
        List<String> out = new List<String>();
        for (Integer i = 0; i < MAX_ROWS; i++) { out.add(rows[i]); }
        out.add('- and ' + (rows.size() - MAX_ROWS) + ' more');
        return out;
    }
    static String pick(String suggestion, String chosen) {
        if (suggestion == null) { return ''; }
        if (chosen == null) { return '. CQ.AI Suggests: ' + suggestion; }
        return suggestion == chosen ? ' (as CQ.AI Suggests)' : '. CQ.AI Suggested ' + suggestion;
    }
    static String dot(String v) { return v.endsWith('.') || v.endsWith('?') || v.endsWith('!') ? v : v + '.'; }
    static String z(Decimal v) { return v == null ? '0' : n(v); }
    static String s(String v) { return String.isBlank(v) ? 'not set' : v; }
    static String n(Decimal v) { return v == null ? 'not known' : v.stripTrailingZeros().toPlainString(); }
    static String d(Date v) { return v == null ? 'not set' : v.format(); }
    static String d(Datetime v) { return v == null ? 'not set' : v.date().format(); }
}

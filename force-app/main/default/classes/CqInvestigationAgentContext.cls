/**
 * CqInvestigationAgentContext
 * ---------------------------
 * Facts for the CQ.AI Quality agent (through CqQualityAgentContext, its one action) on the screens built after triage:
 *  - an Investigation: what the CQ.AI Investigation workspace shows on each of its six steps, including the Find the Cause
 *    hypotheses with what CQ.AI Suggests and why, their evidence, the Is / Is Not, the 5 Whys, the fishbone and the root causes;
 *  - a Nonconformance: the repeat problem flagged in triage (happened before after a CAPA closed) and the disposition.
 * The suggestions come from the same classes the screens use, so the agent explains the same thing the user sees.
 * Read only: the caller runs this inside a savepoint that is rolled back.
 */
public with sharing class CqInvestigationAgentContext {

    @TestVisible static final Integer MAX_ROWS = 8;

    // ---------------------------------------------------------------- Investigation
    public static void investigation(List<String> l, Id invId) {
        CqInvestigationWorkspace.View v = CqInvestigationWorkspace.getView(invId);
        l.add('INVESTIGATION ' + link(v.investigationName, v.investigationId));
        l.add('The CQ.AI Investigation workspace has six steps, opened in any order: Investigation at a Glance, What Changed, Check History, Find the Cause, Actions, Conclusion.');
        l.add('Nonconformance: ' + link(v.ncName, v.ncId) + (v.title == null ? '' : ', ' + v.title) + '. Part: ' + s(v.partNumber) + '. Lot: ' + s(v.lot) + '.');
        l.add('Status: ' + s(v.status) + '. Risk at triage: ' + s(v.risk) + '. Investigation due: ' + d(v.due) + '. Owner: ' + s(v.owner) + '. NC stage: ' + s(v.ncStage) + '.');
        l.add('The problem: ' + s(v.description == null ? v.title : v.description));
        l.add('Units affected: ' + n(v.defective) + '. Approval needed to complete: ' + yn(v.needsApproval) + '.');
        if (v.isComplete) { l.add('The investigation is complete' + (v.completedBy == null ? '' : ', by ' + v.completedBy + ' on ' + d(v.completedOn)) + '.'); }
        else if (v.inApproval) { l.add('The investigation was submitted and is in approval.'); }

        // ---- 1 Glance
        l.add('');
        l.add('STEP 1 INVESTIGATION AT A GLANCE');
        l.add('Triage: risk ' + s(v.risk) + (v.path == null ? '' : ', path ' + v.path) + '.');
        l.add('Disposition: ' + (!v.dispositionRequired ? 'not required' : v.dispositionComplete ? 'complete' + (v.dispositionText == null ? '' : ' (' + v.dispositionText + ')') : 'still open') + '.');
        l.add('Root causes recorded in CQ: ' + (v.causes.isEmpty() ? 'none yet' : v.causes.size() + '') + '. Actions planned: ' + (v.plans.isEmpty() ? 'none yet' : v.plans.size() + '') + '.');
        Integer openTools = 0;
        for (CqInvestigationWorkspace.Tool t : v.tools) { if (t.status != 'Complete') { openTools++; } }
        if (!v.tools.isEmpty()) { l.add('Analysis tools in CQ: ' + v.tools.size() + ', ' + openTools + ' still open. Open tools are completed on Complete Investigation.'); }

        // ---- 2 What Changed
        l.add('');
        l.add('STEP 2 WHAT CHANGED');
        try {
            CqInvestigationChanges.View w = CqInvestigationChanges.getChanges(invId, 30);
            l.add('Start date: ' + d(w.startDate) + ' (from the NC\'s ' + s(w.startFrom) + '). Changes are looked for in the ' + w.days + ' days before it. CQ.AI Says Could Explain It for a change within 14 days before the start, or in effect on the part or a component; older changes are Unlikely.');
            if (w.items.isEmpty()) { l.add('CQ holds no changes on the part in that window.'); }
            for (CqInvestigationChanges.Item i : w.items) {
                l.add('- ' + (i.byHand ? i.name + ' (added by hand)' : link(i.name, i.recordId)) + ': ' + s(i.whatChanged) + '. '
                    + (i.inEffect ? 'In effect since ' + d(i.day) + (i.untilDay == null ? '' : ' until ' + d(i.untilDay)) : 'On ' + d(i.day))
                    + '. Found in ' + s(i.foundIn) + '. CQ.AI Says: ' + s(i.rating) + '.' + (i.hypothesis == null ? '' : ' Added as H' + i.hypothesis + '.'));
            }
            l.add('Fixture maintenance, operator assignments and line moves are not held in CQ; the investigator adds them by hand.');
        } catch (Exception e) { l.add('The changes could not be read: ' + e.getMessage()); }

        // ---- 3 Check History
        l.add('');
        l.add('STEP 3 CHECK HISTORY');
        try {
            CqInvestigationHistory.View h = CqInvestigationHistory.getHistory(invId);
            l.add('Past records on the part, ranked the same way as the Product History Review (part and BOM, the words of the problem, the defect code and failed inspections, open or recent). Red meets three of these, Yellow two.');
            for (CqInvestigationHistory.Item r : h.recurrences) {
                l.add('Happened before, and the fix did not hold: ' + link(r.name, r.recordId) + ' had the same problem on ' + d(r.day)
                    + (r.causeNote == null ? '' : ', root cause ' + r.causeNote) + '. ' + link(r.capaName, r.capaId) + (r.capaTitle == null ? '' : ' (' + r.capaTitle + ')')
                    + ' closed' + (r.capaClosed == null ? '' : ' on ' + d(r.capaClosed))
                    + (r.efrId == null ? ', with no effectiveness review on record' : '; ' + r.efrName + ' rated it ' + s(r.efrResolution) + ' on ' + d(r.efrDate))
                    + '. The problem came back on ' + d(h.startDate) + '.');
            }
            l.add('Records that match the problem or the lot: ' + h.items.size() + (h.items.isEmpty() ? '.' : ', most relevant first:'));
            for (Integer k = 0; k < Math.min(h.items.size(), MAX_ROWS); k++) {
                CqInvestigationHistory.Item r = h.items[k];
                l.add('- ' + link(r.name, r.recordId) + ' (' + s(r.type) + ', ' + s(r.status) + (r.day == null ? '' : ', ' + d(r.day)) + '): ' + s(r.whatHappened)
                    + '. Root cause: ' + (r.causeHead == null ? 'none recorded' : r.causeHead + (r.causeNote == null ? '' : ', ' + r.causeNote))
                    + '. Fix: ' + (r.capaId == null ? 'no CAPA' : link(r.capaName, r.capaId) + ' ' + s(r.capaStatus))
                    + '. Match ' + s(r.colour) + ' ' + r.score + (r.why == null ? '' : ' (' + r.why + ')') + '.' + (r.hypothesis == null ? '' : ' Added as H' + r.hypothesis + '.'));
            }
            if (h.items.size() > MAX_ROWS) { l.add('and ' + (h.items.size() - MAX_ROWS) + ' more.'); }
            l.add('Other records on the part that match the part only, not the problem: ' + h.others.size() + '.');
            if (!h.dismissed.isEmpty()) {
                List<String> names = new List<String>();
                for (CqInvestigationHistory.Dismissed x : h.dismissed) { names.add(x.name + (x.atTriage ? ' (Not the Same Problem, at triage)' : '')); }
                l.add('Marked Not Relevant: ' + String.join(names, ', ') + '.');
            }
        } catch (Exception e) { l.add('The history could not be read: ' + e.getMessage()); }

        // ---- 4 Find the Cause
        l.add('');
        l.add('STEP 4 FIND THE CAUSE');
        try { cause(l, invId); } catch (Exception e) { l.add('The hypotheses could not be read: ' + e.getMessage()); }

        // ---- 5 Actions
        l.add('');
        l.add('STEP 5 ACTIONS');
        l.add('A correction fixes what is broken now; a corrective action removes the cause; a preventive action stops it happening elsewhere. Actions are saved as CQ action plans on the investigation and become CQ actions when it is complete.');
        if (v.plans.isEmpty()) { l.add('No actions planned yet.'); }
        for (CqInvestigationWorkspace.Plan p : v.plans) {
            l.add('- ' + s(p.title) + ' (' + s(p.type) + '), due ' + d(p.due) + ', owner ' + s(p.userName) + '.');
        }

        // ---- 6 Conclusion
        l.add('');
        l.add('STEP 6 CONCLUSION');
        l.add('Conclusion: ' + s(v.conclusion) + '. Choices: ' + String.join(v.conclusions, ', ') + '.');
        l.add('Investigation summary: ' + (String.isBlank(v.summary) ? 'not written yet' : v.summary.abbreviate(600)));
        l.add(v.needsApproval
            ? 'On Submit for Approval: CQ saves the conclusion, summary and actions and sends the investigation for approval; once approved, the NC moves to Implement and the actions are made.'
            : 'On Complete Investigation: CQ saves the conclusion, summary and actions, completes the investigation and moves the NC to Implement; each action plan becomes a CQ action with its owner and due date.');
    }

    /** Find the Cause: hypotheses, evidence, Is / Is Not, 5 Why, fishbone and root causes. */
    static void cause(List<String> l, Id invId) {
        CqInvestigationCause.View c = CqInvestigationCause.getCause(invId);
        l.add('Find the Cause has five tabs: Hypotheses, Is / Is Not, 5 Why, Fishbone and Root Causes. Every hypothesis starts Open; the investigator decides Confirmed or Ruled Out.');
        l.add('How CQ.AI Suggests works (rules over the evidence, the same evidence always gives the same suggestion): Unlikely when any evidence goes against it (including a row of the Is / Is Not it does not fit); Likely when at least two pieces of evidence support it and either a test supports it or it fits at least two Is / Is Not rows; otherwise Needs Evidence, with the test that would settle it for its category.');
        Map<Id, String> codeName = new Map<Id, String>();
        for (CqInvestigationCause.Code k : c.codes) { codeName.put(k.id, k.name); }

        l.add('Hypotheses: ' + c.hyps.size() + (c.hyps.isEmpty() ? '. They are added from What Changed or Check History with Add as Hypothesis, or on a fishbone bone.' : '.'));
        for (CqInvestigationCause.Hyp h : c.hyps) {
            l.add('');
            l.add('H' + h.num + ': ' + h.title + '. Category ' + s(h.category) + '. Status ' + h.status + '. ' + s(h.origin) + (h.sourceName == null ? '' : ' (' + h.sourceName + ')') + '.');
            l.add('CQ.AI Suggests ' + s(h.suggest) + '. Why: ' + s(h.suggestWhy));
            l.add('Tests: ' + h.testsDone + ' done, ' + h.testsPlanned + ' planned.');
            List<String> ck = new List<String>();
            for (CqInvestigationCause.Check k : h.checks) { ck.add((k.ok ? 'met: ' : 'not met: ') + k.text); }
            if (!ck.isEmpty()) { l.add('Could this be the root cause? ' + String.join(ck, ' | ')); }
            if (h.evidence.isEmpty()) { l.add('Evidence: none yet.'); }
            else {
                l.add('Evidence:');
                for (CqInvestigationCause.Evidence e : h.evidence) { l.add(evLine(e)); }
            }
            l.add('How do you know: ' + (String.isNotBlank(h.howKnow) ? h.howKnow : h.howKnowDraft == null ? 'not written yet' : 'not written yet (the screen starts it as: ' + h.howKnowDraft + ')'));
            if (!h.whys.isEmpty()) {
                l.add('5 Why' + (h.toolId == null ? '' : ' (saved in CQ as ' + link(h.toolName, h.toolId) + ')') + ':');
                for (CqInvestigationCause.Why w : h.whys) {
                    l.add('- Why ' + w.level + ': ' + s(w.text) + (w.isRoot ? ' [marked Root Cause]' : ''));
                    for (CqInvestigationCause.Evidence e : w.evidence) { l.add('  ' + evLine(e)); }
                }
            }
        }
        if (!c.newHyps.isEmpty()) {
            l.add('');
            l.add('Changes that could explain it but no hypothesis covers (shown as CQ.AI Suggests a Hypothesis):');
            for (CqInvestigationCause.NewHyp n : c.newHyps) { l.add('- ' + n.text); }
        }

        // Is / Is Not
        l.add('');
        l.add('IS / IS NOT (saved in CQ\'s 5W2H' + (c.isNotPrefilled ? '; not saved yet, filled in from the NC' : '') + '):');
        for (CqInvestigationCause.Row r : c.rows) {
            List<String> fits = new List<String>();
            for (CqInvestigationCause.Hyp h : c.hyps) {
                String f = h.fits.get(r.key);
                if (f == 'fits') { fits.add('H' + h.num + ' fits'); } else if (f == 'fails') { fits.add('H' + h.num + ' does not fit'); }
            }
            l.add('- ' + r.label + ': Is ' + s(r.isText) + '; Is Not ' + s(r.isNotText) + (fits.isEmpty() ? '' : '. ' + String.join(fits, ', ')) + '.');
        }

        // Fishbone
        List<String> used = new List<String>();
        List<String> noneOn = new List<String>();
        List<String> cats = new List<String>(c.categories);
        for (CqInvestigationCause.Hyp h : c.hyps) { if (h.category != null && !cats.contains(h.category)) { cats.add(h.category); } }
        for (String cat : cats) {
            List<String> onBone = new List<String>();
            for (CqInvestigationCause.Hyp h : c.hyps) { if (h.category == cat) { onBone.add('H' + h.num + ' ' + h.status); } }
            if (onBone.isEmpty()) { noneOn.add(cat); } else { used.add(cat + ' (' + String.join(onBone, ', ') + ')'); }
        }
        l.add('');
        l.add('FISHBONE (a view of the hypotheses by category, not saved to CQ): hypotheses on ' + (used.isEmpty() ? 'no category yet' : String.join(used, '; '))
            + '.' + (noneOn.isEmpty() ? '' : ' No hypothesis yet on ' + String.join(noneOn, ', ') + '.'));

        // Root causes
        l.add('');
        l.add('ROOT CAUSES (rows come from confirmed hypotheses and the whys marked Root Cause; Primary would cause the problem on its own, Contributing made it more likely or worse; there can be more than one Primary):');
        if (c.roots.isEmpty()) { l.add('None yet. A hypothesis must be Confirmed first.'); }
        for (CqInvestigationCause.RootRow r : c.roots) {
            l.add('- ' + s(r.text) + ' (' + s(r.source) + '). ' + s(r.role) + ', category ' + s(r.category) + ', CQ cause code ' + (r.codeId == null ? 'not chosen' : s(codeName.get(r.codeId)))
                + '. Evidence: ' + s(r.evidence) + '. Verified: ' + yn(r.verified) + '. ' + (r.saved ? 'Saved in CQ as ' + link('a root cause', r.id) : 'Not saved to CQ yet') + '.');
        }
        if (!c.openHyps.isEmpty()) { l.add('Still Open: ' + String.join(c.openHyps, ', ') + '.'); }
    }

    static String evLine(CqInvestigationCause.Evidence e) {
        String sup = e.supports == 'Against' ? ' Goes against it.' : e.supports == 'Inconclusive' ? ' Inconclusive.' : e.supports == 'Came Back' ? ' The problem came back after that fix.' : '';
        return '- ' + s(e.tag) + ': ' + s(e.text) + (e.recordId == null ? '' : ' (' + link(e.recordName, e.recordId) + ')') + '.' + sup + (e.origin == null ? '' : ' ' + e.origin + '.');
    }

    // ---------------------------------------------------------------- Nonconformance extras
    /** The repeat problem flagged in triage, and the disposition. */
    public static void ncExtras(List<String> l, Id ncId) {
        l.add('');
        l.add('HAPPENED BEFORE');
        try {
            CqTriageRepeat.Repeat r = CqTriageRepeat.getRepeat(ncId);
            compliancequest__SQX_Nonconformance__c nc = [SELECT Repeat_Of__c, Repeat_Of__r.Name, Repeat_Decision__c, Repeat_Decision_Reason__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
            if (r == null || r.found != true) {
                l.add('No earlier NC on the part had the same problem after a CAPA closed.');
            } else {
                l.add('The same problem happened before: ' + link(r.ncName, r.ncId) + ' on ' + d(r.ncDay) + (r.whatHappened == null ? '' : ' (' + r.whatHappened + ')')
                    + (r.causeNote == null ? '' : ', root cause ' + r.causeNote) + '. ' + link(r.capaName, r.capaId) + (r.capaTitle == null ? '' : ' (' + r.capaTitle + ')')
                    + ' closed' + (r.capaClosed == null ? '' : ' on ' + d(r.capaClosed))
                    + (r.efrId == null ? ', with no effectiveness review on record' : '; ' + r.efrName + ' rated it ' + s(r.efrResolution) + ' on ' + d(r.efrDate))
                    + '. It came back on ' + d(r.startDate) + '.');
                l.add('Because it happened before, the risk likelihood is raised one step, and an investigation is suggested.');
                l.add('CQ.AI Suggests Escalate to CAPA. Why: The same problem came back after ' + r.capaName + (r.effective ? ' was marked effective' : ' closed')
                    + ', so that fix did not deal with why it happened. An investigation of this NC alone would likely repeat the same fix.');
                l.add('The choices on Next Steps: Escalate to CAPA (sets CQ\'s Initiate CAPA), Link to Earlier CAPA (sets CQ\'s Related CAPA to ' + r.capaName + '; a closed CAPA is never reopened), or Not Needed with a reason. Not the Same Problem drops the earlier NC.');
            }
            if (nc.Repeat_Decision__c != null) {
                l.add('Chosen at triage: ' + nc.Repeat_Decision__c + (nc.Repeat_Of__c == null ? '' : ' (repeat of ' + link(nc.Repeat_Of__r.Name, nc.Repeat_Of__c) + ')')
                    + (String.isBlank(nc.Repeat_Decision_Reason__c) ? '' : '. Reason: ' + nc.Repeat_Decision_Reason__c) + '.');
            }
            if (r != null && r.dismissed != null && !r.dismissed.isEmpty()) {
                List<String> names = new List<String>();
                for (CqInvestigationHistory.Dismissed x : r.dismissed) { names.add(x.name); }
                l.add('Marked Not the Same Problem: ' + String.join(names, ', ') + '.');
            }
        } catch (Exception e) { l.add('Could not be read: ' + e.getMessage()); }

        l.add('');
        l.add('DISPOSITION');
        try {
            CqDispositionWorkspace.View v = CqDispositionWorkspace.getView(ncId);
            l.add('The CQ.AI Disposition workspace has two steps: Disposition at a Glance and Dispose by Lot. Due ' + d(v.dispDue) + '. Approval needed: ' + yn(v.needsApproval) + '. Complete: ' + yn(v.isComplete) + '.');
            if (v.suggestType == null) { l.add('No disposition is suggested: ' + s(v.suggestWhy)); }
            else { l.add('CQ.AI Suggests ' + s(v.suggestType) + '. Why: ' + s(v.suggestWhy)); }
            l.add('Disposition types: ' + String.join(v.types, ', ') + '.');
            for (CqDispositionWorkspace.Lot t : v.lots) {
                l.add('- Lot ' + s(t.lot) + ' of ' + s(t.partName) + ': ' + n(t.impacted) + ' impacted, ' + n(t.disposed) + ' disposed, ' + n(t.left) + ' left.');
                for (CqDispositionWorkspace.Rec rc : t.records) {
                    l.add('  - ' + link(rc.name, rc.id) + ': ' + s(rc.type) + ' ' + n(rc.qty) + ', ' + s(rc.status) + (rc.completedOn == null ? '' : ', completed ' + d(rc.completedOn)) + '.');
                }
            }
            if (!v.history.isEmpty()) {
                List<String> past = new List<String>();
                for (CqDispositionWorkspace.Past p : v.history) { past.add(p.ncName + ' ' + s(p.type) + ' ' + n(p.qty)); }
                l.add('Done with this part before: ' + String.join(past, '; ') + '.');
            }
        } catch (Exception e) { l.add('No disposition to show: ' + e.getMessage()); }
    }

    // ---------------------------------------------------------------- helpers
    static String link(String label, Id id) { return id == null ? s(label) : '[' + s(label) + '](/lightning/r/' + id + '/view)'; }
    static String s(String v) { return String.isBlank(v) ? 'not set' : v; }
    static String yn(Boolean b) { return b == true ? 'yes' : 'no'; }
    static String n(Decimal v) { return v == null ? 'not known' : v.stripTrailingZeros().toPlainString(); }
    static String d(Date v) { return v == null ? 'not set' : v.format(); }
}

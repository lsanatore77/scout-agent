/**
 * CqInvestigationSummary: CQ.AI Suggested Summary on the Conclusion step of the CQ.AI Investigation workspace.
 *
 * suggest() gathers the facts for the five sections of the summary (Problem, Containment, Hypotheses, Root Cause,
 * Actions) and runs the Prompt Builder template CQAI_Investigation_Summary, which writes them up.
 * The prompt wording lives in Prompt Builder, so it can be edited there without changing this class.
 * The actions come from the screen, so actions not saved yet are in the summary too.
 *
 * toHtml() and toPlain(): CQ's Investigation Summary is a rich text field. The screen edits plain text with the
 * section headers on their own lines; it is saved as simple HTML (bold headers, paragraphs, bullets) so it reads
 * properly on the record, and turned back into plain text when the screen reads it.
 */
public with sharing class CqInvestigationSummary {

    @TestVisible static final String TEMPLATE_NAME = 'CQAI_Investigation_Summary';
    @TestVisible static final String INPUT_NAME = 'Input:Investigation_Data';
    @TestVisible static String mockResponse;
    @TestVisible static Boolean mockFail = false;
    public static final List<String> HEADERS = new List<String>{ 'Problem', 'Containment', 'Hypotheses', 'Root Cause', 'Actions' };

    @AuraEnabled
    public static String suggest(Id recordId, String actionsPayload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        String data = buildData(invId, actionsPayload);
        try {
            return clean(runTemplate(data));
        } catch (Exception e) {
            throw new AuraHandledException('CQ.AI could not write the summary just now. Try again, or write it yourself. (' + e.getMessage() + ')');
        }
    }

    // ---------------------------------------------------------------- the facts, by section
    @TestVisible
    static String buildData(Id invId, String actionsPayload) {
        List<String> l = new List<String>();
        CqInvestigationWorkspace.View v = CqInvestigationWorkspace.getView(invId);
        l.add('INVESTIGATION ' + v.investigationName + ' on nonconformance ' + s(v.ncName) + '.');

        // ---- Problem
        l.add('');
        l.add('## PROBLEM');
        l.add('Title: ' + s(v.title) + '.');
        l.add('Description: ' + s(v.description) + '.');
        l.add('Part: ' + s(v.partNumber) + '. Lot: ' + s(v.lot) + '. Units affected: ' + n(v.defective) + '. Risk at triage: ' + s(v.risk) + '.');
        try {
            CqInvestigationChanges.View w = CqInvestigationChanges.getChanges(invId, 14);
            l.add('The problem started on ' + d(w.startDate) + ' (the NC\'s ' + s(w.startFrom) + ').');
        } catch (Exception e) { l.add('Start date: not known.'); }

        // ---- Containment
        l.add('');
        l.add('## CONTAINMENT');
        if (!v.dispositionRequired) {
            l.add('Disposition was not required on this NC. Leave the Containment section out.');
        } else {
            l.add('Disposition is ' + (v.dispositionComplete ? 'complete' : 'still open') + (v.dispositionText == null ? '' : ': ' + v.dispositionText) + '.');
            try {
                CqDispositionWorkspace.View dv = CqDispositionWorkspace.getView(v.ncId);
                for (CqDispositionWorkspace.Lot t : dv.lots) {
                    l.add('- Lot ' + s(t.lot) + ' of ' + s(t.partName) + ': ' + n(t.impacted) + ' impacted, ' + n(t.disposed) + ' disposed, ' + n(t.left) + ' not disposed yet.');
                    for (CqDispositionWorkspace.Rec rc : t.records) {
                        l.add('  - ' + s(rc.type) + ' ' + n(rc.qty) + ', ' + s(rc.status) + (rc.completedOn == null ? '' : ', completed ' + d(rc.completedOn)) + '.');
                    }
                }
            } catch (Exception e) { /* the disposition text above is enough */ }
        }

        // ---- Hypotheses and Root Cause (Find the Cause)
        CqInvestigationCause.View c;
        try { c = CqInvestigationCause.getCause(invId); } catch (Exception e) { c = null; }
        l.add('');
        l.add('## HYPOTHESES');
        if (c == null || c.hyps.isEmpty()) { l.add('None recorded.'); }
        else {
            for (CqInvestigationCause.Hyp h : c.hyps) {
                l.add('- H' + h.num + ': ' + h.title + '. Category ' + s(h.category) + '. Status ' + s(h.status) + '.'
                    + (h.sourceName == null ? '' : ' Came from ' + h.sourceName + '.'));
                if (String.isNotBlank(h.howKnow)) { l.add('  How we know: ' + h.howKnow); }
                for (CqInvestigationCause.Evidence e : h.evidence) {
                    String sup = e.supports == 'Against' ? ' (goes against it)' : e.supports == 'Inconclusive' ? ' (inconclusive)' : e.supports == 'Came Back' ? ' (the problem came back after that fix)' : '';
                    l.add('  Evidence: ' + s(e.tag) + ': ' + s(e.text) + (e.recordName == null ? '' : ' (' + e.recordName + ')') + sup + '.');
                }
                for (CqInvestigationCause.Why y : h.whys) {
                    l.add('  Why ' + y.level + ': ' + s(y.text) + (y.isRoot ? ' (marked root cause)' : ''));
                }
            }
        }

        l.add('');
        l.add('## ROOT CAUSE');
        Map<Id, String> codeName = new Map<Id, String>();
        if (c != null) { for (CqInvestigationCause.Code k : c.codes) { codeName.put(k.id, k.name); } }
        if (c != null && !c.roots.isEmpty()) {
            for (CqInvestigationCause.RootRow r : c.roots) {
                l.add('- ' + s(r.text) + '. ' + s(r.role) + ', category ' + s(r.category) + (r.codeId == null ? '' : ', cause code ' + s(codeName.get(r.codeId)))
                    + '. Evidence: ' + s(r.evidence) + '. Verified: ' + (r.verified ? 'yes' : 'no') + '.');
            }
        } else if (!v.causes.isEmpty()) {
            for (CqInvestigationWorkspace.Cause k : v.causes) {
                l.add('- ' + s(k.description) + '. Category ' + s(k.category) + ', cause code ' + s(k.code) + '. Verified: ' + (k.verified ? 'yes' : 'no') + '.');
            }
        } else {
            l.add('None recorded.');
        }
        try {
            CqInvestigationHistory.View hv = CqInvestigationHistory.getHistory(invId);
            for (CqInvestigationHistory.Item r : hv.recurrences) {
                l.add('Happened before: ' + r.name + ' had the same problem on ' + d(r.day) + (r.causeNote == null ? '' : ', root cause ' + r.causeNote)
                    + '. Its fix ' + s(r.capaName) + (r.capaTitle == null ? '' : ' (' + r.capaTitle + ')') + ' closed' + (r.capaClosed == null ? '' : ' on ' + d(r.capaClosed))
                    + (r.efrId == null ? ', with no effectiveness review' : ', and ' + r.efrName + ' rated it ' + s(r.efrResolution) + ' on ' + d(r.efrDate))
                    + '. The problem came back, so that fix did not hold.');
            }
        } catch (Exception e) { /* no history to add */ }

        // ---- Actions (from the screen when given, so unsaved actions are included)
        l.add('');
        l.add('## ACTIONS');
        List<String> acts = actionLines(v, actionsPayload);
        if (acts.isEmpty()) { l.add('None recorded.'); } else { l.addAll(acts); }
        return String.join(l, '\n');
    }

    static List<String> actionLines(CqInvestigationWorkspace.View v, String actionsPayload) {
        List<String> out = new List<String>();
        if (actionsPayload == null) {
            for (CqInvestigationWorkspace.Plan p : v.plans) { out.add(actionLine(p.title, p.type, p.description, p.userName, p.due)); }
            return out;
        }
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(actionsPayload);
        Set<Id> userIds = new Set<Id>();
        for (Object o : rows) {
            Map<String, Object> m = (Map<String, Object>) o;
            if (m.get('userId') != null) { userIds.add((Id) String.valueOf(m.get('userId'))); }
        }
        Map<Id, User> users = new Map<Id, User>([SELECT Id, Name FROM User WHERE Id IN :userIds]);
        for (Object o : rows) {
            Map<String, Object> m = (Map<String, Object>) o;
            Id uid = m.get('userId') == null ? null : (Id) String.valueOf(m.get('userId'));
            String owner = uid == null ? UserInfo.getName() : users.containsKey(uid) ? users.get(uid).Name : null;
            String due = m.get('due') == null ? null : String.valueOf(m.get('due'));
            out.add(actionLine(str(m.get('title')), str(m.get('type')), str(m.get('description')), owner, String.isBlank(due) ? null : Date.valueOf(due)));
        }
        return out;
    }

    static String actionLine(String title, String type, String description, String owner, Date due) {
        Boolean descNew = String.isNotBlank(description) && description.trim() != (title == null ? '' : title.trim());
        // an owner that is not known is left out, so the summary never says "not set"
        return '- ' + s(title) + ' (' + s(type) + ')' + (String.isBlank(owner) ? '' : ', owner ' + owner) + ', due ' + d(due) + '.' + (descNew ? ' Description: ' + description.trim() : '');
    }

    // ---------------------------------------------------------------- the prompt template
    @TestVisible
    static String runTemplate(String data) {
        ConnectApi.WrappedValue dataValue = new ConnectApi.WrappedValue();
        dataValue.value = data;
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{ INPUT_NAME => dataValue };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = 'PromptBuilderPreview';
        if (Test.isRunningTest()) {
            if (mockFail) { throw new SummaryException('no answer'); }
            return mockResponse == null ? 'Problem\nTEST SUMMARY' : mockResponse;
        }
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output =
            ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(TEMPLATE_NAME, input);
        if (output.generations == null || output.generations.isEmpty() || String.isBlank(output.generations[0].text)) {
            throw new SummaryException('The prompt template returned no text.');
        }
        return output.generations[0].text;
    }

    /** Plain text with the headers on their own lines: markdown marks taken off. */
    @TestVisible
    static String clean(String text) {
        List<String> out = new List<String>();
        for (String line : text.replace('\r', '').split('\n')) {
            String t = line.replace('**', '').replaceFirst('^#+\\s*', '').trim();
            if (t.endsWith(':') && HEADERS.contains(t.removeEnd(':').trim())) { t = t.removeEnd(':').trim(); }
            if (t.startsWith('* ') || t.startsWith('• ')) { t = '- ' + t.substring(2); }
            out.add(t);
        }
        return String.join(out, '\n').replaceAll('\n{3,}', '\n\n').trim();
    }

    // ---------------------------------------------------------------- rich text field
    /** Plain text (headers on their own lines, "- " bullets) to the simple HTML saved in CQ's rich text summary. */
    public static String toHtml(String text) {
        if (text == null) { return null; }
        List<String> html = new List<String>();
        List<String> para = new List<String>();
        Boolean inList = false;
        for (String raw : text.replace('\r', '').split('\n')) {
            String line = raw.trim();
            Boolean bullet = line.startsWith('- ');
            if (line == '' || HEADERS.contains(line) || bullet) {
                if (!para.isEmpty()) { html.add('<p>' + String.join(para, '<br>') + '</p>'); para.clear(); }
            }
            if (!bullet && inList) { html.add('</ul>'); inList = false; }
            if (line == '') { continue; }
            if (HEADERS.contains(line)) { html.add('<p><b>' + line.escapeHtml4() + '</b></p>'); }
            else if (bullet) {
                if (!inList) { html.add('<ul>'); inList = true; }
                html.add('<li>' + line.substring(2).trim().escapeHtml4() + '</li>');
            } else { para.add(line.escapeHtml4()); }
        }
        if (!para.isEmpty()) { html.add('<p>' + String.join(para, '<br>') + '</p>'); }
        if (inList) { html.add('</ul>'); }
        return String.join(html, '');
    }

    /** CQ's rich text summary back to plain text for the screen (also handles a summary typed in CQ). */
    public static String toPlain(String html) {
        if (html == null || !html.contains('<')) { return html; }
        String t = html.replaceAll('(?i)<p>\\s*<(b|strong)>([^<]*)</(b|strong)>\\s*</p>', '$2\n')
            .replaceAll('(?i)<br\\s*/?>', '\n')
            .replaceAll('(?i)</p>|</div>|</h[1-6]>', '\n\n')
            .replaceAll('(?i)<li[^>]*>', '- ')
            .replaceAll('(?i)</li>|</ul>|</ol>', '\n')
            .replaceAll('<[^>]+>', '')
            .unescapeHtml4().replace('\u00a0', ' ');
        List<String> out = new List<String>();
        for (String line : t.split('\n')) { out.add(line.trim()); }
        return String.join(out, '\n').replaceAll('\n{3,}', '\n\n').trim();
    }

    static String str(Object o) { return o == null ? null : String.valueOf(o); }
    static String s(String v) { return String.isBlank(v) ? 'not set' : v; }
    static String n(Decimal v) { return v == null ? 'not known' : v.stripTrailingZeros().toPlainString(); }
    static String d(Date v) { return v == null ? 'not set' : v.format(); }

    public class SummaryException extends Exception {}
}

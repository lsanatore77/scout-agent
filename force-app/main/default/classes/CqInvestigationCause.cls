/**
 * CqInvestigationCause: the Find the Cause step of the CQ.AI Investigation workspace.
 *
 * Hypotheses (Investigation_Hypothesis__c) are tested with evidence (Investigation_Evidence__c: tests planned or done,
 * linked CQ records, pinned Ask CQ.AI answers) and against the Is / Is Not, which is CQ's own 5W2H on the investigation
 * (Is and Is Not kept together in each field). Each hypothesis can have a 5 Why, kept in CQ's own records: a 5 Why
 * investigation tool with its Why records. Root causes are saved as CQ root causes with a Role (Primary or Contributing).
 *
 * CQ.AI Suggests (Likely, Unlikely, Needs Evidence) is worked out here by rule from the evidence, so the same evidence
 * gives the same suggestion. The person decides Confirmed or Ruled Out.
 */
public with sharing class CqInvestigationCause {

    public static final List<String> ROWS = new List<String>{ 'what', 'where', 'when', 'who', 'which', 'how', 'howMany' };
    public static final Map<String, String> ROW_LABEL = new Map<String, String>{ 'what' => 'What', 'where' => 'Where', 'when' => 'When',
        'who' => 'Who', 'which' => 'Which', 'how' => 'How', 'howMany' => 'How Many' };
    public static final Map<String, String> ROW_FIELD = new Map<String, String>{ 'what' => 'compliancequest__What__c', 'where' => 'compliancequest__Where__c',
        'when' => 'compliancequest__When__c', 'who' => 'compliancequest__Who__c', 'which' => 'compliancequest__Which__c',
        'how' => 'compliancequest__How__c', 'howMany' => 'compliancequest__How_Many__c' };
    /** CQ's cause category records use slightly different names from the root cause Category picklist. */
    public static final Map<String, String> CATEGORY_OF = new Map<String, String>{ 'Man (People)' => 'People', 'Material' => 'Materials',
        'Environment' => 'Environment (Nature)' };
    /** What test settles a hypothesis in each category, for Needs Evidence. */
    public static final Map<String, String> TEST_HINT = new Map<String, String>{
        'Machine' => 'Measure or inspect the equipment, or compare units made on it with units made elsewhere.',
        'Method' => 'Compare units made with and without the change in method.',
        'Materials' => 'Check the material lot records or certificate, or compare lots.',
        'Measurement' => 'Check the gauge calibration and repeat the measurement.',
        'People' => 'Check training records and who made the affected units.',
        'Environment (Nature)' => 'Check the environmental records for the time the units were made.' };

    public class Row { @AuraEnabled public String key; @AuraEnabled public String label; @AuraEnabled public String isText; @AuraEnabled public String isNotText; }
    public class Check { @AuraEnabled public Boolean ok; @AuraEnabled public String text; @AuraEnabled public String key; }
    public class Evidence {
        @AuraEnabled public String key; @AuraEnabled public Id id; @AuraEnabled public String kind; @AuraEnabled public String tag;
        @AuraEnabled public String text; @AuraEnabled public String origin; @AuraEnabled public String supports; @AuraEnabled public String status;
        @AuraEnabled public String testType; @AuraEnabled public String result; @AuraEnabled public String recordId; @AuraEnabled public String recordName;
        @AuraEnabled public Id ownerId; @AuraEnabled public String ownerName; @AuraEnabled public Date due; @AuraEnabled public Date doneOn;
        @AuraEnabled public Boolean auto = false; @AuraEnabled public Integer files = 0;
    }
    public class Why {
        @AuraEnabled public Id id; @AuraEnabled public Integer level; @AuraEnabled public String text; @AuraEnabled public Boolean isRoot = false;
        @AuraEnabled public List<Evidence> evidence = new List<Evidence>();
    }
    public class Hyp {
        @AuraEnabled public Id id; @AuraEnabled public Integer num; @AuraEnabled public String title; @AuraEnabled public String category;
        @AuraEnabled public String status; @AuraEnabled public String sourceName; @AuraEnabled public String sourceId; @AuraEnabled public String origin;
        @AuraEnabled public String howKnow; @AuraEnabled public Map<String, String> fits = new Map<String, String>();
        @AuraEnabled public Id toolId; @AuraEnabled public String toolName; @AuraEnabled public Id rootCauseId;
        @AuraEnabled public List<Why> whys = new List<Why>();
        @AuraEnabled public List<Evidence> evidence = new List<Evidence>();
        @AuraEnabled public List<Check> checks = new List<Check>();
        @AuraEnabled public String suggest; @AuraEnabled public String suggestWhy; @AuraEnabled public String testHint;
        @AuraEnabled public Boolean cameBack = false; @AuraEnabled public Integer testsDone = 0; @AuraEnabled public Integer testsPlanned = 0;
        @AuraEnabled public String howKnowDraft;
    }
    public class Code { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String category; @AuraEnabled public String sub; }
    public class RootRow {
        @AuraEnabled public String key; @AuraEnabled public Id id; @AuraEnabled public Id hypId; @AuraEnabled public Id whyId;
        @AuraEnabled public String text; @AuraEnabled public String source; @AuraEnabled public String role; @AuraEnabled public String category;
        @AuraEnabled public Id codeId; @AuraEnabled public String evidence; @AuraEnabled public Boolean verified = false; @AuraEnabled public Boolean saved = false;
    }
    public class NewHyp { @AuraEnabled public String key; @AuraEnabled public String sourceId; @AuraEnabled public String name; @AuraEnabled public String text; @AuraEnabled public String category; }
    public class View {
        @AuraEnabled public Id investigationId; @AuraEnabled public String investigationName; @AuraEnabled public String problem;
        @AuraEnabled public Id fiveId; @AuraEnabled public Boolean isNotPrefilled = false;
        @AuraEnabled public List<Row> rows = new List<Row>();
        @AuraEnabled public List<Hyp> hyps = new List<Hyp>();
        @AuraEnabled public List<String> categories = new List<String>();
        @AuraEnabled public List<Code> codes = new List<Code>();
        @AuraEnabled public List<RootRow> roots = new List<RootRow>();
        @AuraEnabled public List<NewHyp> newHyps = new List<NewHyp>();
        @AuraEnabled public List<String> openHyps = new List<String>();
    }

    // ------------------------------------------------------------------ read
    @AuraEnabled
    public static View getCause(Id recordId) { return build(recordId, true); }

    /** The whole step. The changes no hypothesis covers are looked for on the first read only (it reads What Changed). */
    static View build(Id recordId, Boolean withNew) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        View v = new View();
        v.investigationId = invId;
        compliancequest__SQX_Investigation__c inv = [SELECT Name, compliancequest__SQX_Nonconformance__c FROM compliancequest__SQX_Investigation__c WHERE Id = :invId];
        v.investigationName = inv.Name;
        for (Schema.PicklistEntry p : compliancequest__SQX_Root_Cause__c.compliancequest__Category__c.getDescribe().getPicklistValues()) { if (p.isActive()) { v.categories.add(p.getValue()); } }
        for (compliancequest__SQX_Root_Cause_Code__c c : [
                SELECT Id, Name, compliancequest__SQX_Root_Cause_Sub_Category__c, compliancequest__SQX_Root_Cause_Sub_Category__r.Name,
                       compliancequest__SQX_Root_Cause_Sub_Category__r.compliancequest__SQX_Root_Cause_Category__r.Name
                FROM compliancequest__SQX_Root_Cause_Code__c ORDER BY Name LIMIT 500]) {
            Code k = new Code(); k.id = c.Id; k.name = c.Name;
            if (c.compliancequest__SQX_Root_Cause_Sub_Category__r != null) {
                k.sub = c.compliancequest__SQX_Root_Cause_Sub_Category__r.Name;
                String cat = c.compliancequest__SQX_Root_Cause_Sub_Category__r.compliancequest__SQX_Root_Cause_Category__r == null ? null
                    : c.compliancequest__SQX_Root_Cause_Sub_Category__r.compliancequest__SQX_Root_Cause_Category__r.Name;
                k.category = CATEGORY_OF.containsKey(cat) ? CATEGORY_OF.get(cat) : cat;
            }
            v.codes.add(k);
        }

        // the problem, and the Is / Is Not from CQ's 5W2H (or filled in from the NC)
        compliancequest__SQX_Nonconformance__c nc;
        if (inv.compliancequest__SQX_Nonconformance__c != null) {
            nc = [SELECT Name, compliancequest__NC_Title__c, compliancequest__Description__c, compliancequest__Occurrence_Date__c, compliancequest__Lot_Number__c,
                         compliancequest__Defective_Quantity__c, compliancequest__SQX_Part__r.compliancequest__Part_Number__c
                  FROM compliancequest__SQX_Nonconformance__c WHERE Id = :inv.compliancequest__SQX_Nonconformance__c];
            v.problem = String.isBlank(nc.compliancequest__Description__c) ? nc.compliancequest__NC_Title__c
                : nc.compliancequest__Description__c.removeStartIgnoreCase('SAMPLE DATA. ').abbreviate(240);
        }
        List<compliancequest__SQX_5W2H__c> fives = [SELECT Id, compliancequest__What__c, compliancequest__Where__c, compliancequest__When__c, compliancequest__Who__c,
                compliancequest__Which__c, compliancequest__How__c, compliancequest__How_Many__c
            FROM compliancequest__SQX_5W2H__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate DESC LIMIT 1];
        Boolean anyText = false;
        for (String k : ROWS) {
            Row r = new Row(); r.key = k; r.label = ROW_LABEL.get(k);
            if (!fives.isEmpty()) {
                v.fiveId = fives[0].Id;
                List<String> pair = split((String) fives[0].get(ROW_FIELD.get(k)));
                r.isText = pair[0]; r.isNotText = pair[1];
                if (String.isNotBlank(r.isText) || String.isNotBlank(r.isNotText)) { anyText = true; }
            }
            v.rows.add(r);
        }
        if (!anyText && nc != null) {
            v.isNotPrefilled = true;
            for (Row r : v.rows) {
                if (r.key == 'what') { r.isText = nc.compliancequest__NC_Title__c; }
                if (r.key == 'when' && nc.compliancequest__Occurrence_Date__c != null) { r.isText = 'From ' + toDate(nc.compliancequest__Occurrence_Date__c).format() + (nc.compliancequest__Lot_Number__c == null ? '' : ' (lot ' + nc.compliancequest__Lot_Number__c + ')'); }
                if (r.key == 'which' && nc.compliancequest__SQX_Part__r != null) { r.isText = nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c; }
                if (r.key == 'howMany' && nc.compliancequest__Defective_Quantity__c != null) { r.isText = nc.compliancequest__Defective_Quantity__c.stripTrailingZeros().toPlainString() + ' units defective'; }
            }
        }
        Map<String, Row> rowByKey = new Map<String, Row>();
        Integer filled = 0;
        for (Row r : v.rows) { rowByKey.put(r.key, r); if (!v.isNotPrefilled && (String.isNotBlank(r.isText) || String.isNotBlank(r.isNotText))) { filled++; } }

        // hypotheses with their evidence and 5 Why
        List<Investigation_Hypothesis__c> hs = [
            SELECT Id, Number__c, Title__c, Category__c, Status__c, Source_Name__c, Source_Record_Id__c, How_Do_You_Know__c, Is_Not_Fit__c,
                   Five_Why_Tool__c, Five_Why_Tool__r.Name, Root_Cause__c, Investigation_Change__c
            FROM Investigation_Hypothesis__c WHERE Investigation__c = :invId ORDER BY Number__c];
        Set<Id> toolIds = new Set<Id>(); Set<Id> hypIds = new Set<Id>();
        for (Investigation_Hypothesis__c h : hs) { hypIds.add(h.Id); if (h.Five_Why_Tool__c != null) { toolIds.add(h.Five_Why_Tool__c); } }
        Map<Id, List<compliancequest__SQX_Why__c>> whysByTool = new Map<Id, List<compliancequest__SQX_Why__c>>();
        Set<Id> whyIds = new Set<Id>();
        for (compliancequest__SQX_Why__c w : [SELECT Id, compliancequest__SQX_Investigation_Tool__c, compliancequest__Level__c, compliancequest__Because__c, compliancequest__Is_Root_Cause__c
                FROM compliancequest__SQX_Why__c WHERE compliancequest__SQX_Investigation_Tool__c IN :toolIds ORDER BY compliancequest__Level__c, CreatedDate]) {
            if (!whysByTool.containsKey(w.compliancequest__SQX_Investigation_Tool__c)) { whysByTool.put(w.compliancequest__SQX_Investigation_Tool__c, new List<compliancequest__SQX_Why__c>()); }
            whysByTool.get(w.compliancequest__SQX_Investigation_Tool__c).add(w);
            whyIds.add(w.Id);
        }
        Map<Id, List<Investigation_Evidence__c>> evByHyp = new Map<Id, List<Investigation_Evidence__c>>();
        Map<Id, List<Investigation_Evidence__c>> evByWhy = new Map<Id, List<Investigation_Evidence__c>>();
        Set<Id> evIds = new Set<Id>();
        for (Investigation_Evidence__c e : [SELECT Id, Hypothesis__c, Why__c, Kind__c, Test_Type__c, Supports__c, Status__c, Detail__c, Result__c, Record_Id__c, Record_Name__c,
                    Owner__c, Owner__r.Name, Due_Date__c, Done_On__c, CreatedBy.Name, CreatedDate
                FROM Investigation_Evidence__c WHERE Hypothesis__c IN :hypIds OR Why__c IN :whyIds ORDER BY CreatedDate]) {
            evIds.add(e.Id);
            if (e.Why__c != null) {
                if (!evByWhy.containsKey(e.Why__c)) { evByWhy.put(e.Why__c, new List<Investigation_Evidence__c>()); }
                evByWhy.get(e.Why__c).add(e);
            } else if (e.Hypothesis__c != null) {
                if (!evByHyp.containsKey(e.Hypothesis__c)) { evByHyp.put(e.Hypothesis__c, new List<Investigation_Evidence__c>()); }
                evByHyp.get(e.Hypothesis__c).add(e);
            }
        }
        Map<Id, Integer> fileCount = new Map<Id, Integer>();
        if (!evIds.isEmpty()) {
            for (ContentDocumentLink l : [SELECT LinkedEntityId FROM ContentDocumentLink WHERE LinkedEntityId IN :evIds]) {
                fileCount.put(l.LinkedEntityId, (fileCount.containsKey(l.LinkedEntityId) ? fileCount.get(l.LinkedEntityId) : 0) + 1);
            }
        }
        Map<String, Evidence> sourceFacts = sourceFacts(hs, v);

        for (Investigation_Hypothesis__c h : hs) {
            Hyp x = new Hyp();
            x.id = h.Id; x.num = h.Number__c == null ? null : h.Number__c.intValue(); x.title = h.Title__c; x.category = h.Category__c;
            x.status = h.Status__c == null ? 'Open' : h.Status__c; x.sourceName = h.Source_Name__c; x.sourceId = h.Source_Record_Id__c;
            x.howKnow = h.How_Do_You_Know__c; x.toolId = h.Five_Why_Tool__c; x.toolName = h.Five_Why_Tool__r == null ? null : h.Five_Why_Tool__r.Name;
            x.rootCauseId = h.Root_Cause__c;
            x.origin = h.Investigation_Change__c != null || h.Source_Name__c == 'Added by You' ? 'Added by you'
                : h.Source_Record_Id__c == null ? 'Added here' : (h.Source_Record_Id__c.startsWith(compliancequest__SQX_Nonconformance__c.SObjectType.getDescribe().getKeyPrefix())
                    || h.Source_Record_Id__c.startsWith(compliancequest__SQX_Inspection__c.SObjectType.getDescribe().getKeyPrefix()) ? 'From Check History' : 'From What Changed');
            if (String.isNotBlank(h.Is_Not_Fit__c)) {
                try {
                    Map<String, Object> fm = (Map<String, Object>) JSON.deserializeUntyped(h.Is_Not_Fit__c);
                    for (String k : fm.keySet()) { x.fits.put(k, (String) fm.get(k)); }
                } catch (Exception e) { x.fits.clear(); }
            }
            // evidence: what CQ already holds, then tests, linked records and pinned answers
            Evidence src = h.Source_Record_Id__c == null ? null : sourceFacts.get(h.Source_Record_Id__c.left(15));
            if (src != null) { x.evidence.add(src); if (src.supports == 'Came Back') { x.cameBack = true; } }
            List<String> fitRows = new List<String>(); List<String> failRows = new List<String>();
            for (String k : ROWS) {
                String f = x.fits.get(k);
                if (f == 'fits') { fitRows.add(ROW_LABEL.get(k)); }
                if (f == 'fails') { failRows.add(ROW_LABEL.get(k) + (String.isBlank(rowByKey.get(k).isNotText) ? '' : ': not ' + rowByKey.get(k).isNotText)); }
            }
            if (!fitRows.isEmpty() || !failRows.isEmpty()) {
                Evidence e = new Evidence(); e.key = 'isnot:' + h.Id; e.kind = 'Is / Is Not'; e.tag = 'From CQ'; e.auto = true;
                e.supports = failRows.isEmpty() ? 'For' : 'Against';
                e.text = (fitRows.isEmpty() ? '' : 'Fits ' + String.join(fitRows, ', ') + '. ') + (failRows.isEmpty() ? '' : 'Does not fit ' + String.join(failRows, '; ') + '.');
                e.origin = 'Is / Is Not';
                x.evidence.add(e);
            }
            Integer forCount = 0; Integer againstCount = 0; Boolean testFor = false; String againstText; String forTest;
            for (Evidence e : x.evidence) {
                if (e.supports == 'For' || e.supports == 'Came Back') { forCount++; }
                if (e.supports == 'Against') { againstCount++; if (againstText == null) { againstText = e.text; } }
            }
            if (evByHyp.containsKey(h.Id)) {
                for (Investigation_Evidence__c r : evByHyp.get(h.Id)) {
                    Evidence e = toEvidence(r, fileCount);
                    x.evidence.add(e);
                    if (r.Kind__c == 'Test' && r.Status__c == 'Planned') { x.testsPlanned++; continue; }
                    if (r.Kind__c == 'Test') { x.testsDone++; }
                    if (r.Supports__c == 'For') { forCount++; if (r.Kind__c == 'Test') { testFor = true; if (forTest == null) { forTest = r.Result__c; } } }
                    if (r.Supports__c == 'Against') { againstCount++; if (againstText == null) { againstText = String.isBlank(r.Result__c) ? r.Detail__c : r.Result__c; } }
                }
            }
            // 5 Why
            Boolean rootWhy = false; String rootWhyText;
            if (h.Five_Why_Tool__c != null && whysByTool.containsKey(h.Five_Why_Tool__c)) {
                Integer i = 0;
                for (compliancequest__SQX_Why__c w : whysByTool.get(h.Five_Why_Tool__c)) {
                    i++;
                    Why y = new Why(); y.id = w.Id; y.level = i; y.text = w.compliancequest__Because__c; y.isRoot = w.compliancequest__Is_Root_Cause__c == true;
                    if (y.isRoot && !rootWhy) { rootWhy = true; rootWhyText = y.text; }
                    if (evByWhy.containsKey(w.Id)) { for (Investigation_Evidence__c r : evByWhy.get(w.Id)) { y.evidence.add(toEvidence(r, fileCount)); } }
                    x.whys.add(y);
                }
            }
            // CQ.AI Suggests, by rule
            x.testHint = TEST_HINT.get(h.Category__c);
            if (againstCount > 0) {
                x.suggest = 'Unlikely';
                x.suggestWhy = againstText == null ? 'Evidence goes against it.' : againstText.abbreviate(160);
            } else if (forCount >= 2 && (testFor || fitRows.size() >= 2)) {
                x.suggest = 'Likely';
                List<String> bits = new List<String>();
                if (!fitRows.isEmpty()) { bits.add(fitRows.size() == filled && filled > 0 ? 'fits every Is / Is Not row' : 'fits ' + String.join(fitRows, ', ')); }
                if (forTest != null) { bits.add(forTest.uncapitalize().removeEnd('.')); }
                if (src != null && src.kind == 'Past Case') { bits.add('same cause as ' + h.Source_Name__c); }
                x.suggestWhy = bits.isEmpty() ? 'The evidence supports it.' : String.join(bits, '; ').capitalize() + '.';
            } else {
                x.suggest = 'Needs Evidence';
                x.suggestWhy = forCount == 0 ? 'No evidence for or against it yet. ' + (x.testHint == null ? '' : x.testHint)
                    : 'Only one piece of evidence so far. ' + (x.testHint == null ? '' : x.testHint);
            }
            // Could This Be the Root Cause?
            Check c1 = new Check(); c1.key = 'fit';
            if (!failRows.isEmpty()) { c1.ok = false; c1.text = 'It does not fit the Is / Is Not: ' + String.join(failRows, '; ') + '.'; }
            else if (filled > 0 && fitRows.size() >= filled) { c1.ok = true; c1.text = 'It explains what is and what is not affected (every Is / Is Not row).'; }
            else if (filled == 0) { c1.ok = false; c1.text = 'Fill in the Is / Is Not, then mark whether it explains each row.'; }
            else { c1.ok = false; c1.text = 'Check it against the Is / Is Not: ' + fitRows.size() + ' of ' + filled + ' rows marked so far.'; }
            x.checks.add(c1);
            Check c2 = new Check(); c2.key = 'test'; c2.ok = testFor;
            c2.text = testFor ? 'It is backed by a test, not only a likely story.' : (x.testsPlanned > 0 ? 'A test is planned; until it is done this is only likely.' : 'No test yet: a test would prove it, not only make it likely.');
            x.checks.add(c2);
            if (x.cameBack) {
                Check c3 = new Check(); c3.key = 'back'; c3.ok = rootWhy;
                c3.text = rootWhy ? 'It came back after a fix, and the 5 Why reaches why: ' + rootWhyText.uncapitalize().removeEnd('.') + '.'
                    : 'It came back after a fix: ask why in 5 Why before you call this the root cause.';
                x.checks.add(c3);
            }
            // a starting line for How Do You Know?
            List<String> draft = new List<String>();
            if (forTest != null) { draft.add(forTest.removeEnd('.')); }
            if (!fitRows.isEmpty() && failRows.isEmpty()) { draft.add('fits the Is / Is Not (' + String.join(fitRows, ', ') + ')'); }
            if (!failRows.isEmpty()) { draft.add('does not fit ' + String.join(failRows, '; ')); }
            if (src != null && src.kind == 'Past Case') { draft.add('same cause as ' + h.Source_Name__c); }
            x.howKnowDraft = draft.isEmpty() ? null : String.join(draft, '; ').capitalize() + '.';
            if (x.status == 'Open') { v.openHyps.add('H' + x.num); }
            v.hyps.add(x);
        }

        // a change that could explain it but no hypothesis covers
        Set<String> covered = new Set<String>();
        for (Investigation_Hypothesis__c h : hs) { if (h.Source_Record_Id__c != null) { covered.add(h.Source_Record_Id__c.left(15)); } }
        if (withNew) { try {
            CqInvestigationChanges.View w = CqInvestigationChanges.getChanges(invId, 30);
            for (CqInvestigationChanges.Item it : w.items) {
                if (it.rating != 'Could Explain It' || it.hypothesis != null || it.recordId == null || covered.contains(String.valueOf(it.recordId).left(15))) { continue; }
                NewHyp n = new NewHyp(); n.key = it.key; n.sourceId = it.recordId; n.name = it.name; n.category = it.category;
                n.text = it.name + ': ' + (it.whatChanged == null ? '' : it.whatChanged.uncapitalize().removeEnd('.')) + ', ' + daysBefore(it.day, w.startDate) + '; no hypothesis covers it.';
                v.newHyps.add(n);
                if (v.newHyps.size() == 2) { break; }
            }
        } catch (Exception e) { v.newHyps.clear(); } }

        v.roots = roots(invId, v.hyps, v.codes);
        return v;
    }

    static String daysBefore(Date d, Date start) {
        if (d == null || start == null) { return 'before the start'; }
        Integer n = d.daysBetween(start);
        return n == 0 ? 'on the start date' : n + (n == 1 ? ' day' : ' days') + ' before the start';
    }

    /** What the record a hypothesis came from says, as evidence: a past NC with its root cause and fix, or the change. */
    static Map<String, Evidence> sourceFacts(List<Investigation_Hypothesis__c> hs, View v) {
        Map<String, Evidence> out = new Map<String, Evidence>();
        Set<Id> ncIds = new Set<Id>(); Set<Id> changeIds = new Set<Id>(); Map<Id, Investigation_Hypothesis__c> other = new Map<Id, Investigation_Hypothesis__c>();
        for (Investigation_Hypothesis__c h : hs) {
            if (h.Investigation_Change__c != null) { changeIds.add(h.Investigation_Change__c); continue; }
            if (h.Source_Record_Id__c == null) { continue; }
            Id sid;
            try { sid = Id.valueOf(h.Source_Record_Id__c); } catch (Exception e) { continue; }
            if (sid.getSObjectType() == compliancequest__SQX_Nonconformance__c.SObjectType) { ncIds.add(sid); } else { other.put(sid, h); }
        }
        if (!ncIds.isEmpty()) {
            Map<Id, compliancequest__SQX_Nonconformance__c> ncs = new Map<Id, compliancequest__SQX_Nonconformance__c>([
                SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Occurrence_Date__c, compliancequest__SQX_Investigation__c,
                       compliancequest__SQX_CAPA__c, compliancequest__SQX_CAPA__r.Name, compliancequest__SQX_CAPA__r.compliancequest__Title__c, compliancequest__SQX_CAPA__r.compliancequest__Status__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :ncIds]);
            Set<Id> invs = new Set<Id>();
            for (compliancequest__SQX_Nonconformance__c n : ncs.values()) { if (n.compliancequest__SQX_Investigation__c != null) { invs.add(n.compliancequest__SQX_Investigation__c); } }
            Map<Id, compliancequest__SQX_Root_Cause__c> rcByInv = new Map<Id, compliancequest__SQX_Root_Cause__c>();
            for (compliancequest__SQX_Root_Cause__c rc : [SELECT compliancequest__SQX_Investigation__c, compliancequest__Category__c, compliancequest__Description__c, compliancequest__Root_Cause_Code_Name__c
                    FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c IN :invs ORDER BY CreatedDate]) {
                if (!rcByInv.containsKey(rc.compliancequest__SQX_Investigation__c)) { rcByInv.put(rc.compliancequest__SQX_Investigation__c, rc); }
            }
            for (compliancequest__SQX_Nonconformance__c n : ncs.values()) {
                Evidence e = new Evidence(); e.key = 'src:' + n.Id; e.kind = 'Past Case'; e.tag = 'From CQ'; e.auto = true; e.supports = 'For';
                List<String> bits = new List<String>{ n.Name + (n.compliancequest__Occurrence_Date__c == null ? '' : ' (' + toDate(n.compliancequest__Occurrence_Date__c).format() + ')') + ': ' + n.compliancequest__NC_Title__c };
                compliancequest__SQX_Root_Cause__c rc = rcByInv.get(n.compliancequest__SQX_Investigation__c);
                if (rc != null) { bits.add('root cause ' + rc.compliancequest__Category__c + (rc.compliancequest__Root_Cause_Code_Name__c == null ? '' : ', ' + rc.compliancequest__Root_Cause_Code_Name__c) + (rc.compliancequest__Description__c == null ? '' : ': ' + rc.compliancequest__Description__c.uncapitalize())); }
                if (n.compliancequest__SQX_CAPA__c != null) {
                    String st = n.compliancequest__SQX_CAPA__r.compliancequest__Status__c;
                    bits.add('fixed by ' + n.compliancequest__SQX_CAPA__r.Name + ' (' + n.compliancequest__SQX_CAPA__r.compliancequest__Title__c + ', ' + st + ')');
                    if (st == 'Closed' || st == 'Complete') { e.supports = 'Came Back'; }
                }
                e.text = String.join(bits, '; ') + '.';
                e.origin = 'Check History';
                e.recordId = n.Id; e.recordName = n.Name;
                out.put(String.valueOf(n.Id).left(15), e);
            }
        }
        for (Id sid : other.keySet()) {
            Investigation_Hypothesis__c h = other.get(sid);
            Evidence e = new Evidence(); e.key = 'src:' + sid; e.kind = 'Change'; e.tag = 'From CQ'; e.auto = true; e.supports = 'For';
            e.text = 'Came from ' + h.Source_Name__c + ', found in What Changed or Check History.';
            e.origin = sid.getSObjectType().getDescribe().getLabel(); e.recordId = sid; e.recordName = h.Source_Name__c;
            out.put(String.valueOf(sid).left(15), e);
        }
        return out;
    }

    static Evidence toEvidence(Investigation_Evidence__c r, Map<Id, Integer> fileCount) {
        Evidence e = new Evidence();
        e.key = r.Id; e.id = r.Id; e.kind = r.Kind__c; e.supports = r.Supports__c; e.status = r.Status__c; e.testType = r.Test_Type__c;
        e.result = r.Result__c; e.recordId = r.Record_Id__c; e.recordName = r.Record_Name__c; e.ownerId = r.Owner__c;
        e.ownerName = r.Owner__r == null ? null : r.Owner__r.Name; e.due = r.Due_Date__c; e.doneOn = r.Done_On__c;
        e.files = fileCount.containsKey(r.Id) ? fileCount.get(r.Id) : 0;
        if (r.Kind__c == 'Test') {
            e.tag = r.Status__c == 'Planned' ? 'Test Planned' : 'Test Done';
            e.text = r.Test_Type__c + ': ' + (r.Status__c == 'Planned' || String.isBlank(r.Result__c) ? r.Detail__c : r.Result__c);
            List<String> o = new List<String>();
            if (r.Status__c == 'Planned') {
                if (r.Owner__r != null) { o.add('Owner ' + r.Owner__r.Name); }
                if (r.Due_Date__c != null) { o.add('due ' + r.Due_Date__c.format()); }
            } else {
                if (r.Done_On__c != null) { o.add(r.Done_On__c.format()); }
                o.add(r.Owner__r != null ? r.Owner__r.Name : r.CreatedBy.Name);
                if (String.isNotBlank(r.Result__c) && String.isNotBlank(r.Detail__c)) { o.add(r.Detail__c.abbreviate(120)); }
            }
            List<String> clean = new List<String>();
            for (String s : o) { if (String.isNotBlank(s)) { clean.add(s); } }
            e.origin = String.join(clean, ' · ');
        } else if (r.Kind__c == 'Ask CQ.AI') {
            e.tag = 'From Ask CQ.AI'; e.text = r.Detail__c; e.origin = 'Pinned from an Ask CQ.AI answer by ' + r.CreatedBy.Name;
        } else {
            e.tag = 'CQ Record'; e.text = String.isBlank(r.Result__c) ? r.Record_Name__c : r.Result__c; e.origin = 'Linked by ' + r.CreatedBy.Name;
        }
        return e;
    }

    /** Root cause rows: whys marked Root Cause and confirmed hypotheses, with the CQ root causes already saved. */
    static List<RootRow> roots(Id invId, List<Hyp> hyps, List<Code> codes) {
        Map<Id, compliancequest__SQX_Root_Cause__c> saved = new Map<Id, compliancequest__SQX_Root_Cause__c>([
            SELECT Id, compliancequest__Description__c, compliancequest__Category__c, compliancequest__SQX_Root_Cause_Code__c, compliancequest__Justification__c,
                   compliancequest__Verified__c, Cause_Role__c, compliancequest__SQX_Why__c
            FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate]);
        Map<Id, compliancequest__SQX_Root_Cause__c> byWhy = new Map<Id, compliancequest__SQX_Root_Cause__c>();
        for (compliancequest__SQX_Root_Cause__c rc : saved.values()) { if (rc.compliancequest__SQX_Why__c != null) { byWhy.put(rc.compliancequest__SQX_Why__c, rc); } }
        Set<Id> used = new Set<Id>();
        List<RootRow> out = new List<RootRow>();
        for (Hyp h : hyps) {
            if (h.status != 'Confirmed') { continue; }
            Boolean first = true; Boolean anyRoot = false;
            for (Why w : h.whys) {
                if (!w.isRoot) { continue; }
                anyRoot = true;
                RootRow r = new RootRow(); r.key = 'w:' + w.id; r.whyId = w.id; r.hypId = h.id; r.text = w.text;
                r.source = 'Why ' + w.level + ', H' + h.num; r.category = h.category; r.role = first ? 'Primary' : 'Contributing'; first = false;
                List<String> ev = new List<String>(); Boolean ver = false;
                for (Evidence e : w.evidence) { if (e.supports == 'For' && e.status != 'Planned') { ev.add(e.text); ver = true; } }
                r.evidence = ev.isEmpty() ? h.howKnow : String.join(ev, '; ');
                r.verified = ver;
                apply(r, byWhy.get(w.id), used);
                out.add(r);
            }
            RootRow r = new RootRow(); r.key = 'h:' + h.id; r.hypId = h.id; r.text = h.title.replaceAll(',\\s*as in [A-Z]+-[0-9]+$', '');
            r.source = 'H' + h.num; r.category = h.category; r.role = anyRoot ? 'Contributing' : 'Primary'; r.evidence = h.howKnow;
            r.verified = false;
            for (Evidence e : h.evidence) { if (!e.auto && e.supports == 'For' && e.status != 'Planned') { r.verified = true; } }
            apply(r, h.rootCauseId == null ? null : saved.get(h.rootCauseId), used);
            out.add(r);
        }
        for (compliancequest__SQX_Root_Cause__c rc : saved.values()) {
            if (used.contains(rc.Id)) { continue; }
            RootRow r = new RootRow(); r.key = 'r:' + rc.Id; r.source = 'In CQ'; r.text = rc.compliancequest__Description__c; r.category = rc.compliancequest__Category__c;
            r.role = rc.Cause_Role__c == null ? 'Contributing' : rc.Cause_Role__c;
            apply(r, rc, used);
            out.add(r);
        }
        for (RootRow r : out) { if (r.codeId == null) { r.codeId = suggestCode(r.text, r.category, codes); } }
        return out;
    }

    static void apply(RootRow r, compliancequest__SQX_Root_Cause__c rc, Set<Id> used) {
        if (rc == null) { return; }
        used.add(rc.Id);
        r.id = rc.Id; r.saved = true;
        if (String.isNotBlank(rc.compliancequest__Description__c)) { r.text = rc.compliancequest__Description__c; }
        if (rc.compliancequest__Category__c != null) { r.category = rc.compliancequest__Category__c; }
        r.codeId = rc.compliancequest__SQX_Root_Cause_Code__c;
        if (String.isNotBlank(rc.compliancequest__Justification__c)) { r.evidence = rc.compliancequest__Justification__c; }
        r.verified = rc.compliancequest__Verified__c == true;
        if (rc.Cause_Role__c != null) { r.role = rc.Cause_Role__c; }
    }

    /** The code in the category whose name shares the most words with the cause. */
    @TestVisible
    static Id suggestCode(String text, String category, List<Code> codes) {
        Set<String> words = new Set<String>();
        for (String w : (text == null ? '' : text.toLowerCase()).split('[^a-z]+')) { if (w.length() > 3) { words.add(w.removeEnd('s')); } }
        Id best; Integer bestScore = -1;
        for (Code c : codes) {
            if (c.category != category) { continue; }
            Integer s = 0;
            for (String w : (c.name + ' ' + (c.sub == null ? '' : c.sub)).toLowerCase().split('[^a-z]+')) { if (w.length() > 3 && words.contains(w.removeEnd('s'))) { s++; } }
            if (s > bestScore) { bestScore = s; best = c.id; }
        }
        return best;
    }

    // ------------------------------------------------------------------ writes
    @AuraEnabled
    public static View setStatus(Id recordId, Id hypId, String status, String howKnow) {
        if (status != 'Open' && status != 'Confirmed' && status != 'Ruled Out') { throw new AuraHandledException('Unknown status.'); }
        if (status != 'Open' && String.isBlank(howKnow)) { throw new AuraHandledException('Say how you know.'); }
        try {
            update new Investigation_Hypothesis__c(Id = hypId, Status__c = status, How_Do_You_Know__c = howKnow == null ? null : howKnow.trim().left(255));
        } catch (DmlException e) { throw new AuraHandledException('It was not saved: ' + e.getDmlMessage(0)); }
        return build(recordId, false);
    }

    @AuraEnabled
    public static View saveFit(Id recordId, Id hypId, String rowKey, String value) {
        if (!ROWS.contains(rowKey)) { throw new AuraHandledException('Unknown row.'); }
        Investigation_Hypothesis__c h = [SELECT Is_Not_Fit__c FROM Investigation_Hypothesis__c WHERE Id = :hypId];
        Map<String, Object> m = String.isBlank(h.Is_Not_Fit__c) ? new Map<String, Object>() : (Map<String, Object>) JSON.deserializeUntyped(h.Is_Not_Fit__c);
        if (value == 'fits' || value == 'fails') { m.put(rowKey, value); } else { m.remove(rowKey); }
        update new Investigation_Hypothesis__c(Id = hypId, Is_Not_Fit__c = JSON.serialize(m));
        return build(recordId, false);
    }

    @AuraEnabled
    public static View saveIsNot(Id recordId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(payload);
        List<compliancequest__SQX_5W2H__c> fives = [SELECT Id FROM compliancequest__SQX_5W2H__c WHERE compliancequest__SQX_Investigation__c = :invId ORDER BY CreatedDate DESC LIMIT 1];
        compliancequest__SQX_5W2H__c f = fives.isEmpty() ? new compliancequest__SQX_5W2H__c(compliancequest__SQX_Investigation__c = invId) : fives[0];
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            String k = (String) r.get('key');
            if (!ROW_FIELD.containsKey(k)) { continue; }
            f.put(ROW_FIELD.get(k), join((String) r.get('isText'), (String) r.get('isNotText')));
        }
        try { upsert f; } catch (DmlException e) { throw new AuraHandledException('The Is / Is Not was not saved: ' + e.getDmlMessage(0)); }
        return build(recordId, false);
    }

    @AuraEnabled
    public static View saveEvidence(Id recordId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(payload);
        Investigation_Evidence__c e = new Investigation_Evidence__c();
        if (m.get('id') != null) { e.Id = (Id) m.get('id'); } else { e.Investigation__c = invId; }
        if (m.get('hypId') != null) { e.Hypothesis__c = (Id) m.get('hypId'); }
        if (m.get('whyId') != null) { e.Why__c = (Id) m.get('whyId'); }
        String kind = (String) m.get('kind');
        e.Kind__c = kind; e.Test_Type__c = (String) m.get('testType'); e.Supports__c = (String) m.get('supports'); e.Status__c = (String) m.get('status');
        e.Detail__c = (String) m.get('detail'); e.Result__c = m.get('result') == null ? null : ((String) m.get('result')).left(255);
        e.Record_Id__c = (String) m.get('recordId'); e.Record_Name__c = m.get('recordName') == null ? null : ((String) m.get('recordName')).left(80);
        e.Owner__c = m.get('ownerId') == null ? UserInfo.getUserId() : (Id) m.get('ownerId');
        e.Due_Date__c = m.get('due') == null ? null : Date.valueOf((String) m.get('due'));
        e.Done_On__c = m.get('doneOn') == null ? (e.Status__c == 'Done' ? Date.today() : null) : Date.valueOf((String) m.get('doneOn'));
        if (kind == 'Test') {
            if (String.isBlank(e.Test_Type__c)) { throw new AuraHandledException('Choose the kind of test.'); }
            if (String.isBlank(e.Detail__c)) { throw new AuraHandledException('Say what was done.'); }
            if (e.Status__c == 'Done' && (String.isBlank(e.Result__c) || String.isBlank(e.Supports__c))) { throw new AuraHandledException('Give the result and whether it supports it.'); }
        } else if (kind == 'CQ Record') {
            if (String.isBlank(e.Record_Id__c)) { throw new AuraHandledException('Choose the CQ record.'); }
            if (String.isBlank(e.Supports__c)) { e.Supports__c = 'For'; }
        } else if (kind == 'Ask CQ.AI') {
            if (String.isBlank(e.Detail__c)) { throw new AuraHandledException('Nothing to pin.'); }
            if (String.isBlank(e.Supports__c)) { e.Supports__c = 'For'; }
        } else {
            throw new AuraHandledException('Unknown kind of evidence.');
        }
        if (e.Hypothesis__c == null && e.Why__c == null && e.Id == null) { throw new AuraHandledException('Choose the hypothesis or why it is for.'); }
        try { upsert e; } catch (DmlException ex) { throw new AuraHandledException('The evidence was not saved: ' + ex.getDmlMessage(0)); }
        return build(recordId, false);
    }

    @AuraEnabled
    public static View deleteEvidence(Id recordId, Id evidenceId) {
        try { delete [SELECT Id FROM Investigation_Evidence__c WHERE Id = :evidenceId]; } catch (DmlException e) { throw new AuraHandledException('It was not removed: ' + e.getDmlMessage(0)); }
        return build(recordId, false);
    }

    /** The 5 Why for a hypothesis, saved in CQ's own 5 Why tool and Why records, in order. */
    @AuraEnabled
    public static View saveWhys(Id recordId, Id hypId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        Investigation_Hypothesis__c h = [SELECT Id, Number__c, Title__c, Five_Why_Tool__c FROM Investigation_Hypothesis__c WHERE Id = :hypId];
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(payload);
        Savepoint sp = Database.setSavepoint();
        try {
            Id toolId = h.Five_Why_Tool__c;
            if (toolId == null) {
                List<compliancequest__SQX_Investigation_Tool_Name__c> tpl = [SELECT Id FROM compliancequest__SQX_Investigation_Tool_Name__c WHERE Name = '5 Why' LIMIT 1];
                compliancequest__SQX_Investigation_Tool__c t = new compliancequest__SQX_Investigation_Tool__c(compliancequest__SQX_Investigation__c = invId,
                    compliancequest__Investigation_Tool_Method_Used__c = tpl.isEmpty() ? null : tpl[0].Id,
                    compliancequest__Problem_Statement__c = h.Title__c, compliancequest__Description__c = '5 Why for H' + h.Number__c.intValue() + ' (CQ.AI Investigation)');
                insert t;
                toolId = t.Id;
                update new Investigation_Hypothesis__c(Id = h.Id, Five_Why_Tool__c = toolId);
            }
            Map<Id, compliancequest__SQX_Why__c> existing = new Map<Id, compliancequest__SQX_Why__c>([SELECT Id FROM compliancequest__SQX_Why__c WHERE compliancequest__SQX_Investigation_Tool__c = :toolId]);
            List<compliancequest__SQX_Why__c> keep = new List<compliancequest__SQX_Why__c>();
            Integer i = 0;
            for (Object o : rows) {
                Map<String, Object> r = (Map<String, Object>) o;
                String text = (String) r.get('text');
                if (String.isBlank(text)) { continue; }
                i++;
                compliancequest__SQX_Why__c w = new compliancequest__SQX_Why__c(compliancequest__Because__c = text.trim(), compliancequest__Level__c = String.valueOf(i),
                    compliancequest__Is_Root_Cause__c = r.get('isRoot') == true);
                if (r.get('id') != null && existing.containsKey((Id) r.get('id'))) { w.Id = (Id) r.get('id'); existing.remove(w.Id); }
                else { w.compliancequest__SQX_Investigation_Tool__c = toolId; }
                keep.add(w);
            }
            if (!existing.isEmpty()) {
                // a removed why stops being a root cause: its CQ root cause loses the link
                List<compliancequest__SQX_Root_Cause__c> rcs = [SELECT Id FROM compliancequest__SQX_Root_Cause__c WHERE compliancequest__SQX_Why__c IN :existing.keySet()];
                for (compliancequest__SQX_Root_Cause__c rc : rcs) { rc.compliancequest__SQX_Why__c = null; }
                if (!rcs.isEmpty()) { update rcs; }
                delete existing.values();
            }
            upsert keep;
            // chain them: each why answers the one before
            for (Integer k = 1; k < keep.size(); k++) { keep[k].compliancequest__SQX_Why__c = keep[k - 1].Id; }
            if (!keep.isEmpty()) { keep[0].compliancequest__SQX_Why__c = null; update keep; }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The 5 Why was not saved: ' + e.getDmlMessage(0));
        }
        return build(recordId, false);
    }

    /** Saves the root cause rows as CQ root causes with category, code, justification, Verified and Role. */
    @AuraEnabled
    public static View saveRootCauses(Id recordId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        List<Object> rows = (List<Object>) JSON.deserializeUntyped(payload);
        Boolean primary = false;
        Set<Id> codeIds = new Set<Id>();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            if (r.get('role') == 'Primary') { primary = true; }
            if (r.get('codeId') == null) { throw new AuraHandledException('Choose a CQ cause code for: ' + r.get('text')); }
            if (String.isBlank((String) r.get('text'))) { throw new AuraHandledException('Every root cause needs a description.'); }
            codeIds.add((Id) r.get('codeId'));
        }
        if (!primary) { throw new AuraHandledException('Mark at least one root cause Primary.'); }
        Map<Id, compliancequest__SQX_Root_Cause_Code__c> codes = new Map<Id, compliancequest__SQX_Root_Cause_Code__c>([
            SELECT Id, compliancequest__SQX_Root_Cause_Sub_Category__c, compliancequest__SQX_Root_Cause_Sub_Category__r.compliancequest__SQX_Root_Cause_Category__c
            FROM compliancequest__SQX_Root_Cause_Code__c WHERE Id IN :codeIds]);
        List<compliancequest__SQX_Root_Cause__c> ups = new List<compliancequest__SQX_Root_Cause__c>();
        List<Id> hypOf = new List<Id>();
        for (Object o : rows) {
            Map<String, Object> r = (Map<String, Object>) o;
            compliancequest__SQX_Root_Cause__c rc = new compliancequest__SQX_Root_Cause__c();
            if (r.get('id') != null) { rc.Id = (Id) r.get('id'); } else { rc.compliancequest__SQX_Investigation__c = invId; }
            compliancequest__SQX_Root_Cause_Code__c c = codes.get((Id) r.get('codeId'));
            rc.compliancequest__Category__c = (String) r.get('category');
            rc.compliancequest__SQX_Root_Cause_Code__c = c.Id;
            rc.compliancequest__SQX_Root_Cause_Sub_Category__c = c.compliancequest__SQX_Root_Cause_Sub_Category__c;
            rc.compliancequest__SQX_Root_Cause_Category__c = c.compliancequest__SQX_Root_Cause_Sub_Category__r == null ? null : c.compliancequest__SQX_Root_Cause_Sub_Category__r.compliancequest__SQX_Root_Cause_Category__c;
            rc.compliancequest__Description__c = ((String) r.get('text')).trim();
            rc.compliancequest__Justification__c = (String) r.get('evidence');
            rc.compliancequest__Verified__c = r.get('verified') == true;
            rc.Cause_Role__c = (String) r.get('role');
            if (r.get('whyId') != null) { rc.compliancequest__SQX_Why__c = (Id) r.get('whyId'); }
            ups.add(rc);
            String key = (String) r.get('key');
            hypOf.add(key != null && key.startsWith('h:') ? (Id) r.get('hypId') : null);
        }
        Savepoint sp = Database.setSavepoint();
        try {
            upsert ups;
            List<Investigation_Hypothesis__c> hu = new List<Investigation_Hypothesis__c>();
            for (Integer i = 0; i < ups.size(); i++) { if (hypOf[i] != null) { hu.add(new Investigation_Hypothesis__c(Id = hypOf[i], Root_Cause__c = ups[i].Id)); } }
            if (!hu.isEmpty()) { update hu; }
        } catch (DmlException e) {
            Database.rollback(sp);
            throw new AuraHandledException('The root causes were not saved: ' + e.getDmlMessage(0));
        }
        return build(recordId, false);
    }

    public class Found { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String type; }

    /** CQ records to link as evidence, by number or name. */
    @AuraEnabled
    public static List<Found> findRecords(String term) {
        List<Found> out = new List<Found>();
        if (String.isBlank(term) || term.trim().length() < 2) { return out; }
        String pat = term.trim() + '%';
        for (String obj : new List<String>{ 'compliancequest__SQX_Nonconformance__c', 'compliancequest__SQX_CAPA__c', 'compliancequest__SQX_Change_Order__c',
                'compliancequest__SQX_Controlled_Document__c', 'compliancequest__SQX_Equipment__c', 'compliancequest__SQX_Calibration__c',
                'compliancequest__SQX_Inspection__c', 'compliancequest__SQX_Supplier_Deviation__c' }) {
            try {
                for (SObject s : Database.query('SELECT Id, Name FROM ' + obj + ' WHERE Name LIKE :pat ORDER BY Name LIMIT 5')) {
                    Found f = new Found(); f.id = s.Id; f.name = (String) s.get('Name'); f.type = s.getSObjectType().getDescribe().getLabel();
                    out.add(f);
                }
            } catch (Exception e) { System.debug(e.getMessage()); }
        }
        return out;
    }

    // ------------------------------------------------------------------ Is / Is Not in CQ's 5W2H rich text
    @TestVisible
    static List<String> split(String html) {
        if (String.isBlank(html)) { return new List<String>{ null, null }; }
        Matcher a = Pattern.compile('(?is)<b>\\s*Is:\\s*</b>(.*?)</p>').matcher(html);
        Matcher b = Pattern.compile('(?is)<b>\\s*Is Not:\\s*</b>(.*?)</p>').matcher(html);
        String isText = a.find() ? plain(a.group(1)) : null;
        String isNotText = b.find() ? plain(b.group(1)) : null;
        if (isText == null && isNotText == null) { isText = plain(html); }
        return new List<String>{ isText, isNotText };
    }
    @TestVisible
    static String join(String isText, String isNotText) {
        if (String.isBlank(isText) && String.isBlank(isNotText)) { return null; }
        return '<p><b>Is:</b> ' + (isText == null ? '' : isText.trim().escapeHtml4()) + '</p><p><b>Is Not:</b> ' + (isNotText == null ? '' : isNotText.trim().escapeHtml4()) + '</p>';
    }
    static String plain(String s) {
        String t = s == null ? '' : s.replaceAll('(?i)<br\\s*/?>', ' ').replaceAll('<[^>]+>', '').unescapeHtml4().trim();
        return String.isBlank(t) ? null : t;
    }
    static Date toDate(Object o) {
        if (o == null) { return null; }
        if (o instanceof Datetime) { return ((Datetime) o).dateGmt(); }
        return (Date) o;
    }
}

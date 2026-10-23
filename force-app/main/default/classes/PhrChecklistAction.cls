/**
 * PhrChecklistAction
 * -------------------
 * Agent action for the Scout Checklist agent. Finds every checklist question on the Product History
 * Review, suggests an answer for each from data the agent already uses, and, when asked, saves the
 * answers it is sure about in one go.
 *
 * Where suggestions come from (plain rules, no AI):
 *   - "scrap rate" questions: the same calculation as the flow
 *     CalculateScrapRateWithStaticTotalProductsManufactured (nonconformances / total products
 *     manufactured x 100, with the flow's static 2,000 products and its 5% threshold). The flow itself
 *     is not called because it writes to the checklist; this action only writes when the user confirms.
 *   - questions about nonconformances, CAPAs, change orders, inspections or investigations: the records
 *     worth reviewing (Most Relevant and Less Relevant) from the same search as the relevance package.
 *   - anything else, or a question the data cannot answer either way: "not sure", and the question is
 *     named so the user can answer it. Nothing is saved for those.
 *
 * The checklist is treated as blank: existing answers are not read or copied. Saving overwrites the
 * Answer, Answer Value and Notes of the questions the agent is sure about.
 */
global with sharing class PhrChecklistAction {

    // Mirrors the scrap rate flow. Change both together.
    @TestVisible static final Decimal TOTAL_PRODUCTS_MANUFACTURED = 2000;
    @TestVisible static final Decimal SCRAP_RATE_THRESHOLD = 5;
    static final Integer MAX_NAMES = 5;

    @TestVisible static final String SUGGESTED = 'suggested';
    @TestVisible static final String UNSURE = 'unsure';
    @TestVisible static final String SAVED = 'saved';

    global class Request {
        @InvocableVariable(label='Record Id' description='The Product History Review open in the conversation (a Complaint Id also works: its most recent PHR is used).' required=true)
        global Id recordId;

        @InvocableVariable(label='Save Answers' description='False (default): only suggest answers. True: save the answers the agent is sure about to the checklist. Use true only after the user confirms.')
        global Boolean saveAnswers;
    }

    global class ActionResponse {
        @InvocableVariable(label='Checklist' description='Every checklist question with its suggested answer, whether the agent is sure, and what it is based on.')
        global PhrChecklistResult result;
    }

    @InvocableMethod(
        label='Answer PHR Checklist'
        description='Finds every checklist question on the Product History Review and suggests an answer for each from the scrap rate calculation and the records worth reviewing. Questions it cannot answer are marked not sure. With Save Answers true, saves the answers it is sure about.'
    )
    global static List<ActionResponse> run(List<Request> requests) {
        List<ActionResponse> out = new List<ActionResponse>();
        for (Request req : requests) {
            ActionResponse r = new ActionResponse();
            r.result = answer(req == null ? null : req.recordId, req != null && req.saveAnswers == true);
            out.add(r);
        }
        return out;
    }

    // ---------- Main ----------

    @TestVisible
    static PhrChecklistResult answer(Id recordId, Boolean save) {
        PhrChecklistResult res = new PhrChecklistResult();
        res.saved = false;
        res.sureCount = 0;
        res.unsureCount = 0;
        res.savedCount = 0;
        try {
            Id phrId = PhrRecordContext.phrIdFor(recordId);
            if (phrId == null) {
                return fail(res, recordId == null
                    ? 'I could not tell which Product History Review to use.'
                    : 'There is no Product History Review for this record yet, so there is no checklist to answer.');
            }
            List<compliancequest__SQX_Product_History_Review__c> phrs = [
                SELECT Name FROM compliancequest__SQX_Product_History_Review__c WHERE Id = :phrId WITH USER_MODE LIMIT 1
            ];
            res.phrName = phrs.isEmpty() ? null : phrs[0].Name;
            res.checklistName = 'PHR checklist' + (res.phrName == null ? '' : ' · ' + res.phrName);

            List<compliancequest__SQX_Product_History_Answer__c> answers = [
                SELECT Id, compliancequest__Question__c, compliancequest__Question_Number__c, compliancequest__Result_Type_Id__c
                FROM compliancequest__SQX_Product_History_Answer__c
                WHERE compliancequest__SQX_Product_History_Review__c = :phrId
                WITH USER_MODE
                ORDER BY compliancequest__Question_Number__c, Name
            ];
            if (answers.isEmpty()) {
                res.success = true;
                res.intro = 'There are no checklist questions on ' + label(res) + ' yet.';
                return res;
            }

            Evidence ev = new Evidence(phrId);
            Map<String, List<String>> allowed = allowedValues(answers);
            List<compliancequest__SQX_Product_History_Answer__c> toSave = new List<compliancequest__SQX_Product_History_Answer__c>();
            List<PhrChecklistItem> sureItems = new List<PhrChecklistItem>();
            List<String> unsure = new List<String>();

            for (compliancequest__SQX_Product_History_Answer__c a : answers) {
                Suggestion s = suggest(a.compliancequest__Question__c, ev);
                List<String> values = allowed.get(a.compliancequest__Result_Type_Id__c);
                String value = s.answer == null ? null : matchValue(s.answer, values);
                if (s.answer != null && value == null) {
                    s.sure = false;
                    s.basis = 'The answer would be ' + s.answer + ', but that is not one of this question\'s answers ('
                        + String.join(values, ', ') + ').';
                }
                PhrChecklistItem item = new PhrChecklistItem();
                item.answerId = a.Id;
                item.questionNumber = a.compliancequest__Question_Number__c;
                item.question = a.compliancequest__Question__c;
                item.suggestedAnswer = s.sure ? value : null;
                item.basis = s.basis;
                item.sure = s.sure;
                item.status = s.sure ? SUGGESTED : UNSURE;
                res.items.add(item);
                if (s.sure) {
                    res.sureCount++;
                    sureItems.add(item);
                    toSave.add(new compliancequest__SQX_Product_History_Answer__c(
                        Id = a.Id,
                        compliancequest__Answer__c = value,
                        compliancequest__Answer_Value__c = value,
                        compliancequest__Notes__c = s.basis));
                } else {
                    res.unsureCount++;
                    unsure.add(questionLabel(item));
                }
            }
            res.unsureQuestions = String.join(unsure, '\n');

            if (save && !toSave.isEmpty()) {
                List<Database.SaveResult> rs = Database.update(toSave, false, AccessLevel.USER_MODE);
                List<String> problems = new List<String>();
                for (Integer i = 0; i < rs.size(); i++) {
                    if (rs[i].isSuccess()) {
                        sureItems[i].status = SAVED;
                        res.savedCount++;
                    } else {
                        for (Database.Error e : rs[i].getErrors()) { problems.add(questionLabel(sureItems[i]) + ': ' + e.getMessage()); }
                    }
                }
                res.saved = true;
                if (!problems.isEmpty()) { res.errorMessage = 'Some answers could not be saved. ' + String.join(problems, ' '); }
            }
            res.intro = intro(res, save);
            res.success = true;
        } catch (Exception ex) {
            return fail(res, 'I could not work through the checklist: ' + ex.getMessage());
        }
        return res;
    }

    static String intro(PhrChecklistResult res, Boolean save) {
        Integer total = res.items.size();
        String s;
        if (save) {
            s = 'I saved ' + res.savedCount + (res.savedCount == 1 ? ' answer' : ' answers') + ' to the checklist on ' + label(res) + '.';
        } else if (res.sureCount == 0) {
            s = 'I looked at the ' + total + ' checklist ' + (total == 1 ? 'question' : 'questions') + ' on ' + label(res)
                + ' but could not suggest an answer for any of them.';
        } else {
            s = 'I suggested answers for ' + res.sureCount + ' of the ' + total + ' checklist '
                + (total == 1 ? 'question' : 'questions') + ' on ' + label(res) + '. Nothing is saved until you confirm.';
        }
        if (res.unsureCount > 0) {
            s += ' I am not sure about ' + (res.unsureCount == 1 ? 'this question, so please answer it yourself: ' : 'these questions, so please answer them yourself: ')
                + res.unsureQuestions.replace('\n', '; ') + '.';
        }
        return s;
    }

    static String label(PhrChecklistResult res) {
        return res.phrName == null ? 'the Product History Review' : res.phrName;
    }

    static String questionLabel(PhrChecklistItem item) {
        return (String.isBlank(item.questionNumber) ? '' : item.questionNumber + ' ') + '"' + item.question + '"';
    }

    static PhrChecklistResult fail(PhrChecklistResult res, String msg) {
        res.success = false;
        res.errorMessage = msg;
        res.intro = msg;
        return res;
    }

    // ---------- Rules ----------

    @TestVisible
    class Suggestion {
        String answer;
        Boolean sure = false;
        String basis;
        Suggestion(String answer, Boolean sure, String basis) {
            this.answer = answer;
            this.sure = sure;
            this.basis = basis;
        }
    }

    // A question about a quality being acceptable ("passed", "within limits") cannot be answered from a count.
    static final Pattern QUALITY_WORDS = Pattern.compile('(?i)\\b(pass(ed|es)?|acceptable|within|meet(s)?|met|compliant|adequate|effective|verified|approved)\\b');

    @TestVisible
    static Suggestion suggest(String question, Evidence ev) {
        String q = question == null ? '' : question;
        if (Pattern.compile('(?i)scrap').matcher(q).find()) {
            return scrapRate(ev);
        }
        String kind = kindOf(q);
        if (kind == null) {
            return new Suggestion(null, false, 'I have no data that answers this question.');
        }
        if (QUALITY_WORDS.matcher(q).find()) {
            return new Suggestion(null, false, 'This asks whether something was acceptable, which the records found cannot tell me. '
                + ev.describe(kind));
        }
        if (!ev.searched) {
            return new Suggestion(null, false, ev.problem);
        }
        List<String> names = ev.names(kind);
        if (names.isEmpty()) {
            return new Suggestion('No', true, 'No ' + plural(kind) + ' worth reviewing were found for this part'
                + (String.isBlank(ev.lotNumber) ? '' : ' and lot ' + ev.lotNumber) + '.');
        }
        return new Suggestion('Yes', true, names.size() + ' ' + (names.size() == 1 ? singular(kind) : plural(kind))
            + ' worth reviewing: ' + shortList(names) + '.');
    }

    static Suggestion scrapRate(Evidence ev) {
        Integer ncs = ev.allNonconformances();
        Decimal rate = (Decimal.valueOf(ncs) / TOTAL_PRODUCTS_MANUFACTURED * 100).setScale(2);
        Boolean high = rate > SCRAP_RATE_THRESHOLD;
        return new Suggestion(high ? 'Yes' : 'No', true,
            'The scrap rate calculated = ' + rate.toPlainString() + ' (' + ncs + ' nonconformances / '
            + TOTAL_PRODUCTS_MANUFACTURED.format() + ' products manufactured x 100). '
            + (high ? 'That is above' : 'That is within') + ' the ' + SCRAP_RATE_THRESHOLD.format() + '% threshold.');
    }

    @TestVisible
    static String kindOf(String q) {
        if (Pattern.compile('(?i)non-?conform|\\bNCs?\\b').matcher(q).find()) { return 'nc'; }
        if (Pattern.compile('(?i)\\bCAPAs?\\b|corrective|preventive').matcher(q).find()) { return 'capa'; }
        if (Pattern.compile('(?i)change order|design change|engineering change|\\bECOs?\\b|\\bchanges?\\b').matcher(q).find()) { return 'change'; }
        if (Pattern.compile('(?i)inspect').matcher(q).find()) { return 'inspection'; }
        if (Pattern.compile('(?i)investigat').matcher(q).find()) { return 'investigation'; }
        return null;
    }

    static String singular(String kind) {
        return new Map<String, String>{ 'nc' => 'nonconformance', 'capa' => 'CAPA', 'change' => 'change order',
            'inspection' => 'inspection', 'investigation' => 'investigation' }.get(kind);
    }

    static String plural(String kind) {
        return new Map<String, String>{ 'nc' => 'nonconformances', 'capa' => 'CAPAs', 'change' => 'change orders',
            'inspection' => 'inspections', 'investigation' => 'investigations' }.get(kind);
    }

    static String shortList(List<String> names) {
        List<String> shown = new List<String>();
        for (Integer i = 0; i < names.size() && i < MAX_NAMES; i++) { shown.add(names[i]); }
        return String.join(shown, ', ') + (names.size() > MAX_NAMES ? ' and ' + (names.size() - MAX_NAMES) + ' more' : '');
    }

    /** Yes/No style answer matched to the question's own answer values (by name, ignoring case). */
    @TestVisible
    static String matchValue(String answer, List<String> values) {
        if (values == null || values.isEmpty()) { return answer; }
        for (String v : values) { if (v != null && v.trim().equalsIgnoreCase(answer)) { return v.trim(); } }
        return null;
    }

    static Map<String, List<String>> allowedValues(List<compliancequest__SQX_Product_History_Answer__c> answers) {
        Set<Id> typeIds = new Set<Id>();
        for (compliancequest__SQX_Product_History_Answer__c a : answers) {
            try { if (String.isNotBlank(a.compliancequest__Result_Type_Id__c)) { typeIds.add((Id) a.compliancequest__Result_Type_Id__c); } } catch (Exception e) { continue; }
        }
        Map<String, List<String>> out = new Map<String, List<String>>();
        if (typeIds.isEmpty()) { return out; }
        for (compliancequest__SQX_Result_Type_Value__c v : [
            SELECT Name, compliancequest__SQX_Result_Type__c FROM compliancequest__SQX_Result_Type_Value__c
            WHERE compliancequest__SQX_Result_Type__c IN :typeIds WITH USER_MODE ORDER BY Name
        ]) {
            for (String key : new List<String>{ String.valueOf(v.compliancequest__SQX_Result_Type__c),
                    String.valueOf(v.compliancequest__SQX_Result_Type__c).left(15) }) {
                if (!out.containsKey(key)) { out.put(key, new List<String>()); }
                out.get(key).add(v.Name);
            }
        }
        return out;
    }

    // ---------- Evidence ----------

    /** The records worth reviewing for the PHR's complaint, loaded once. */
    @TestVisible
    class Evidence {
        Boolean searched = false;
        String problem;
        String lotNumber;
        Id phrId;
        Map<String, List<String>> byKind = new Map<String, List<String>>();
        Integer ncTotal;

        Evidence(Id phrId) {
            this.phrId = phrId;
            for (String k : new List<String>{ 'nc', 'capa', 'change', 'inspection', 'investigation' }) { byKind.put(k, new List<String>()); }
            try {
                PhrQmsPanelController.PanelData p = PhrQmsPanelController.getPanelData(phrId, null);
                if (!p.success) { problem = 'I could not search for related records: ' + p.errorMessage; return; }
                if (String.isBlank(p.partName)) { problem = 'The complaint has no part, so related records could not be searched.'; return; }
                lotNumber = p.lotNumber;
                add('nc', p.nonconformances);
                add('capa', p.capas);
                add('change', p.changeOrders);
                add('inspection', p.inspections);
                for (PhrQmsPanelController.Row r : p.investigations) { byKind.get('investigation').add(r.name); }
                searched = true;
            } catch (Exception ex) {
                problem = 'I could not search for related records: ' + ex.getMessage();
            }
        }

        void add(String kind, List<PhrQmsPanelController.Row> rows) {
            for (PhrQmsPanelController.Row r : rows) {
                if (r.tier == null || r.tier == 'Top' || r.tier == 'Next') { byKind.get(kind).add(r.name); }
            }
        }

        List<String> names(String kind) {
            return byKind.containsKey(kind) ? byKind.get(kind) : new List<String>();
        }

        String describe(String kind) {
            if (!searched) { return problem; }
            List<String> n = names(kind);
            return n.isEmpty() ? 'No ' + PhrChecklistAction.plural(kind) + ' worth reviewing were found.' : 'Found: ' + PhrChecklistAction.shortList(n) + '.';
        }

        /** Same count as the scrap rate flow: every nonconformance. */
        Integer allNonconformances() {
            if (ncTotal == null) { ncTotal = [SELECT COUNT() FROM compliancequest__SQX_Nonconformance__c WITH USER_MODE]; }
            return ncTotal;
        }
    }
}

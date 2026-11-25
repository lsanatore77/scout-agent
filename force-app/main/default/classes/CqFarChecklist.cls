/**
 * CqFarChecklist: the questions a Field Action Review answers on its Reviewer Assessment step, and the record fields
 * that show where a review stands.
 *
 * Which checklist a review gets: an active assignment for its part, then one for its part family, then the default
 * checklist. With no checklist set up at all, the review uses the six built-in questions, so the workspace works
 * with no configuration. The checklist is chosen the first time the review is saved, and the questions are copied
 * onto the review as Field Action Review Check rows (the Checklist related list), with the answer, who gave it and when.
 * The coordinator can change the checklist before submitting, with a reason.
 *
 * The workspace keeps its work in progress as a draft (Review_Draft__c). Every save also writes what the draft holds
 * to real fields (step, choices, proposed field action), so a standard record page and reports show the review.
 */
public with sharing class CqFarChecklist {
    /** The workspace's steps, in order, as Review Step values. */
    public static final List<String> STEPS = new List<String>{ 'Review at a Glance', 'Reviewer Assessment', 'Recommendation', 'Committee Approval' };
    public static final String COMPLETE = 'Complete';
    public static final Integer ASSESS = 1;
    /** Statuses in which the review is still with the coordinator. */
    public static final Set<String> OPEN = new Set<String>{ 'New', 'In Review' };
    /** Statuses in which the review waits on its approval: the committee, or one emergency approver. */
    public static final Set<String> AWAITING = new Set<String>{ 'With Committee', 'Escalated' };

    /** The questions every review gets when no checklist is set up: key, question. */
    @TestVisible
    private static final List<List<String>> BUILT_IN = new List<List<String>>{
        new List<String>{ 'left', 'Has affected product left our control (shipped or in use)?' },
        new List<String>{ 'injury', 'Has an injury or death been reported?' },
        new List<String>{ 'couldHarm', 'Could the problem cause injury if it happens again?' },
        new List<String>{ 'moreLots', 'Is more than one lot likely to be affected?' },
        new List<String>{ 'detect', 'Would the user detect the problem before use?' },
        new List<String>{ 'cause', 'Is the root cause understood?' }
    };

    public class Question {
        @AuraEnabled public String id;      // the key the workspace stores the answer under
        @AuraEnabled public String text;
        @AuraEnabled public String help;
        Question(String id, String text, String help) { this.id = id; this.text = text; this.help = help; }
    }
    /** The checklist a review answers: its questions, and which checklist they come from. */
    public class Info {
        @AuraEnabled public Id checklistId; @AuraEnabled public String checklistName;
        @AuraEnabled public String changeReason;
        @AuraEnabled public List<Question> questions = new List<Question>();
    }

    /** The workspace says Not known; the record says Not Known. */
    private static String answerValue(Object a) {
        String s = a == null ? null : String.valueOf(a);
        if (String.isBlank(s)) { return null; }
        if (s.equalsIgnoreCase('Not known')) { return 'Not Known'; }
        return s == 'Yes' || s == 'No' ? s : null;
    }

    /** The checklist a part gets: its own active assignment, then its family's, then the default. Null when none is set up. */
    public static Id chooseFor(Id partId) {
        if (partId != null) {
            List<compliancequest__SQX_Part__c> p = [SELECT compliancequest__Part_Family__c FROM compliancequest__SQX_Part__c WHERE Id = :partId];
            Id familyId = p.isEmpty() ? null : p[0].compliancequest__Part_Family__c;
            Id byFamily;
            for (Field_Action_Checklist_Assignment__c a : [
                    SELECT Checklist__c, Part__c, Part_Family__c FROM Field_Action_Checklist_Assignment__c
                    WHERE Active__c = true AND Checklist__r.Active__c = true
                      AND (Part__c = :partId OR (Part_Family__c != null AND Part_Family__c = :familyId))
                    ORDER BY CreatedDate DESC LIMIT 50]) {
                if (a.Part__c == partId) { return a.Checklist__c; }
                if (byFamily == null) { byFamily = a.Checklist__c; }
            }
            if (byFamily != null) { return byFamily; }
        }
        List<Field_Action_Checklist__c> d = [SELECT Id FROM Field_Action_Checklist__c WHERE Active__c = true AND Default__c = true ORDER BY CreatedDate LIMIT 1];
        return d.isEmpty() ? null : d[0].Id;
    }

    /** A checklist's active questions as check rows (not yet saved). The built-in questions when checklistId is null. */
    private static List<Field_Action_Review_Check__c> rowsFor(Id reviewId, Id checklistId) {
        List<Field_Action_Review_Check__c> out = new List<Field_Action_Review_Check__c>();
        if (checklistId != null) {
            for (Field_Action_Checklist_Question__c q : [
                    SELECT Id, Question__c, Key__c, Sort_Order__c FROM Field_Action_Checklist_Question__c
                    WHERE Field_Action_Checklist__c = :checklistId AND Active__c = true ORDER BY Sort_Order__c NULLS LAST, Name]) {
                out.add(new Field_Action_Review_Check__c(Field_Action_Review__c = reviewId, Question__c = q.Id, Question_Text__c = q.Question__c,
                    Key__c = String.isBlank(q.Key__c) ? String.valueOf(q.Id) : q.Key__c, Sort_Order__c = q.Sort_Order__c));
            }
            if (!out.isEmpty()) { return out; }
        }
        Integer n = 0;
        for (List<String> q : BUILT_IN) {
            n += 10;
            out.add(new Field_Action_Review_Check__c(Field_Action_Review__c = reviewId, Question_Text__c = q[1], Key__c = q[0], Sort_Order__c = n));
        }
        return out;
    }

    private static List<Field_Action_Review_Check__c> rows(Id reviewId) {
        return [SELECT Id, Key__c, Question_Text__c, Question__r.Help_Text__c, Answer__c, Sort_Order__c FROM Field_Action_Review_Check__c
                WHERE Field_Action_Review__c = :reviewId ORDER BY Sort_Order__c NULLS LAST, Name];
    }

    /** The questions the workspace shows: the review's own rows once it has them, otherwise the checklist it would get. */
    public static Info info(Id reviewId, Id partId) {
        Info x = new Info();
        Field_Action_Review__c r = [SELECT Checklist__c, Checklist__r.Name, Checklist_Change_Reason__c FROM Field_Action_Review__c WHERE Id = :reviewId];
        List<Field_Action_Review_Check__c> have = rows(reviewId);
        x.checklistId = r.Checklist__c; x.checklistName = r.Checklist__r?.Name; x.changeReason = r.Checklist_Change_Reason__c;
        if (have.isEmpty()) {
            if (x.checklistId == null) { x.checklistId = chooseFor(partId); }
            if (x.checklistId != null && x.checklistName == null) {
                x.checklistName = [SELECT Name FROM Field_Action_Checklist__c WHERE Id = :x.checklistId].Name;
            }
            Map<Id, String> help = new Map<Id, String>();
            if (x.checklistId != null) {
                for (Field_Action_Checklist_Question__c q : [SELECT Id, Help_Text__c FROM Field_Action_Checklist_Question__c WHERE Field_Action_Checklist__c = :x.checklistId]) {
                    help.put(q.Id, q.Help_Text__c);
                }
            }
            for (Field_Action_Review_Check__c c : rowsFor(reviewId, x.checklistId)) { x.questions.add(new Question(c.Key__c, c.Question_Text__c, help.get(c.Question__c))); }
        } else {
            for (Field_Action_Review_Check__c c : have) { x.questions.add(new Question(c.Key__c, c.Question_Text__c, c.Question__r?.Help_Text__c)); }
        }
        return x;
    }

    /**
     * Saves the checklist answers in the draft to the review's check rows, creating the rows the first time.
     * An answer that changes records who changed it and when; a cleared answer clears both.
     */
    public static void saveAnswers(Id reviewId, Id partId, Map<String, Object> answers) {
        List<Field_Action_Review_Check__c> have = rows(reviewId);
        if (have.isEmpty()) {
            Field_Action_Review__c r = [SELECT Checklist__c FROM Field_Action_Review__c WHERE Id = :reviewId];
            Id checklistId = r.Checklist__c != null ? r.Checklist__c : chooseFor(partId);
            if (r.Checklist__c == null && checklistId != null) { update new Field_Action_Review__c(Id = reviewId, Checklist__c = checklistId); }
            have = rowsFor(reviewId, checklistId);
            insert have;
        }
        if (answers == null) { return; }
        List<Field_Action_Review_Check__c> changed = new List<Field_Action_Review_Check__c>();
        for (Field_Action_Review_Check__c c : have) {
            String a = answerValue(answers.get(c.Key__c));
            if (a == c.Answer__c) { continue; }
            changed.add(new Field_Action_Review_Check__c(Id = c.Id, Answer__c = a,
                Answered_By__c = a == null ? null : UserInfo.getUserId(), Answered_On__c = a == null ? null : Datetime.now()));
        }
        if (!changed.isEmpty()) { update changed; }
    }

    /**
     * The coordinator chooses a different checklist before submitting. A reason is needed unless it is the checklist
     * the review would get anyway. The review's questions are replaced, so answers to the old ones are cleared.
     */
    @AuraEnabled
    public static Info changeChecklist(Id recordId, Id checklistId, String reason) {
        Field_Action_Review__c r = [SELECT Status__c, Checklist__c, Part__c, Nonconformance__r.compliancequest__SQX_Part__c, Complaint__r.compliancequest__SQX_Part__c
                                    FROM Field_Action_Review__c WHERE Id = :recordId];
        if (!OPEN.contains(r.Status__c)) { throw new AuraHandledException('The checklist can be changed only before the review is submitted.'); }
        if (checklistId == null || [SELECT COUNT() FROM Field_Action_Checklist__c WHERE Id = :checklistId AND Active__c = true] == 0) {
            throw new AuraHandledException('Choose an active checklist.');
        }
        Id partId = r.Part__c != null ? r.Part__c : r.Nonconformance__r?.compliancequest__SQX_Part__c != null
            ? r.Nonconformance__r.compliancequest__SQX_Part__c : r.Complaint__r?.compliancequest__SQX_Part__c;
        Boolean usual = checklistId == chooseFor(partId);
        if (!usual && String.isBlank(reason)) { throw new AuraHandledException('Give the reason for using a different checklist.'); }
        delete [SELECT Id FROM Field_Action_Review_Check__c WHERE Field_Action_Review__c = :recordId];
        update new Field_Action_Review__c(Id = recordId, Checklist__c = checklistId, Checklist_Change_Reason__c = usual ? null : reason.trim().left(32768));
        insert rowsFor(recordId, checklistId);
        return info(recordId, partId);
    }

    /** The active checklists a coordinator can choose from. */
    @AuraEnabled(cacheable=true)
    public static List<Field_Action_Checklist__c> checklists() {
        return [SELECT Id, Name, Description__c, Default__c FROM Field_Action_Checklist__c WHERE Active__c = true ORDER BY Default__c DESC, Name LIMIT 200];
    }

    private static String str(Object o) { return o == null ? null : String.valueOf(o).trim(); }
    private static String pick(Object o, Set<String> allowed) { String s = str(o); return s != null && allowed.contains(s) ? s : null; }
    private static String text(Object o) { String s = str(o); return String.isBlank(s) ? null : s.left(32768); }

    /**
     * Copies what the workspace's draft holds to the review's fields: the step, when the assessment was completed,
     * and the recommendation (field action choice, proposed field action, action type, recall class, the reasons for
     * choosing differently from CQ.AI, the emergency approver). r must carry Started_On__c and Assessment_Completed_On__c.
     * At submission the reasons are left out: CqFarSuggestions writes them then, only where the choice differs.
     */
    public static void fromDraft(Field_Action_Review__c r, Map<String, Object> d) { fromDraft(r, d, true); }
    public static void fromDraft(Field_Action_Review__c r, Map<String, Object> d, Boolean withReasons) {
        if (d == null) { return; }
        if (r.Started_On__c == null) { r.Started_On__c = Datetime.now(); }
        Integer step = d.get('step') instanceof Integer ? (Integer) d.get('step') : null;
        if (step != null && step >= 0 && step < STEPS.size()) { r.Review_Step__c = STEPS[step]; }
        Integer maxStep = d.get('maxStep') instanceof Integer ? (Integer) d.get('maxStep') : 0;
        Boolean assessed = String.isNotBlank(str(d.get('hazard'))) && String.isNotBlank(str(d.get('level')))
            && d.get('checks') instanceof Map<String, Object> && !((Map<String, Object>) d.get('checks')).isEmpty();
        if (r.Assessment_Completed_On__c == null && assessed && maxStep > ASSESS) { r.Assessment_Completed_On__c = Datetime.now(); }

        Boolean needed = str(d.get('outcome')) == 'Field Action Needed';
        String choice = needed ? str(d.get('faChoice')) : null;
        Id joinId;
        if (String.isNotBlank(choice) && choice != 'new') { try { joinId = Id.valueOf(choice); } catch (Exception e) { joinId = null; } }
        Boolean isNew = choice == 'new';
        r.Field_Action_Choice__c = isNew ? 'New Field Action' : joinId != null ? 'Add to Existing' : null;
        r.Proposed_Field_Action__c = joinId;
        r.Proposed_Title__c = isNew && String.isNotBlank(str(d.get('faTitle'))) ? str(d.get('faTitle')).left(255) : null;
        r.Proposed_Action_Type__c = isNew ? pick(d.get('actionType'), new Set<String>{ 'Correction', 'Removal (Recall)', 'Withdrawal', 'Advisory Notice' }) : null;
        r.Proposed_Recall_Class__c = isNew && r.Proposed_Action_Type__c != 'Withdrawal' ? pick(d.get('recallClass'), new Set<String>{ 'Class I', 'Class II', 'Class III' }) : null;
        if (withReasons) {
            r.Risk_Level_Reason__c = text(d.get('whyLevel'));
            r.Outcome_Reason__c = text(d.get('whyOutcome'));
            r.Scope_Reason__c = isNew ? text(d.get('whyScope')) : null;
            r.Action_Type_Reason__c = isNew ? text(d.get('whyType')) : null;
        }
        String approver = d.get('emergency') == true ? str(d.get('emergencyUser')) : null;
        try { r.Emergency_Approver__c = String.isBlank(approver) ? null : Id.valueOf(approver); } catch (Exception e) { r.Emergency_Approver__c = null; }
    }

    /** The draft as a map, or null when there is none or it cannot be read. */
    public static Map<String, Object> parse(String draft) {
        if (String.isBlank(draft)) { return null; }
        try { return (Map<String, Object>) JSON.deserializeUntyped(draft); } catch (Exception e) { return null; }
    }
}

/** The checklist a Field Action Review answers, its Checklist rows, and the record fields the workspace writes. */
@IsTest
private class CqFarChecklistTest {

    static compliancequest__SQX_Part__c part(String num, Id familyId) {
        compliancequest__SQX_Part__c p = new compliancequest__SQX_Part__c(
            Name = num, cqext__Title__c = num, compliancequest__Part_Number__c = num, compliancequest__Part_Family__c = familyId,
            compliancequest__Part_Type__c = 'Finished Product', compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert p;
        return p;
    }

    static Field_Action_Checklist__c checklist(String name, Boolean isDefault, List<String> keys) {
        Field_Action_Checklist__c c = new Field_Action_Checklist__c(Name = name, Active__c = true, Default__c = isDefault);
        insert c;
        List<Field_Action_Checklist_Question__c> qs = new List<Field_Action_Checklist_Question__c>();
        Integer n = 0;
        for (String k : keys) {
            n += 10;
            qs.add(new Field_Action_Checklist_Question__c(Field_Action_Checklist__c = c.Id, Question__c = name + ' ' + k + '?', Key__c = k, Sort_Order__c = n, Active__c = true));
        }
        insert qs;
        return c;
    }

    static List<Field_Action_Review_Check__c> rows(Id reviewId) {
        return [SELECT Key__c, Question_Text__c, Answer__c, Answered_By__c, Answered_On__c FROM Field_Action_Review_Check__c
                WHERE Field_Action_Review__c = :reviewId ORDER BY Sort_Order__c];
    }

    @IsTest
    static void aPartsOwnChecklistWinsThenItsFamilyThenTheDefault() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Implants');
        compliancequest__SQX_Part_Family__c otherFam = new compliancequest__SQX_Part_Family__c(Name = 'Disposables');
        insert new List<compliancequest__SQX_Part_Family__c>{ fam, otherFam };
        compliancequest__SQX_Part__c mine = part('CL-1', fam.Id);
        compliancequest__SQX_Part__c sibling = part('CL-2', fam.Id);
        compliancequest__SQX_Part__c other = part('CL-3', otherFam.Id);
        System.assertEquals(null, CqFarChecklist.chooseFor(other.Id), 'nothing set up');

        Field_Action_Checklist__c std = checklist('Standard', true, new List<String>{ 'left' });
        Field_Action_Checklist__c byFam = checklist('Implant', false, new List<String>{ 'implanted' });
        Field_Action_Checklist__c byPart = checklist('Sterile', false, new List<String>{ 'sterile' });
        insert new List<Field_Action_Checklist_Assignment__c>{
            new Field_Action_Checklist_Assignment__c(Checklist__c = byFam.Id, Part_Family__c = fam.Id, Active__c = true),
            new Field_Action_Checklist_Assignment__c(Checklist__c = byPart.Id, Part__c = mine.Id, Active__c = true) };

        System.assertEquals(byPart.Id, CqFarChecklist.chooseFor(mine.Id));
        System.assertEquals(byFam.Id, CqFarChecklist.chooseFor(sibling.Id));
        System.assertEquals(std.Id, CqFarChecklist.chooseFor(other.Id));
        System.assertEquals(std.Id, CqFarChecklist.chooseFor(null));
        try {
            insert new Field_Action_Checklist_Assignment__c(Checklist__c = std.Id, Part__c = other.Id, Part_Family__c = fam.Id);
            System.assert(false, 'a part and a family together');
        } catch (DmlException e) { System.assert(true); }
    }

    @IsTest
    static void withNoChecklistTheBuiltInQuestionsAreUsed() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Built in');
        insert review;
        CqFarChecklist.Info x = CqFarChecklist.info(review.Id, null);
        System.assertEquals(6, x.questions.size());
        System.assertEquals('left', x.questions[0].id);
        System.assertEquals(null, x.checklistId);
        System.assertEquals('the built-in questions', x.source);
        System.assert(!x.canChange, 'nothing to change to');

        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":1,"maxStep":1,"checks":{"injury":"Not known"}}');
        List<Field_Action_Review_Check__c> rs = rows(review.Id);
        System.assertEquals(6, rs.size());
        System.assertEquals('Not Known', rs[1].Answer__c);
        System.assertEquals(UserInfo.getUserId(), rs[1].Answered_By__c);
        System.assertEquals(null, rs[0].Answer__c);
    }

    @IsTest
    static void savingTheDraftWritesTheRecordFieldsAndTheChecklist() {
        Field_Action_Checklist__c std = checklist('Standard', true, new List<String>{ 'left', 'injury' });
        Field_Action__c fa = new Field_Action__c(Title__c = 'Open action');
        insert fa;
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Draft review');
        insert review;

        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":0,"maxStep":0}');
        Field_Action_Review__c r = [SELECT Status__c, Review_Step__c, Started_On__c, Checklist__c, Checks_Total__c, Checks_Answered__c
                                    FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals('In Review', r.Status__c);
        System.assertEquals('Review at a Glance', r.Review_Step__c);
        System.assertNotEquals(null, r.Started_On__c);
        System.assertEquals(std.Id, r.Checklist__c);
        System.assertEquals(2, r.Checks_Total__c);
        System.assertEquals(0, r.Checks_Answered__c);

        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":2,"maxStep":2,"hazard":"Burns","level":"High","checks":{"left":"Yes","injury":"No"},'
            + '"outcome":"Field Action Needed","faChoice":"' + fa.Id + '","whyLevel":"Seen in the field","whyFa":"x"}');
        r = [SELECT Review_Step__c, Assessment_Completed_On__c, Checks_Answered__c, Field_Action_Choice__c, Proposed_Field_Action__c,
                    Proposed_Action_Type__c, Risk_Level_Reason__c FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals('Recommendation', r.Review_Step__c);
        System.assertNotEquals(null, r.Assessment_Completed_On__c);
        System.assertEquals(2, r.Checks_Answered__c);
        System.assertEquals('Add to Existing', r.Field_Action_Choice__c);
        System.assertEquals(fa.Id, r.Proposed_Field_Action__c);
        System.assertEquals(null, r.Proposed_Action_Type__c);
        System.assertEquals('Seen in the field', r.Risk_Level_Reason__c);

        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":2,"maxStep":2,"checks":{"left":"Yes"},"outcome":"Field Action Needed",'
            + '"faChoice":"new","faTitle":"Seal recall","actionType":"Removal (Recall)","recallClass":"Class II","emergency":true,"emergencyUser":"' + UserInfo.getUserId() + '"}');
        r = [SELECT Field_Action_Choice__c, Proposed_Field_Action__c, Proposed_Title__c, Proposed_Action_Type__c, Proposed_Recall_Class__c,
                    Emergency_Approver__c, Checks_Answered__c FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals('New Field Action', r.Field_Action_Choice__c);
        System.assertEquals(null, r.Proposed_Field_Action__c);
        System.assertEquals('Seal recall', r.Proposed_Title__c);
        System.assertEquals('Removal (Recall)', r.Proposed_Action_Type__c);
        System.assertEquals('Class II', r.Proposed_Recall_Class__c);
        System.assertEquals(UserInfo.getUserId(), r.Emergency_Approver__c);
        System.assertEquals(1, r.Checks_Answered__c, 'a cleared answer is cleared');

        CqFieldActionReview.View v = CqFieldActionReview.getView(review.Id);
        System.assertEquals('Standard', v.checklist.checklistName);
        System.assertEquals('the default checklist', v.checklist.source);
        System.assertEquals(2, v.checklist.questions.size());
    }

    @IsTest
    static void aDifferentChecklistNeedsAReason() {
        Field_Action_Checklist__c std = checklist('Standard', true, new List<String>{ 'left' });
        Field_Action_Checklist__c other = checklist('Software', false, new List<String>{ 'version', 'patch' });
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Change');
        insert review;
        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":1,"checks":{"left":"Yes"}}');
        try { CqFarChecklist.changeChecklist(review.Id, other.Id, ' '); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }

        CqFarChecklist.Info x = CqFarChecklist.changeChecklist(review.Id, other.Id, 'It is a software fault');
        System.assertEquals(2, x.questions.size());
        System.assertEquals('It is a software fault', x.changeReason);
        System.assertEquals('changed by the coordinator', x.source);
        System.assertEquals(std.Id, x.usualId);
        System.assert(x.canChange);
        System.assertEquals(2, rows(review.Id).size());
        System.assertEquals(null, rows(review.Id)[0].Answer__c);

        x = CqFarChecklist.changeChecklist(review.Id, std.Id, null);
        System.assertEquals(null, x.changeReason, 'back to the usual checklist: no reason needed');
        System.assertEquals(2, CqFarChecklist.checklists().size());

        update new Field_Action_Review__c(Id = review.Id, Status__c = 'Escalated');
        try { CqFarChecklist.changeChecklist(review.Id, other.Id, 'late'); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest
    static void aSendBackIsCountedAndReturnsToTheRecommendation() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Sent back');
        insert review;
        cqext__CQAPR_Approval__c a = new cqext__CQAPR_Approval__c(cqext__Approval_Record__c = 'CQ Record', cqext__Approval_Type__c = 'CQ Approval',
            cqext__Main_Record_Id__c = review.Id, cqext__Child_Record_Id__c = review.Id);
        // CQ's engine by name, as the app reaches it (see CqApprovalGateway)
        ((CqApprovalGateway) Type.forName('CqApprovalBridge').newInstance()).submit(review, a, new List<cqext__CQAPR_Approval_Step__c>{ new cqext__CQAPR_Approval_Step__c(cqext__Step__c = 1,
            cqext__CQAPR_Assignee_User__c = UserInfo.getUserId(), cqext__Assignee_Id__c = UserInfo.getUserId()) });
        Id approvalId = [SELECT Id FROM cqext__CQAPR_Approval__c WHERE cqext__Main_Record_Id__c = :review.Id ORDER BY CreatedDate DESC LIMIT 1].Id;
        update new Field_Action_Review__c(Id = review.Id, Status__c = 'Escalated', Committee_Approval__c = approvalId, Review_Step__c = 'Committee Approval');

        CqFarCommittee.onClosed(new Map<Id, String>{ approvalId => 'Rejected' });
        Field_Action_Review__c r = [SELECT Status__c, Review_Step__c, Times_Sent_Back__c FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals('In Review', r.Status__c);
        System.assertEquals('Recommendation', r.Review_Step__c);
        System.assertEquals(1, r.Times_Sent_Back__c);

        // with the approver, the draft no longer writes to the record
        update new Field_Action_Review__c(Id = review.Id, Status__c = 'With Committee');
        CqFieldActionReview.saveDraft(review.Id, '{"v":3,"step":0}');
        System.assertEquals('Recommendation', [SELECT Review_Step__c FROM Field_Action_Review__c WHERE Id = :review.Id].Review_Step__c);
    }
}

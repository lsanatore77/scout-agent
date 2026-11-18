/** The Field Action Review: the evidence and risk score CQ.AI gathers, the draft, and the decision that starts or joins a field action. */
@IsTest
private class CqFieldActionReviewTest {

    static compliancequest__SQX_Part__c makePart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Review Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Review Part', cqext__Title__c = 'Review Part', compliancequest__Part_Number__c = 'FAR-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        return part;
    }

    static compliancequest__SQX_Nonconformance__c nc(Id partId, String lot, String risk) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Seal open', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Seal open on the pouch', compliancequest__SQX_Part__c = partId, compliancequest__Lot_Number__c = lot,
            compliancequest__Defective_Quantity__c = 2, compliancequest__Occurrence_Date__c = Date.today(), Triage_Risk__c = risk);
    }

    static CqFieldActionReview.Factor factor(CqFieldActionReview.View v, String name) {
        for (CqFieldActionReview.Factor f : v.factors) { if (f.name == name) { return f; } }
        return null;
    }

    static String refused(Id reviewId, String outcome, String rationale, String actionType) {
        try {
            CqFieldActionReview.submit(reviewId, 'Hazard', 'Summary', 50, 'Medium', outcome, rationale, null, null, actionType, null);
        } catch (AuraHandledException e) {
            return 'refused';
        }
        return 'decided';
    }

    @IsTest
    static void theReviewGathersEvidenceAndScoresTheRisk() {
        compliancequest__SQX_Part__c part = makePart();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'FAR-L1', compliancequest__Part_Number__c = 'FAR-PART-1');
        List<compliancequest__SQX_Nonconformance__c> ncs = new List<compliancequest__SQX_Nonconformance__c>{
            nc(part.Id, 'FAR-L1', 'High'), nc(part.Id, 'FAR-L1', null), nc(part.Id, 'FAR-L2', null) };
        insert ncs;
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Seal review', Reason_for_Review__c = 'Open seals', Nonconformance__c = ncs[0].Id,
            Quantity_Shipped__c = 50, Quantity_Affected__c = 120);
        insert review;
        Field_Action__c open = new Field_Action__c(Title__c = 'Open action', Part__c = part.Id, Lot_Numbers__c = 'FAR-L1');
        insert open;
        Signal_Rule__c rule = new Signal_Rule__c(Name = 'Cluster', Code__c = 'CLUSTER', Threshold_Mode__c = 'Fixed', Unit__c = 'complaints', Window_Days__c = 90, Active__c = true);
        insert rule;
        Signal__c byRule = new Signal__c(Part__c = part.Id, Rule__c = rule.Id, Strength__c = 'Escalate', Status__c = 'New', Score__c = 1,
            Value__c = 3, Raise_Threshold__c = 2, Escalate_Threshold__c = 3, Baseline__c = 1, Value_Label__c = '3 complaints in 90 days');
        Signal__c byHand = new Signal__c(Part__c = part.Id, Lot_Number__c = 'FAR-L1', Strength__c = 'Assess', Status__c = 'New', Summary__c = 'Operator saw two open seals');
        Signal__c quiet = new Signal__c(Part__c = part.Id, Strength__c = 'Watch', Status__c = 'Watching', Summary__c = 'One late report');
        insert new List<Signal__c>{ byRule, byHand, quiet };
        insert new Signal_Event__c(Signal__c = byRule.Id, Nonconformance__c = ncs[1].Id, Record_Number__c = 'NC-2');

        Test.startTest();
        CqFieldActionReview.View v = CqFieldActionReview.getView(review.Id);
        System.assertEquals('Nonconformance', v.sourceKind);
        System.assertEquals('FAR-L1', v.lot, 'the lot comes from the nonconformance');
        System.assertEquals('FAR-PART-1', v.partName);
        System.assertEquals('Seal open on the pouch', v.problem);

        System.assertEquals(2, v.records.size(), 'the other records on the part');
        System.assertEquals(true, v.records[0].sameLot, 'same-lot records come first');
        System.assertEquals('Same lot', v.records[0].why);
        System.assertEquals('Same part', v.records[1].why);
        System.assertEquals(1, v.fieldActions.size());
        System.assertEquals(true, v.fieldActions[0].suggested);
        System.assertEquals('Already covers lot FAR-L1', v.fieldActions[0].why);

        System.assertEquals(20, factor(v, 'Reached the field').pts, 'units recorded as shipped');
        System.assertEquals(25, factor(v, 'Severity').pts, 'High at triage');
        System.assertEquals(35, factor(v, 'Signals').pts, 'the strongest signal that counts is at full score');
        System.assertEquals(10, factor(v, 'Quantity affected').pts);
        System.assertEquals(90, v.score);
        System.assertEquals('High', v.band);
        System.assertEquals('Field Action Needed', v.suggestedOutcome);
        System.assertEquals('Score 90 of 100 and the product has reached the field.', v.suggestedWhy);

        System.assertEquals(2, v.signals.size(), 'Assess and Escalate signals');
        System.assertEquals(1, v.moreSignals.size(), 'a Watch signal is kept apart');
        CqFieldActionReview.Sig top = v.signals[0];
        System.assertEquals('Cluster', top.rule);
        System.assertEquals(true, top.thisLot, 'a record behind it is on this lot');
        System.assertEquals(1, top.records.size());
        System.assertEquals(3.0, top.times);
        System.assertEquals('3 complaints. Normal is 1 complaints per 90 days. Escalates at 3.', top.why);
        System.assertEquals('Manual', v.signals[1].rule);
        System.assertEquals('Raised by a person, not by a rule.', v.signals[1].why);
        System.assertNotEquals(null, v.signals[1].raisedBy);

        System.assertEquals(12, v.trendMonths.size());
        System.assertEquals(3, v.trend.size());
        System.assertEquals(2, v.trend[1].counts[11], 'nonconformances this month on lots that have a lot record');
        System.assertEquals(1, v.trend[2].counts[11], 'this review');

        System.assertEquals(8, v.know.size());
        System.assertEquals(true, v.know[0].unknown, 'no intake event: injury is not known');
        System.assertEquals('Yes, 50 units', v.know[2].a);
        System.assertEquals('No, none recorded', v.know[4].a);
        System.assertEquals('High', v.know[6].a);
        System.assertNotEquals(null, v.committee);

        // the scope CQ.AI would start from: Partial, on the lot with the evidence
        CqFieldActionLots.Scope s = CqFieldActionLots.getScope(review.Id);
        System.assertEquals('Partial', s.suggested);
        System.assertEquals('The evidence is on lot FAR-L1. No Spread signal shows the same failure across lots.', s.why);
        System.assertEquals('FAR-L1', s.lots[0].name);
        System.assertEquals(true, s.lots[0].thisLot);
        System.assertEquals(true, s.lots[0].known);
        System.assertEquals(2, s.lots[0].records);
        System.assertEquals(2, s.lots.size(), 'a lot seen only on a record is listed too');
        System.assertEquals(false, s.lots[1].known);
        Test.stopTest();
    }

    @IsTest
    static void aBareReviewScoresLowAndKeepsItsDraft() {
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Bare review');
        insert review;
        CqFieldActionReview.View v = CqFieldActionReview.getView(review.Id);
        System.assertEquals(10, v.score, 'only the middle severity value, as no risk is recorded');
        System.assertEquals('Low', v.band);
        System.assertEquals('No Field Action', v.suggestedOutcome);
        System.assertEquals('Score 10 of 100 and nothing shows the product reached the field.', v.suggestedWhy);
        System.assertEquals(0, v.signals.size());
        System.assertEquals(0, v.trendMonths.size(), 'no part, no trend');

        CqFieldActionReview.saveDraft(review.Id, '{"hazard":"x"}');
        review = [SELECT Status__c, Review_Draft__c FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals('In Review', review.Status__c, 'the first saved draft starts the review');
        System.assertEquals('{"hazard":"x"}', review.Review_Draft__c);
        CqFieldActionReview.saveDraft(review.Id, ' ');
        System.assertEquals(null, [SELECT Review_Draft__c FROM Field_Action_Review__c WHERE Id = :review.Id].Review_Draft__c);

        update new Field_Action_Review__c(Id = review.Id, Status__c = 'Decided');
        System.assertEquals('In Review', CqFieldActionReview.reopen(review.Id).status);

        System.assertEquals('High', CqFieldActionReview.band(70));
        System.assertEquals('Medium', CqFieldActionReview.band(40));
        System.assertEquals('Low', CqFieldActionReview.band(39));
    }

    @IsTest
    static void aDecisionStartsANewFieldAction() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Seal review', Reason_for_Review__c = 'Open seals', Part__c = part.Id,
            Lot_Number__c = 'FAR-L9', Quantity_Affected__c = 40, Quantity_Shipped__c = 12);
        insert review;
        System.assertEquals('refused', refused(review.Id, 'Maybe', 'Because', CqFieldActionStrategy.REMOVAL), 'an outcome must be chosen');
        System.assertEquals('refused', refused(review.Id, 'Field Action Needed', ' ', CqFieldActionStrategy.REMOVAL), 'a rationale is required');

        Test.startTest();
        System.assertEquals('refused', refused(review.Id, 'Field Action Needed', 'Because', null), 'a new field action needs its type');
        CqFieldActionReview.View v = CqFieldActionReview.submit(review.Id, 'The seal can open in use.', 'Two lots affected', 72, 'High',
            'Field Action Needed', 'Shipped product is affected', null, 'Recall the pouches', CqFieldActionStrategy.REMOVAL, 'Class II');
        Test.stopTest();

        System.assertEquals('Decided', v.status);
        System.assertEquals('Field Action Needed', v.outcome);
        System.assertNotEquals(null, v.faId, 'a new field action is started');
        Field_Action__c fa = [SELECT Title__c, Action_Type__c, Recall_Class__c, Part__c, Lot_Numbers__c, Quantity_Shipped__c, Decision_Rationale__c, Description__c
                              FROM Field_Action__c WHERE Id = :v.faId];
        System.assertEquals('Recall the pouches', fa.Title__c);
        System.assertEquals(CqFieldActionStrategy.REMOVAL, fa.Action_Type__c);
        System.assertEquals('Class II', fa.Recall_Class__c);
        System.assertEquals(part.Id, fa.Part__c);
        System.assertEquals('FAR-L9', fa.Lot_Numbers__c);
        System.assertEquals(12, fa.Quantity_Shipped__c);
        System.assertEquals('Shipped product is affected', fa.Decision_Rationale__c);
        System.assertEquals('Open seals', fa.Description__c, 'with no source record, the reason for review describes it');
        review = [SELECT Risk_Score__c, Risk_Level__c, Reviewer__c, Decided_By__c, Review_Draft__c FROM Field_Action_Review__c WHERE Id = :review.Id];
        System.assertEquals(72, review.Risk_Score__c);
        System.assertEquals(UserInfo.getUserId(), review.Reviewer__c, 'the decider is the reviewer when none was set');
    }

    @IsTest
    static void aDecisionJoinsAnOpenFieldActionOrNeedsNone() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c open = new Field_Action__c(Title__c = 'Open action', Part__c = part.Id, Lot_Numbers__c = 'FAR-L1');
        insert open;
        Field_Action_Review__c joins = new Field_Action_Review__c(Title__c = 'Second lot', Part__c = part.Id, Lot_Number__c = 'FAR-L9');
        Field_Action_Review__c none = new Field_Action_Review__c(Title__c = 'Nothing to do', Part__c = part.Id, Lot_Number__c = 'FAR-L3', Field_Action__c = open.Id);
        insert new List<Field_Action_Review__c>{ joins, none };

        Test.startTest();
        CqFieldActionReview.View v = CqFieldActionReview.submit(joins.Id, 'Hazard', 'Summary', 60, 'Medium', 'Field Action Needed', 'Same failure', open.Id, null, null, null);
        System.assertEquals(open.Id, v.faId);
        System.assertEquals('FAR-L1, FAR-L9', [SELECT Lot_Numbers__c FROM Field_Action__c WHERE Id = :open.Id].Lot_Numbers__c, 'the review brings its lot');

        v = CqFieldActionReview.submit(none.Id, 'Hazard', 'Summary', 20, 'Low', 'No Field Action', 'Contained in the plant', null, null, null, null);
        System.assertEquals('No Field Action', v.outcome);
        System.assertEquals(null, v.faId, 'no field action is linked');
        Test.stopTest();
    }
}

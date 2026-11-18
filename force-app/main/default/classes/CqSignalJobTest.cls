/** The signal job: it finds patterns across complaints, nonconformances and reviews, grades them, and lets old signals fade. */
@IsTest
private class CqSignalJobTest {

    static compliancequest__SQX_Part__c makePart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Signal Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Signal Part', cqext__Title__c = 'Signal Part', compliancequest__Part_Number__c = 'SJ-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        return part;
    }

    static Signal_Rule__c rule(String code, String mode, Decimal raise, Decimal escalate) {
        return new Signal_Rule__c(Name = code, Code__c = code, Threshold_Mode__c = mode, Raise_Threshold__c = raise, Escalate_Threshold__c = escalate,
            Window_Days__c = 90, Lookback_Months__c = 3, Active__c = true);
    }

    static compliancequest__SQX_Complaint__c complaint(Id partId, String lot) {
        return new compliancequest__SQX_Complaint__c(
            compliancequest__Complaint_Title__c = 'Seal open on arrival', compliancequest__Description__c = 'The pouch seal was open',
            compliancequest__SQX_Part__c = partId, compliancequest__Country_of_Origin__c = 'US', compliancequest__Aware_Date__c = Date.today(),
            compliancequest__Occurrence_Date__c = Date.today(), compliancequest__Reported_Date__c = Date.today(), compliancequest__Lot_Number__c = lot);
    }

    static compliancequest__SQX_Nonconformance__c nc(Id partId, String lot) {
        return new compliancequest__SQX_Nonconformance__c(
            compliancequest__NC_Title__c = 'Seal open', compliancequest__Type__c = 'Internal', compliancequest__Type_Of_Issue__c = 'Product',
            compliancequest__Description__c = 'Seal open', compliancequest__SQX_Part__c = partId, compliancequest__Lot_Number__c = lot,
            compliancequest__Defective_Quantity__c = 2, compliancequest__Occurrence_Date__c = Date.today());
    }

    static Signal__c signal(String key) {
        return [SELECT Strength__c, Score__c, Value__c, Value_Label__c, Status__c, Trend__c, Raise_Threshold__c, Escalate_Threshold__c, Next_Threshold__c,
                       Baseline__c, Lot_Number__c, Part__c, Rule__c, First_Seen__c
                FROM Signal__c WHERE Group_Key__c = :key];
    }

    @IsTest
    static void complaintsAndANonconformanceOnOneLotRaiseSignals() {
        compliancequest__SQX_Part__c part = makePart();
        insert new List<Signal_Rule__c>{ rule('CROSS_SOURCE', 'Fixed', 1, 2), rule('CLUSTER', 'Fixed', 2, 4), rule('SPREAD', 'Fixed', 2, 3),
            rule('SHARED_COMPONENT_LOT', 'Fixed', 2, 3), rule('RATE_PER_UNITS_BUILT', 'Fixed', 1, 2) };
        insert new List<compliancequest__SQX_Complaint__c>{ complaint(part.Id, 'SJ-L1'), complaint(part.Id, 'SJ-L1') };
        insert nc(part.Id, 'SJ-L1');

        Test.startTest();
        String first = CqSignalJob.run();
        String second = CqSignalJob.run();
        Test.stopTest();

        System.assertEquals('2 signals (2 new), 0 fading or closed, 5 records linked', first);
        Signal__c cross = signal('CROSS_SOURCE|SJ-L1');
        System.assertEquals('Escalate', cross.Strength__c, 'two complaints meet the escalate threshold');
        System.assertEquals(1, cross.Score__c);
        System.assertEquals('2 complaints and 1 nonconformance on lot SJ-L1', cross.Value_Label__c);
        System.assertEquals('SJ-L1', cross.Lot_Number__c);
        System.assertEquals(part.Id, cross.Part__c);
        System.assertEquals('New', cross.Status__c);
        System.assertNotEquals(null, cross.First_Seen__c);

        Signal__c cluster = signal('CLUSTER|' + part.Id);
        System.assertEquals('Assess', cluster.Strength__c, 'two complaints meet the raise threshold, not the escalate one');
        System.assertEquals(0.6, cluster.Score__c);
        System.assertEquals(4, cluster.Next_Threshold__c, 'the next threshold is the escalate level');
        System.assertEquals('2 complaints on this part in 90 days', cluster.Value_Label__c);
        System.assertEquals(0, cluster.Baseline__c, 'no complaints in the lookback: normal is none');

        System.assertEquals('2 signals (0 new), 0 fading or closed, 0 records linked', second, 'a second run updates the same signals and links nothing twice');
        System.assertEquals('Steady', cluster.Trend__c);
        System.assertEquals(5, [SELECT COUNT() FROM Signal_Event__c]);
    }

    @IsTest
    static void reviewsThatRepeatOrRecurRaiseSignals() {
        compliancequest__SQX_Part__c part = makePart();
        insert new List<Signal_Rule__c>{ rule('REPEAT_REVIEWS', 'Fixed', 2, 3), rule('RECURRENCE', 'Fixed', 1, 3) };
        Field_Action_Review__c closedOut = new Field_Action_Review__c(Title__c = 'Earlier review', Part__c = part.Id, Lot_Number__c = 'SJ-L2',
            Outcome__c = 'No Field Action', Status__c = 'Decided', Decided_On__c = Datetime.now().addDays(-1));
        insert new List<Field_Action_Review__c>{ closedOut,
            new Field_Action_Review__c(Title__c = 'Second review', Part__c = part.Id),
            new Field_Action_Review__c(Title__c = 'Third review', Part__c = part.Id),
            new Field_Action_Review__c(Title__c = 'No part: ignored') };
        insert nc(part.Id, 'SJ-L2');

        Test.startTest();
        new CqSignalJob().execute(null);           // the scheduled run finds them
        String result = CqSignalJob.runRest();      // the on-demand run finds nothing new
        Test.stopTest();

        System.assertEquals('2 signals (0 new), 0 fading or closed, 0 records linked', result);
        System.assertEquals(5, [SELECT COUNT() FROM Signal_Event__c], 'three reviews behind one signal, a nonconformance and a review behind the other');
        Signal__c repeat = signal('REPEAT_REVIEWS|' + part.Id);
        System.assertEquals('Escalate', repeat.Strength__c, 'three reviews on one part');
        System.assertEquals('3 reviews on this part in 90 days', repeat.Value_Label__c);
        Signal__c again = signal('RECURRENCE|SJ-L2');
        System.assertEquals('Assess', again.Strength__c);
        System.assertEquals(1, again.Value__c);
        System.assert(again.Value_Label__c.startsWith('1 new record on lot SJ-L2 since '), again.Value_Label__c);
        System.assert(again.Value_Label__c.endsWith(' ended in No Field Action'), again.Value_Label__c);
        System.assertEquals(part.Id, again.Part__c);
    }

    @IsTest
    static void signalsThatStopShowingFadeThenClose() {
        Signal_Rule__c cluster = rule('CLUSTER', 'Fixed', 2, 4);
        insert cluster;
        Signal__c strong = new Signal__c(Group_Key__c = 'CLUSTER|gone-1', Rule__c = cluster.Id, Strength__c = 'Assess', Status__c = 'New', Trend__c = 'Steady', Value__c = 3);
        Signal__c fadingOne = new Signal__c(Group_Key__c = 'CLUSTER|gone-2', Rule__c = cluster.Id, Strength__c = 'Watch', Status__c = 'Watching', Trend__c = 'Fading', Value__c = 1);
        Signal__c dismissed = new Signal__c(Group_Key__c = 'CLUSTER|gone-3', Rule__c = cluster.Id, Strength__c = 'Assess', Status__c = 'Dismissed', Trend__c = 'Steady', Value__c = 2);
        Signal__c byHand = new Signal__c(Strength__c = 'Assess', Status__c = 'New', Summary__c = 'Raised by a person');
        insert new List<Signal__c>{ strong, fadingOne, dismissed, byHand };

        Test.startTest();
        String result = CqSignalJob.run();
        Test.stopTest();

        System.assertEquals('0 signals (0 new), 2 fading or closed, 0 records linked', result);
        strong = [SELECT Strength__c, Trend__c, Status__c FROM Signal__c WHERE Id = :strong.Id];
        System.assertEquals('Watch', strong.Strength__c, 'a signal that no longer shows drops to Watch');
        System.assertEquals('Fading', strong.Trend__c);
        System.assertEquals('New', strong.Status__c);
        System.assertEquals('Closed', [SELECT Status__c FROM Signal__c WHERE Id = :fadingOne.Id].Status__c, 'a fading Watch signal closes on the next run');
        System.assertEquals('Dismissed', [SELECT Status__c FROM Signal__c WHERE Id = :dismissed.Id].Status__c, 'a dismissed signal is left alone');
        System.assertEquals('Assess', [SELECT Strength__c FROM Signal__c WHERE Id = :byHand.Id].Strength__c, 'a signal raised by hand is never changed');
    }

    @IsTest
    static void aDismissedSignalReopensWhenTheDataGetsWorse() {
        compliancequest__SQX_Part__c part = makePart();
        Signal_Rule__c cluster = rule('CLUSTER', 'Baseline', 1, 2);
        insert cluster;
        insert new Signal__c(Group_Key__c = 'CLUSTER|' + part.Id, Rule__c = cluster.Id, Part__c = part.Id, Strength__c = 'Assess', Status__c = 'Dismissed',
            Trend__c = 'Steady', Value__c = 1);
        insert new List<compliancequest__SQX_Complaint__c>{ complaint(part.Id, null), complaint(part.Id, null) };

        Test.startTest();
        String result = CqSignalJob.run();
        Test.stopTest();

        System.assertEquals('1 signals (0 new), 0 fading or closed, 2 records linked', result);
        Signal__c s = signal('CLUSTER|' + part.Id);
        System.assertEquals('New', s.Status__c, 'more complaints than when it was dismissed: it comes back');
        System.assertEquals('Rising', s.Trend__c);
        System.assertEquals(2, s.Value__c);
        System.assertEquals('Escalate', s.Strength__c, 'with no history to compare against, the fixed thresholds apply');
    }
}

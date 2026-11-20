@IsTest
private class CqEventIntakeTest {

    @TestSetup
    static void setup() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Intake Family');
        insert fam;
        insert new compliancequest__SQX_Part__c(Name = 'Intake Part', cqext__Title__c = 'Intake Part', compliancequest__Part_Number__c = 'INT-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert new List<Event_Question__c>{
            new Event_Question__c(Order__c = 1, Question__c = 'Where did this happen?', Answer_Type__c = 'Choice', Choices__c = 'In Our Plant;At a Supplier;At a Customer', Role__c = 'Where Found', Required__c = true, Active__c = true),
            new Event_Question__c(Order__c = 2, Question__c = 'Did this affect a product?', Answer_Type__c = 'Yes or No', Role__c = 'Product Affected', Required__c = true, Active__c = true),
            new Event_Question__c(Order__c = 3, Question__c = 'Was anyone injured?', Answer_Type__c = 'Yes or No', Role__c = 'Injury', Urgent_When__c = 'Yes', Required__c = true, Active__c = true),
            new Event_Question__c(Order__c = 4, Question__c = 'Is safety at risk?', Answer_Type__c = 'Choice', Choices__c = 'No;Yes;Not Sure', Role__c = 'Safety Risk', Urgent_When__c = 'Yes;Not Sure', Required__c = true, Active__c = true),
            new Event_Question__c(Order__c = 5, Question__c = 'Which test found it?', Answer_Type__c = 'Text', Role__c = 'None', Active__c = true),
            new Event_Question__c(Order__c = 6, Question__c = 'Old question', Answer_Type__c = 'Text', Active__c = false)
        };
        insert new Quick_Log_Category__c(Name = 'Broken Screw', Description__c = 'Fastener snapped', Disposition__c = 'Scrap the screw, replace',
            Limit__c = 3, Days__c = 30, Scope__c = 'Same Part', Active__c = true);
    }

    static Id partId() { return [SELECT Id FROM compliancequest__SQX_Part__c WHERE compliancequest__Part_Number__c = 'INT-PART-1'].Id; }

    @IsTest
    static void setupListsActiveQuestionsInOrder() {
        CqEventIntake.Setup s = CqEventIntake.getSetup();
        System.assertEquals(5, s.questions.size(), 'inactive question left out');
        System.assertEquals('Where did this happen?', s.questions[0].question);
        System.assertEquals(new List<String>{ 'Yes', 'No' }, s.questions[1].choices, 'Yes or No gets its two choices');
        System.assertEquals(null, s.questions[4].role, 'None is no role');
        System.assertEquals(1, s.categories.size());
    }

    @IsTest
    static void reportMakesEventAndAnswers() {
        Map<Id, String> ans = new Map<Id, String>();
        for (Event_Question__c q : [SELECT Id, Order__c FROM Event_Question__c WHERE Active__c = true]) {
            Integer o = q.Order__c.intValue();
            ans.put(q.Id, o == 1 ? 'In Our Plant' : o == 2 ? 'Yes' : o == 3 ? 'No' : o == 4 ? 'Not Sure' : 'Final functional test');
        }
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Id k : ans.keySet()) { rows.add(new Map<String, Object>{ 'questionId' => k, 'answer' => ans.get(k) }); }
        String payload = JSON.serialize(new Map<String, Object>{ 'title' => 'Slow deflate', 'problem' => '8 of 50 slow to deflate',
            'partId' => partId(), 'lot' => 'L1', 'units' => '8', 'answers' => rows });
        CqEventIntake.Sent s = CqEventIntake.submitReport(payload);
        System.assert(s.urgent, 'Not Sure on safety is urgent');
        Quality_Event__c ev = [SELECT Status__c, Event_Type__c, Where_Found__c, Product_Affected__c, Injury__c, Safety_Risk__c, Urgent__c, Units_Affected__c,
            (SELECT Question_Text__c, Answer__c, Role__c FROM Answers__r) FROM Quality_Event__c WHERE Id = :s.id];
        System.assertEquals('Waiting for Review', ev.Status__c);
        System.assertEquals('Report', ev.Event_Type__c);
        System.assertEquals('In Our Plant', ev.Where_Found__c);
        System.assertEquals('Yes', ev.Product_Affected__c);
        System.assertEquals('No', ev.Injury__c);
        System.assertEquals('Not Known', ev.Safety_Risk__c, 'Not Sure maps to Not Known');
        System.assertEquals(8, ev.Units_Affected__c);
        System.assertEquals(5, ev.Answers__r.size());
    }

    @IsTest
    static void reportNeedsRequiredAnswers() {
        try {
            CqEventIntake.submitReport(JSON.serialize(new Map<String, Object>{ 'title' => 'T', 'problem' => 'P', 'answers' => new List<Object>() }));
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            CqEventIntake.submitReport(JSON.serialize(new Map<String, Object>{ 'title' => 'T', 'problem' => '' }));
            System.assert(false, 'should refuse');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void quickLogClosesAndOpensTrendAtLimit() {
        Id cat = [SELECT Id FROM Quick_Log_Category__c LIMIT 1].Id;
        Test.startTest();
        CqEventIntake.Logged a = CqEventIntake.quickLog(cat, partId(), 'L1', 2, 'At station 4');
        System.assert(!a.triggered, '2 of 3 does not open an event');
        System.assertEquals(2, a.trend.total);
        compliancequest__SQX_Nonconformance__c nc = [SELECT compliancequest__Status__c, compliancequest__Record_Stage__c, Quick_Log__c, compliancequest__Closure_Comment__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :a.ncId];
        System.assertEquals('Closed', nc.compliancequest__Status__c);
        System.assert(nc.Quick_Log__c);
        System.assert(nc.compliancequest__Closure_Comment__c.contains('Scrap the screw'));
        CqEventIntake.Logged b = CqEventIntake.quickLog(cat, partId(), null, 1, null);
        Test.stopTest();
        System.assert(b.triggered, '3 of 3 opens the Trend event');
        System.assertEquals(2, b.linked);
        Quality_Event__c ev = [SELECT Event_Type__c, Status__c, Units_Affected__c FROM Quality_Event__c WHERE Id = :b.eventId];
        System.assertEquals('Trend', ev.Event_Type__c);
        System.assertEquals('Waiting for Review', ev.Status__c);
        System.assertEquals(0, CqEventIntake.getTrend(cat, partId()).total, 'linked quick logs start a new count');
    }

    @IsTest
    static void quickLogNeedsCategoryAndPart() {
        try { CqEventIntake.quickLog(null, partId(), null, 1, null); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
        try { CqEventIntake.quickLog([SELECT Id FROM Quick_Log_Category__c LIMIT 1].Id, null, null, 1, null); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest
    static void helpers() {
        System.assertEquals('At a Customer', CqEventIntake.pickWhere('in the field'));
        System.assertEquals('Not Known', CqEventIntake.pickWhere('somewhere'));
        System.assertEquals(null, CqEventIntake.yesNo('Maybe', false));
        System.assertEquals(0, CqEventIntake.split(null).size());
    }

    @IsTest
    static void customerReportBecomesACase() {
        insert new Event_Question__c(Order__c = 7, Question__c = 'Which customer?', Answer_Type__c = 'Text', Role__c = 'Customer', Active__c = true);
        insert new Account(Name = 'Intake Test Customer');
        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Event_Question__c q : [SELECT Id, Order__c FROM Event_Question__c WHERE Active__c = true]) {
            Integer o = q.Order__c.intValue();
            String a = o == 1 ? 'At a Customer' : o == 2 ? 'Yes' : o == 3 ? 'Yes' : o == 4 ? 'Not Sure' : o == 7 ? 'Intake Test Customer' : 'Customer returned it';
            rows.add(new Map<String, Object>{ 'questionId' => q.Id, 'answer' => a });
        }
        String payload = JSON.serialize(new Map<String, Object>{ 'title' => 'Cuff leaks at the customer', 'problem' => 'Cuff loses pressure after 2 minutes',
            'partId' => partId(), 'lot' => 'L7', 'units' => '3', 'answers' => rows });
        Test.startTest();
        CqEventIntake.Sent s = CqEventIntake.submitReport(payload);
        Test.stopTest();

        System.assertEquals('Case', s.kind);
        System.assert(s.urgent, 'an injury is urgent');
        System.assertEquals(0, [SELECT COUNT() FROM Quality_Event__c WHERE Title__c = 'Cuff leaks at the customer'], 'a Case, not a Quality Event');
        Case c = [SELECT CaseNumber, Subject, Description, Origin, Type, Priority, Product__c, Lot_Number__c, Aware_Date__c, Reported_By__c, AccountId,
                         Product_Caused_Harm__c, Impact_on_Safety_or_Environment__c FROM Case WHERE Id = :s.id];
        System.assertEquals(c.CaseNumber, s.name);
        System.assertEquals('Cuff leaks at the customer', c.Subject);
        System.assertEquals('Mobile Intake', c.Origin);
        System.assertEquals('Problem', c.Type);
        System.assertEquals('High', c.Priority);
        System.assertEquals(partId(), c.Product__c);
        System.assertEquals('L7', c.Lot_Number__c);
        System.assertNotEquals(null, c.Aware_Date__c);
        System.assertEquals(UserInfo.getUserId(), c.Reported_By__c);
        System.assertEquals([SELECT Id FROM Account WHERE Name = 'Intake Test Customer'].Id, c.AccountId);
        System.assertEquals('Yes', c.Product_Caused_Harm__c);
        System.assertEquals(null, c.Impact_on_Safety_or_Environment__c, 'Not Sure is left for triage');
        System.assert(c.Description.contains('Cuff loses pressure after 2 minutes'));
        System.assert(c.Description.contains('Which customer? Intake Test Customer'));
        System.assert(c.Description.contains('Units affected: 3'));
    }

    @IsTest
    static void unknownCustomerStaysInTheDescription() {
        System.assertEquals(null, CqEventIntake.account('No Such Customer Anywhere'));
        System.assertEquals(null, CqEventIntake.account(null));
    }
}

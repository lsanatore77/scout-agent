/** The Notifications step of the Field Action workspace: the notice sent, each customer's response by lot, and the counts. */
@IsTest
private class CqFieldActionNotifyTest {

    /** A field action with a confirmed strategy and one lot (22 units) shipped to two customers. */
    static Field_Action__c makeFa() {
        List<Account> accs = new List<Account>{ new Account(Name = 'FNT Hospital A'), new Account(Name = 'FNT Hospital B') };
        insert accs;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Notify test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.WITHDRAWAL, Key_Message__c = 'Stop using lot FNT-L1.',
            Check_Level__c = 'Level C', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNT-L1', In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic');
        insert new List<Lot_Shipment__c>{
            new Lot_Shipment__c(Lot_Number__c = 'FNT-L1', Units__c = 22, Customer__c = accs[0].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FNT-L1', Units__c = 8, Customer__c = accs[1].Id) };
        insert new List<Field_Action_Customer__c>{
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer__c = accs[0].Id, Customer_Name__c = 'FNT Hospital A', Units__c = 22, Lots__c = 'FNT-L1', Status__c = 'Sent', Source__c = 'Shipment'),
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer__c = accs[1].Id, Customer_Name__c = 'FNT Hospital B', Units__c = 8, Lots__c = 'FNT-L1', Status__c = 'Sent', Source__c = 'Shipment') };
        return fa;
    }
    static CqFieldActionNotify.Cust cust(CqFieldActionNotify.View v, String name) {
        for (CqFieldActionNotify.Cust c : v.customers) { if (c.name == name) { return c; } }
        return null;
    }

    @IsTest
    static void theNoticeIsMarkedSentAndTheResponseRecordedByLot() {
        Field_Action__c fa = makeFa();
        Test.startTest();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        System.assertEquals('Stop using lot FNT-L1.', v.message, 'the notice is the key message from Strategy');
        System.assertEquals(2, v.total);
        System.assertEquals(0, v.notified);
        System.assert(v.aiLine.contains('not been sent'), v.aiLine);
        System.assertEquals(22, cust(v, 'FNT Hospital A').lines[0].shipped, 'what was shipped to the customer, from the lot shipments');

        v = CqFieldActionNotify.markSent(fa.Id, null);
        System.assertEquals(2, v.notified, 'Mark Sent with no customers given marks everyone not yet notified');
        System.assertEquals(Date.today(), cust(v, 'FNT Hospital A').sentOn);
        System.assert(v.aiLine.contains('replied'), 'CQ.AI now says who has not replied: ' + v.aiLine);

        Id a = cust(v, 'FNT Hospital A').id;
        CqFieldActionNotify.saveLine(fa.Id, a, 'FNT-L1', 'used', 12);
        CqFieldActionNotify.saveLine(fa.Id, a, 'FNT-L1', 'returning', 9);
        v = CqFieldActionNotify.setResponded(fa.Id, a, true);
        Test.stopTest();
        CqFieldActionNotify.Line l = cust(v, 'FNT Hospital A').lines[0];
        System.assertEquals(12, l.used);
        System.assertEquals(9, l.returning);
        System.assertEquals(1, l.unknown, '22 shipped, 12 used, 9 returning: one unit nobody can account for');
        System.assertEquals('Acknowledged', cust(v, 'FNT Hospital A').status);
        System.assertEquals(1, v.responded);
        System.assertEquals(1, v.waiting);
        System.assertEquals(1, [SELECT COUNT() FROM Customer_Response_Line__c WHERE Field_Action_Customer__c = :a], 'one line per customer and lot');
        Map<String, Integer> c = CqFieldActionNotify.counts(fa.Id);
        System.assertEquals(1, c.get('responded'));
        System.assertEquals(2, c.get('notified'));
    }

    @IsTest
    static void tickingTheTasksRecordsTheNoticeAndTheResponse() {
        Field_Action__c fa = makeFa();
        Id a = [SELECT Id FROM Field_Action_Customer__c WHERE Customer_Name__c = 'FNT Hospital A'].Id;
        Task notice = new Task(WhatId = fa.Id, Subject = 'Send withdrawal notice', Status = CqFieldActionTasks.OPEN, Priority = 'Normal',
            Recall_Task_Type__c = CqFieldActionTasks.NOTICE, Field_Action_Customer__c = a);
        Task resp = new Task(WhatId = fa.Id, Subject = 'Collect response form', Status = CqFieldActionTasks.OPEN, Priority = 'Normal',
            Recall_Task_Type__c = CqFieldActionTasks.RESPONSE, Field_Action_Customer__c = a, ActivityDate = Date.today().addDays(14));
        insert new List<Task>{ notice, resp };
        Test.startTest();
        CqFieldActionNotify.View v = CqFieldActionNotify.setTask(fa.Id, notice.Id, true);
        System.assertEquals(Date.today(), cust(v, 'FNT Hospital A').sentOn, 'the notice task done records the date sent');
        System.assertEquals(2, cust(v, 'FNT Hospital A').tasks.size());
        v = CqFieldActionNotify.setTask(fa.Id, resp.Id, true);
        System.assertEquals('Acknowledged', cust(v, 'FNT Hospital A').status, 'the response task done records the response');
        v = CqFieldActionNotify.setResponded(fa.Id, a, false);
        Test.stopTest();
        System.assertEquals('Sent', cust(v, 'FNT Hospital A').status, 'the response can be taken back');
        System.assertEquals(false, [SELECT IsClosed FROM Task WHERE Id = :resp.Id].IsClosed, 'and its task opens again');
    }

    @IsTest
    static void cqAiSuggestsTheNoticeAndResponseTasksStillMissing() {
        Field_Action__c fa = makeFa();
        Test.startTest();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        System.assertEquals(4, v.suggestions.size(), 'a notice and a response for each of the two customers');
        System.assert(v.suggestLine.contains('2 withdrawal notices'), v.suggestLine);
        for (CqFieldActionTasks.Suggestion s : v.suggestions) {
            System.assert(s.type == CqFieldActionTasks.NOTICE || s.type == CqFieldActionTasks.RESPONSE, 'returns are suggested on Recovery, not here');
        }
        v = CqFieldActionNotify.markSent(fa.Id, null);
        System.assertEquals(2, v.suggestions.size(), 'once the notice is sent only the responses are left');
        List<String> keys = new List<String>();
        for (CqFieldActionTasks.Suggestion s : v.suggestions) { keys.add(s.key); }
        v = CqFieldActionNotify.createTasks(fa.Id, keys);
        Test.stopTest();
        System.assertEquals(0, v.suggestions.size());
        System.assertEquals(2, [SELECT COUNT() FROM Task WHERE WhatId = :fa.Id AND Recall_Task_Type__c = :CqFieldActionTasks.RESPONSE]);
        System.assertEquals(1, cust(v, 'FNT Hospital A').tasks.size(), 'the new response task shows under its customer');
    }

    @IsTest
    static void aClosedFieldActionTakesNoChanges() {
        Field_Action__c fa = makeFa();
        update new Field_Action__c(Id = fa.Id, Status__c = 'Closed');
        Boolean refused = false;
        try { CqFieldActionNotify.markSent(fa.Id, null); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a closed field action is not changed');
        try { CqFieldActionNotify.saveLine(fa.Id, [SELECT Id FROM Field_Action_Customer__c LIMIT 1].Id, 'FNT-L1', 'colour', 1); } catch (AuraHandledException e) { refused = true; }
        System.assertEquals(true, CqFieldActionNotify.getView(fa.Id).closed);
    }
}

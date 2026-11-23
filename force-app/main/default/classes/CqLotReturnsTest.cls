/** Lot Returns (RMA receipts): matched to the field action, summed onto the return tasks, and read by Recovery with the units used. */
@IsTest
private class CqLotReturnsTest {

    /** A withdrawal with one lot (22 units to A, 8 to B), the notice sent, and a return task for each customer. */
    static Field_Action__c makeFa() {
        List<Account> accs = new List<Account>{ new Account(Name = 'LRT Hospital A'), new Account(Name = 'LRT Hospital B') };
        insert accs;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Returns test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.WITHDRAWAL, Check_Level__c = 'Level C',
            Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'LRT-L1', In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic');
        insert new List<Lot_Shipment__c>{
            new Lot_Shipment__c(Lot_Number__c = 'LRT-L1', Units__c = 22, Customer__c = accs[0].Id),
            new Lot_Shipment__c(Lot_Number__c = 'LRT-L1', Units__c = 8, Customer__c = accs[1].Id) };
        List<Field_Action_Customer__c> cs = new List<Field_Action_Customer__c>{
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer__c = accs[0].Id, Customer_Name__c = 'LRT Hospital A', Units__c = 22, Lots__c = 'LRT-L1', Status__c = 'Sent', Source__c = 'Shipment', Notice_Sent_On__c = Date.today()),
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer__c = accs[1].Id, Customer_Name__c = 'LRT Hospital B', Units__c = 8, Lots__c = 'LRT-L1', Status__c = 'Sent', Source__c = 'Shipment', Notice_Sent_On__c = Date.today()) };
        insert cs;
        insert new List<Task>{
            new Task(WhatId = fa.Id, Subject = 'Track return of lot LRT-L1', Status = CqFieldActionTasks.OPEN, Priority = 'Normal',
                Recall_Task_Type__c = CqFieldActionTasks.RETURN_IT, Field_Action_Customer__c = cs[0].Id, Lot_Number__c = 'LRT-L1'),
            new Task(WhatId = fa.Id, Subject = 'Track return of lot LRT-L1', Status = CqFieldActionTasks.OPEN, Priority = 'Normal',
                Recall_Task_Type__c = CqFieldActionTasks.RETURN_IT, Field_Action_Customer__c = cs[1].Id, Lot_Number__c = 'LRT-L1') };
        return fa;
    }
    static Id acc(String name) { return [SELECT Id FROM Account WHERE Name = :name].Id; }
    static Field_Action_Customer__c cust(String name) { return [SELECT Id FROM Field_Action_Customer__c WHERE Customer_Name__c = :name]; }
    static Task taskOf(String name) { return [SELECT Id, Units__c FROM Task WHERE Field_Action_Customer__r.Customer_Name__c = :name AND Recall_Task_Type__c = :CqFieldActionTasks.RETURN_IT]; }

    @IsTest
    static void returnsAreMatchedAndAddUpOnTheReturnTask() {
        Field_Action__c fa = makeFa();
        Test.startTest();
        insert new List<Lot_Return__c>{
            new Lot_Return__c(RMA_Number__c = 'RMA-1', Customer__c = acc('LRT Hospital A'), Lot_Number__c = 'LRT-L1', Units_Received__c = 6, Date_Received__c = Date.today().addDays(-3), Source__c = 'ERP'),
            new Lot_Return__c(RMA_Number__c = 'RMA-2', Customer__c = acc('LRT Hospital A'), Lot_Number__c = 'LRT-L1', Units_Received__c = 4, Date_Received__c = Date.today().addDays(-1), Source__c = 'ERP') };
        Test.stopTest();
        System.assertEquals(2, [SELECT COUNT() FROM Lot_Return__c WHERE Field_Action__c = :fa.Id], 'a return with no field action is matched by its customer and lot');
        System.assertEquals(10, taskOf('LRT Hospital A').Units__c, 'the two receipts add up on the customer\'s return task');
        System.assertEquals(null, taskOf('LRT Hospital B').Units__c, 'another customer\'s task is not touched');
        System.assertEquals(new List<String>{ 'RMA-1', 'RMA-2' }, CqLotReturns.rmas(fa.Id).get(cust('LRT Hospital A').Id + '|LRT-L1'));

        delete [SELECT Id FROM Lot_Return__c WHERE RMA_Number__c = 'RMA-2'];
        System.assertEquals(6, taskOf('LRT Hospital A').Units__c, 'a receipt taken away comes off the task');
    }

    @IsTest
    static void unitsFromReturnsAreNotTypedOver() {
        Field_Action__c fa = makeFa();
        insert new Lot_Return__c(RMA_Number__c = 'RMA-1', Customer__c = acc('LRT Hospital A'), Lot_Number__c = 'LRT-L1', Units_Received__c = 6);
        Boolean refused = false;
        try { CqFieldActionTasks.setTask(fa.Id, taskOf('LRT Hospital A').Id, 'units', 20); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'units that come from the RMAs cannot be typed over');
        CqFieldActionTasks.setTask(fa.Id, taskOf('LRT Hospital B').Id, 'units', 3);
        System.assertEquals(3, taskOf('LRT Hospital B').Units__c, 'a task with no returns behind it still takes typed units');
    }

    @IsTest
    static void recoveryCountsUnitsUsedAsAccountedFor() {
        Field_Action__c fa = makeFa();
        Id a = cust('LRT Hospital A').Id;
        insert new Customer_Response_Line__c(Field_Action_Customer__c = a, Lot_Number__c = 'LRT-L1', Units_Used__c = 12, Units_Returning__c = 10);
        insert new Lot_Return__c(RMA_Number__c = 'RMA-1', Customer__c = acc('LRT Hospital A'), Lot_Number__c = 'LRT-L1', Units_Received__c = 10);
        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        Test.stopTest();
        CqFieldActionRecovery.LotRec l = v.lots[0];
        System.assertEquals(30, l.shipped);
        System.assertEquals(10, l.returned, 'returned comes from the RMAs, through the return task');
        System.assertEquals(12, l.used, 'used comes from the customer\'s response');
        System.assertEquals(8, l.field, '30 shipped, 10 back and 12 used: 8 still in the field (all with B)');
        System.assertEquals(22, v.recovered, 'units used count as accounted for');
        System.assertEquals(10, v.tasks.expectedByLine.get(a + '|LRT-L1'), 'Recovery expects back what the customer said is returning');
        System.assertEquals(12, v.tasks.usedByLine.get(a + '|LRT-L1'));
        Boolean seen = false;
        for (CqFieldActionTasks.TaskRow t : v.tasks.tasks) {
            if (t.customerId == a) { seen = true; System.assert(t.fromReturns); System.assertEquals('RMA-1', t.rmas); }
        }
        System.assert(seen);
        System.assert(v.sSummary.contains('12 used'), v.sSummary);
    }

    @IsTest
    static void noReturnIsSuggestedWhenNothingIsComingBack() {
        Field_Action__c fa = makeFa();
        delete [SELECT Id FROM Task WHERE WhatId = :fa.Id];
        insert new Customer_Response_Line__c(Field_Action_Customer__c = cust('LRT Hospital A').Id, Lot_Number__c = 'LRT-L1', Units_Used__c = 22, Units_Returning__c = 0);
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        Integer returns = 0;
        for (CqFieldActionTasks.Suggestion s : v.tasks.suggestions) { if (s.type == CqFieldActionTasks.RETURN_IT) { returns++; } }
        System.assertEquals(1, returns, 'only B gets a return task: A used all 22 and is sending none back');
    }
}

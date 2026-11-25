/** The Field Action's numbers on the record (CqFieldActionNumbers), the nightly job, and the workspace step it is on (CqFieldActionProgress). */
@IsTest
private class CqFieldActionNumbersTest {

    /**
     * Two lots in scope (FNB-L1: 10 shipped, 4 returned, 2 destroyed; FNB-L2: 5 shipped, used 7 as reported, so capped at 5),
     * one lot out of scope, a hold on FNB-L1, and four customers at Distributor depth: one distributor's customer is not listed.
     */
    static Field_Action__c makeFa(String level) {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Numbers test', Scope__c = 'Partial', Scope_Status__c = 'Confirmed',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.REMOVAL, Depth__c = CqFieldActionDepth.DISTRIBUTOR,
            Check_Level__c = level, Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new List<Field_Action_Lot__c>{
            new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNB-L1', In_Scope__c = true, Approved_In_Scope__c = true,
                Units_Shipped__c = 10, Units_On_Hand__c = 6, Units_Returned__c = 4, Units_Destroyed__c = 2),
            new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNB-L2', In_Scope__c = true, Approved_In_Scope__c = true,
                Units_Shipped__c = 5, Units_On_Hand__c = 1),
            new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNB-L3', In_Scope__c = false, Approved_In_Scope__c = false,
                Units_Shipped__c = 99, Units_On_Hand__c = 99) };
        insert new List<Field_Action_Hold__c>{
            new Field_Action_Hold__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNB-L1', Kind__c = CqFieldActionStrategy.FINISHED, Hold__c = true, Held__c = true),
            new Field_Action_Hold__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNB-L2', Kind__c = CqFieldActionStrategy.FINISHED, Hold__c = false, Held__c = false) };
        List<Field_Action_Customer__c> cs = new List<Field_Action_Customer__c>{
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer_Name__c = 'Acked', Kind__c = CqFieldActionDepth.DIRECT,
                Status__c = CqFieldActionNotify.ACK, Notice_Sent_On__c = Date.today().addDays(-5)),
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer_Name__c = 'Late', Kind__c = CqFieldActionDepth.DISTRIBUTOR,
                Notice_Sent_On__c = Date.today().addDays(-3), Response_Due__c = Date.today().addDays(-1)),
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer_Name__c = 'Silent', Kind__c = CqFieldActionDepth.DIRECT,
                Notice_Sent_On__c = Date.today().addDays(-4), Response_Due__c = Date.today().addDays(-2), Closed_Without_Response_On__c = Date.today()),
            new Field_Action_Customer__c(Field_Action__c = fa.Id, Customer_Name__c = 'Not listed', Kind__c = CqFieldActionDepth.CUSTOMER,
                Notice_Sent_On__c = Date.today().addDays(-9)) };
        insert cs;
        insert new Customer_Response_Line__c(Field_Action_Customer__c = cs[0].Id, Lot_Number__c = 'FNB-L2', Units_Used__c = 7);
        return fa;
    }

    static Field_Action__c read(Id faId) {
        return [SELECT Lots_in_Scope__c, Units_on_Hand__c, Lots_on_Hold__c, Quantity_Shipped__c, Customers__c, Customers_Notified__c,
                       Customers_Responded__c, Closed_Without_Response__c, Responses_Overdue__c, Notices_Sent_On__c, Units_Returned__c,
                       Units_Destroyed__c, Units_Corrected__c, Units_Used__c, Units_Unaccounted__c, Recovery_Percent__c, Check_Target_Met__c,
                       Numbers_Updated_On__c, Days_to_Notify__c
                FROM Field_Action__c WHERE Id = :faId];
    }

    @IsTest
    static void theRefreshButtonWritesEveryNumber() {
        Field_Action__c fa = makeFa('Level A');
        Test.startTest();
        Datetime at = CqFieldActionNumbers.refreshNumbers(fa.Id);
        Test.stopTest();
        Field_Action__c r = read(fa.Id);
        System.assertNotEquals(null, at);
        System.assertEquals(at, CqFieldActionNumbers.updatedOn(fa.Id));
        System.assertEquals(2, r.Lots_in_Scope__c, 'the lot out of scope is not counted');
        System.assertEquals(7, r.Units_on_Hand__c);
        System.assertEquals(1, r.Lots_on_Hold__c, 'only a placed hold counts');
        System.assertEquals(15, r.Quantity_Shipped__c, 'units shipped follow the lots in scope');
        System.assertEquals(3, r.Customers__c, 'a distributor\'s own customer is not listed at Distributor depth');
        System.assertEquals(3, r.Customers_Notified__c);
        System.assertEquals(1, r.Customers_Responded__c);
        System.assertEquals(1, r.Closed_Without_Response__c);
        System.assertEquals(1, r.Responses_Overdue__c, 'a customer closed without a response is not overdue');
        System.assertEquals(Date.today().addDays(-5), r.Notices_Sent_On__c, 'the first notice among the listed customers');
        System.assertEquals(4, r.Units_Returned__c);
        System.assertEquals(2, r.Units_Destroyed__c);
        System.assertEquals(0, r.Units_Corrected__c);
        System.assertEquals(7, r.Units_Used__c);
        // recovered: FNB-L1 6 of 10, FNB-L2 5 of 5 (7 used, capped) = 11 of 15
        System.assertEquals(4, r.Units_Unaccounted__c);
        System.assertEquals(73, r.Recovery_Percent__c);
        System.assertEquals(false, r.Check_Target_Met__c, 'Level A needs every customer');
        System.assertNotEquals(null, r.Days_to_Notify__c);
    }

    @IsTest
    static void theCheckTargetFollowsTheLevel() {
        System.assertEquals(100, CqFieldActionNumbers.targetOf('Level A', null));
        System.assertEquals(40, CqFieldActionNumbers.targetOf('Level B', 40));
        System.assertEquals(100, CqFieldActionNumbers.targetOf('Level B', null));
        System.assertEquals(10, CqFieldActionNumbers.targetOf('Level C', null));
        System.assertEquals(2, CqFieldActionNumbers.targetOf('Level D', null));
        System.assertEquals(0, CqFieldActionNumbers.targetOf('Level E', null));
        System.assertEquals(100, CqFieldActionNumbers.targetOf(null, null));
        Field_Action__c fa = makeFa('Level C');   // 1 of 3 responded: past 10%
        CqFieldActionNumbers.refresh(new Set<Id>{ fa.Id });
        System.assertEquals(true, read(fa.Id).Check_Target_Met__c);
        CqFieldActionNumbers.refresh(null);   // nothing to do
    }

    @IsTest
    static void nothingKnownLeavesTheUnitsBlank() {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Empty', Check_Level__c = 'Level E');
        insert fa;
        CqFieldActionNumbers.refresh(new Set<Id>{ fa.Id });
        Field_Action__c r = read(fa.Id);
        System.assertEquals(0, r.Lots_in_Scope__c);
        System.assertEquals(null, r.Units_Unaccounted__c, 'no shipments known');
        System.assertEquals(null, r.Recovery_Percent__c);
        System.assertEquals(true, r.Check_Target_Met__c, 'Level E has no check');
        System.assertEquals(null, r.Days_to_Notify__c, 'no notice yet');
    }

    @IsTest
    static void theNightlyJobRefreshesOpenFieldActions() {
        Field_Action__c open = makeFa('Level A');
        Field_Action__c closedLongAgo = new Field_Action__c(Title__c = 'Closed', Status__c = 'Closed', Closed_On__c = Datetime.now().addDays(-30),
            Numbers_Updated_On__c = Datetime.now().addDays(-30));
        insert closedLongAgo;
        Test.startTest();
        Database.executeBatch(new CqFieldActionNumbersJob(), 50);
        Test.stopTest();
        System.assertEquals(2, read(open.Id).Lots_in_Scope__c);
        System.assertEquals(null, read(closedLongAgo.Id).Lots_in_Scope__c, 'a field action closed long ago keeps its numbers');
    }

    @IsTest
    static void theJobIsScheduledNightly() {
        Id jobId = CqFieldActionNumbersJob.schedule();
        CronTrigger ct = [SELECT CronExpression, CronJobDetail.Name FROM CronTrigger WHERE Id = :jobId];
        System.assertEquals('0 17 2 * * ?', ct.CronExpression);
        System.assertEquals(CqFieldActionNumbersJob.NAME, ct.CronJobDetail.Name);
        new CqFieldActionNumbersJob().execute((SchedulableContext) null);   // the nightly run hands the work to the batch
    }

    @IsTest
    static void theWorkspaceStepAndStartAreKept() {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Progress');
        insert fa;
        CqFieldActionProgress.saveStep(fa.Id, 0);
        Field_Action__c r = [SELECT Workspace_Step__c, Started_On__c FROM Field_Action__c WHERE Id = :fa.Id];
        System.assertEquals('Glance', r.Workspace_Step__c);
        System.assertNotEquals(null, r.Started_On__c);
        Datetime started = r.Started_On__c;
        CqFieldActionProgress.saveStep(fa.Id, 5);
        r = [SELECT Workspace_Step__c, Started_On__c FROM Field_Action__c WHERE Id = :fa.Id];
        System.assertEquals('Recovery', r.Workspace_Step__c);
        System.assertEquals(started, r.Started_On__c, 'Started On is the first opening');
        CqFieldActionProgress.saveStep(fa.Id, 99);
        System.assertEquals('Recovery', [SELECT Workspace_Step__c FROM Field_Action__c WHERE Id = :fa.Id].Workspace_Step__c, 'an unknown step changes nothing');
        update new Field_Action__c(Id = fa.Id, Status__c = 'Closed');
        CqFieldActionProgress.saveStep(fa.Id, 1);
        System.assertEquals('Complete', [SELECT Workspace_Step__c FROM Field_Action__c WHERE Id = :fa.Id].Workspace_Step__c, 'a closed field action is Complete');
    }
}

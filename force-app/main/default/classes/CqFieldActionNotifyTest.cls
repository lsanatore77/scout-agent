/** The Notifications step of the Field Action workspace: it follows the customers' Cases, and submits them to Recovery in batches. */
@IsTest
private class CqFieldActionNotifyTest {

    /** A field action with a confirmed strategy and one lot shipped to two customers (22 and 8 units). */
    static Field_Action__c makeFa() {
        List<Account> accs = new List<Account>{ new Account(Name = 'FNT Hospital A', Customer_Type__c = 'Hospital'), new Account(Name = 'FNT Supply B', Customer_Type__c = 'Distributor') };
        insert accs;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Notify test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Strategy_Confirmed_On__c = Datetime.now(), Action_Type__c = CqFieldActionStrategy.WITHDRAWAL, Depth__c = 'Distributor',
            Key_Message__c = 'Stop using lot FNT-L1.', Check_Level__c = 'Level C', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FNT-L1', In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic');
        insert new List<Lot_Shipment__c>{
            new Lot_Shipment__c(Lot_Number__c = 'FNT-L1', Units__c = 22, Customer__c = accs[0].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FNT-L1', Units__c = 8, Customer__c = accs[1].Id) };
        return fa;
    }
    static CqFieldActionNotify.Cust cust(CqFieldActionNotify.View v, String name) {
        for (CqFieldActionNotify.Cust c : v.customers) { if (c.name == name) { return c; } }
        return null;
    }

    @IsTest
    static void openingTheStepListsTheCustomersWithACaseEach() {
        Field_Action__c fa = makeFa();
        Test.startTest();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        Test.stopTest();
        System.assertEquals(true, v.strategyConfirmed);
        System.assertEquals('Stop using lot FNT-L1.', v.message);
        System.assertEquals(2, v.total);
        System.assertEquals(2, v.pending);
        System.assertEquals(2, v.unsent);
        System.assertEquals(0, v.acked);
        CqFieldActionNotify.Cust a = cust(v, 'FNT Hospital A'), b = cust(v, 'FNT Supply B');
        System.assertEquals('Direct Customer', a.kind);
        System.assertEquals('Distributor', b.kind);
        System.assertNotEquals(null, a.caseId);
        System.assertNotEquals(null, a.caseNumber);
        System.assertEquals(22, a.shipped);
        System.assertEquals(null, a.returning, 'nothing reported yet');
        System.assertEquals('Pending Acknowledgment', a.status);
        System.assertEquals(Date.today().addDays(14), a.due);
        System.assertEquals(1, a.lines.size());
        System.assertEquals(22, a.lines[0].shipped);
    }

    @IsTest
    static void theNoticeIsMarkedSentAnAcknowledgedCustomerIsSubmittedAndTheRailCounts() {
        Field_Action__c fa = makeFa();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        Id a = cust(v, 'FNT Hospital A').id, aCase = cust(v, 'FNT Hospital A').caseId;
        Test.startTest();
        v = CqFieldActionNotify.markSent(fa.Id);
        System.assertEquals(2, v.notified);
        System.assertEquals(0, v.unsent);
        System.assertEquals(Date.today(), v.sentOn);

        insert new Customer_Response_Line__c(Field_Action_Customer__c = a, Lot_Number__c = 'FNT-L1', Units_Used__c = 12, Units_Returning__c = 9);
        update new Case(Id = aCase, Status = 'Closed');
        v = CqFieldActionNotify.getView(fa.Id);
        CqFieldActionNotify.Cust x = cust(v, 'FNT Hospital A');
        System.assertEquals('Acknowledged', x.status);
        System.assertEquals(9, x.returning);
        System.assertEquals(1, x.unknown, '22 shipped less 12 used and 9 returning');
        System.assertEquals(1, x.lines[0].unknown);
        System.assertEquals(1, v.acked);
        System.assertEquals(1, v.toSubmit);
        System.assertEquals(1, v.pending);

        v = CqFieldActionNotify.submit(fa.Id);
        Test.stopTest();
        System.assertEquals(true, cust(v, 'FNT Hospital A').submitted);
        System.assertEquals(1, v.submitted);
        System.assertEquals(0, v.toSubmit);
        Map<String, Integer> c = CqFieldActionNotify.counts(fa.Id);
        System.assertEquals(2, c.get('total'));
        System.assertEquals(2, c.get('notified'));
        System.assertEquals(1, c.get('responded'));
        System.assertEquals(1, c.get('settled'));
    }

    @IsTest
    static void aCustomerIsFollowedUpClosedWithoutAResponseAndReopened() {
        Field_Action__c fa = makeFa();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        Id b = cust(v, 'FNT Supply B').id;
        update new Field_Action_Customer__c(Id = b, Response_Due__c = Date.today().addDays(-1));
        Test.startTest();
        v = CqFieldActionNotify.followUp(fa.Id);
        System.assertEquals(1, v.overdue, 'pending past its due date');
        System.assertEquals(true, cust(v, 'FNT Supply B').overdue);
        v = CqFieldActionNotify.closeWithoutResponse(fa.Id, b, 'No answer after 3 follow-ups');
        CqFieldActionNotify.Cust x = cust(v, 'FNT Supply B');
        System.assertEquals('Closed Without Response', x.status);
        System.assertEquals('No answer after 3 follow-ups', x.reason);
        System.assertEquals(1, v.noResponse);
        System.assertEquals(1, v.pending);
        System.assertEquals(0, v.overdue);
        System.assertEquals(1, CqFieldActionNotify.counts(fa.Id).get('settled'));
        v = CqFieldActionNotify.reopen(fa.Id, b);
        Test.stopTest();
        System.assertEquals('Pending Acknowledgment', cust(v, 'FNT Supply B').status);
        System.assertEquals(0, v.noResponse);
    }

    @IsTest
    static void aClosedFieldActionIsReadOnly() {
        Field_Action__c fa = makeFa();
        CqFieldActionNotify.getView(fa.Id);
        update new Field_Action__c(Id = fa.Id, Status__c = 'Closed');
        Boolean refused = false;
        try { CqFieldActionNotify.markSent(fa.Id); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused);
        refused = false;
        try { CqFieldActionNotify.submit(fa.Id); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused);
        System.assertEquals(true, CqFieldActionNotify.getView(fa.Id).closed);
    }
}

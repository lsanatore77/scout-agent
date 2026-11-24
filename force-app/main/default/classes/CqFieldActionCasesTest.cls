/** Customer notification on Cases: one per listed customer, the Case writes to the customer's row, and the coordinator's actions. */
@IsTest
private class CqFieldActionCasesTest {

    /** One lot: 40 units to a distributor (15 passed on to its customer) and 10 direct to a hospital. Confirming the strategy opens the Cases. */
    static Field_Action__c makeFa(String depth) {
        List<Account> accs = new List<Account>{
            new Account(Name = 'FCT Distributor', Customer_Type__c = 'Distributor'),
            new Account(Name = 'FCT Hospital', Customer_Type__c = 'Hospital'),
            new Account(Name = 'FCT Clinic') };
        insert accs;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Cases test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Being Defined', Action_Type__c = CqFieldActionStrategy.WITHDRAWAL, Depth__c = depth,
            Key_Message__c = 'Stop using lot FCT-L1.', Check_Level__c = 'Level C', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FCT-L1', In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic');
        insert new List<Lot_Shipment__c>{
            new Lot_Shipment__c(Lot_Number__c = 'FCT-L1', Units__c = 40, Customer__c = accs[0].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FCT-L1', Units__c = 10, Customer__c = accs[1].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FCT-L1', Units__c = 15, Customer__c = accs[2].Id, Shipped_By__c = accs[0].Id) };
        update new Field_Action__c(Id = fa.Id, Strategy_Status__c = 'Confirmed', Strategy_Confirmed_On__c = Datetime.now());
        return fa;
    }
    static Field_Action_Customer__c row(String name) {
        return [SELECT Id, Kind__c, Distributor__c, Case__c, Case__r.IsClosed, Case__r.Response_Outcome__c, Case__r.Subject, Status__c, Response_Due__c,
                       Notice_Sent_On__c, Responded_On__c, Acknowledged_By__c, Submitted_On__c, Closed_Without_Response_On__c, No_Response_Reason__c,
                       Follow_Ups__c, Units__c
                FROM Field_Action_Customer__c WHERE Customer_Name__c = :name];
    }

    @IsTest
    static void confirmingTheStrategyOpensACaseForEveryoneWeShippedTo() {
        Field_Action__c fa = makeFa('Distributor');
        System.assertEquals(50, [SELECT Units_Shipped__c FROM Field_Action_Lot__c WHERE Field_Action__c = :fa.Id].Units_Shipped__c,
            '40 + 10 from us: a distributor\'s onward 15 is not added to what we shipped');
        Field_Action_Customer__c d = row('FCT Distributor'), h = row('FCT Hospital'), c = row('FCT Clinic');
        System.assertEquals('Distributor', d.Kind__c);
        System.assertEquals('Direct Customer', h.Kind__c);
        System.assertEquals('Customer', c.Kind__c);
        System.assertEquals(d.Id, c.Distributor__c, 'the clinic is supplied by the distributor');
        System.assertEquals(15, c.Units__c);
        System.assertNotEquals(null, d.Case__c);
        System.assertNotEquals(null, h.Case__c);
        System.assertEquals(null, c.Case__c, 'at distributor depth the distributor\'s customer gets no Case');
        System.assertEquals(2, [SELECT COUNT() FROM Case WHERE Field_Action__c = :fa.Id]);
        System.assert(h.Case__r.Subject.startsWith('Withdrawal notice'), h.Case__r.Subject);
        System.assertEquals(Date.today().addDays(14), h.Response_Due__c, '14 days after the strategy was confirmed');
        Map<String, Decimal> shipped = CqFieldActionCases.shippedByLine(fa.Id);
        System.assertEquals(40, shipped.get(d.Id + '|FCT-L1'));
        System.assertEquals(10, shipped.get(h.Id + '|FCT-L1'));
        CqFieldActionCases.sync(fa.Id);
        System.assertEquals(2, [SELECT COUNT() FROM Case WHERE Field_Action__c = :fa.Id], 'a second pass opens nothing new');
    }

    @IsTest
    static void hospitalDepthAlsoListsTheDistributorsCustomers() {
        Field_Action__c fa = makeFa('Hospital');
        Field_Action_Customer__c d = row('FCT Distributor'), c = row('FCT Clinic');
        System.assertNotEquals(null, c.Case__c);
        System.assertEquals(3, [SELECT COUNT() FROM Case WHERE Field_Action__c = :fa.Id]);
        Map<String, Decimal> shipped = CqFieldActionCases.shippedByLine(fa.Id);
        System.assertEquals(25, shipped.get(d.Id + '|FCT-L1'), 'the distributor answers for what it still holds: 40 less the 15 it passed on');
        System.assertEquals(15, shipped.get(c.Id + '|FCT-L1'));
    }

    @IsTest
    static void closingTheCaseAcknowledgesTheCustomerAndItCanBeSubmitted() {
        Field_Action__c fa = makeFa('Distributor');
        Field_Action_Customer__c h = row('FCT Hospital');
        Boolean refused = false;
        try { update new Case(Id = h.Case__c, Status = 'Closed'); } catch (DmlException e) { refused = e.getMessage().contains('FCT-L1'); }
        System.assert(refused, 'a Case does not close as Response Received until the lot has what the customer reported');
        try { CqFieldActionCases.submit(fa.Id); System.assert(false); } catch (AuraHandledException e) { refused = true; }

        insert new Customer_Response_Line__c(Field_Action_Customer__c = h.Id, Lot_Number__c = 'FCT-L1', Units_Used__c = 4, Units_Returning__c = 6);
        Test.startTest();
        update new Case(Id = h.Case__c, Status = 'Closed');
        h = row('FCT Hospital');
        System.assertEquals('Acknowledged', h.Status__c);
        System.assertEquals('Response', h.Acknowledged_By__c);
        System.assertEquals(Date.today(), h.Responded_On__c);
        System.assertEquals('Response Received', h.Case__r.Response_Outcome__c, 'closing with no outcome chosen means the response came in');
        System.assertEquals(1, CqFieldActionCases.submit(fa.Id));
        System.assertNotEquals(null, row('FCT Hospital').Submitted_On__c);

        update new Case(Id = h.Case__c, Status = 'New');
        Test.stopTest();
        h = row('FCT Hospital');
        System.assertEquals('Sent', h.Status__c, 'a reopened Case puts the customer back to pending');
        System.assertEquals(null, h.Submitted_On__c);
        System.assertEquals(null, h.Case__r.Response_Outcome__c);
    }

    @IsTest
    static void aCustomerWhoNeverAnswersIsClosedWithAReasonAndCanBeReopened() {
        Field_Action__c fa = makeFa('Distributor');
        Field_Action_Customer__c h = row('FCT Hospital');
        Boolean refused = false;
        try { CqFieldActionCases.closeWithoutResponse(fa.Id, h.Id, ' '); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'a reason is required');
        Test.startTest();
        CqFieldActionCases.closeWithoutResponse(fa.Id, h.Id, 'Unreachable after 3 attempts');
        h = row('FCT Hospital');
        System.assertEquals(Date.today(), h.Closed_Without_Response_On__c);
        System.assertEquals('Unreachable after 3 attempts', h.No_Response_Reason__c);
        System.assertNotEquals('Acknowledged', h.Status__c, 'closed without a response is not acknowledged');
        System.assertEquals(true, h.Case__r.IsClosed);
        System.assertEquals('No Response', h.Case__r.Response_Outcome__c);

        CqFieldActionCases.reopen(fa.Id, h.Id);
        Test.stopTest();
        h = row('FCT Hospital');
        System.assertEquals(null, h.Closed_Without_Response_On__c);
        System.assertEquals(null, h.No_Response_Reason__c);
        System.assertEquals(false, h.Case__r.IsClosed);
    }

    @IsTest
    static void returningEveryUnitShippedCountsAsTheResponse() {
        Field_Action__c fa = makeFa('Distributor');
        Id hospital = [SELECT Id FROM Account WHERE Name = 'FCT Hospital'].Id, distributor = [SELECT Id FROM Account WHERE Name = 'FCT Distributor'].Id;
        Test.startTest();
        insert new List<Lot_Return__c>{
            new Lot_Return__c(RMA_Number__c = 'RMA-1', Customer__c = hospital, Lot_Number__c = 'FCT-L1', Units_Received__c = 10),
            new Lot_Return__c(RMA_Number__c = 'RMA-2', Customer__c = distributor, Lot_Number__c = 'FCT-L1', Units_Received__c = 6) };
        Test.stopTest();
        Field_Action_Customer__c h = row('FCT Hospital'), d = row('FCT Distributor');
        System.assertEquals('Acknowledged', h.Status__c, 'all 10 units shipped came back');
        System.assertEquals('Full Return', h.Acknowledged_By__c);
        System.assertEquals(true, h.Case__r.IsClosed);
        System.assertEquals(10, [SELECT Units_Returning__c FROM Customer_Response_Line__c WHERE Field_Action_Customer__c = :h.Id].Units_Returning__c);
        System.assertEquals('Sent', d.Status__c, '6 of 40 back leaves the rest unexplained: still pending');
        System.assertEquals(false, d.Case__r.IsClosed);
    }

    @IsTest
    static void theNoticeAndFollowUpsAreRecordedOnEveryOpenCase() {
        Field_Action__c fa = makeFa('Distributor');
        Test.startTest();
        System.assertEquals(2, CqFieldActionCases.markNoticeSent(fa.Id));
        System.assertEquals(Date.today(), row('FCT Hospital').Notice_Sent_On__c, 'the date on the Case shows on the customer\'s row');
        Boolean refused = false;
        try { CqFieldActionCases.markNoticeSent(fa.Id); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused, 'nothing left to mark');
        System.assertEquals(2, CqFieldActionCases.followUp(fa.Id));
        Test.stopTest();
        Field_Action_Customer__c h = row('FCT Hospital');
        System.assertEquals(1, h.Follow_Ups__c);
        System.assertEquals(1, [SELECT COUNT() FROM Task WHERE WhatId = :h.Case__c AND Subject = 'Follow-up sent']);
        update new Case(Id = h.Case__c, Response_Due__c = Date.today().addDays(21));
        System.assertEquals(Date.today().addDays(21), row('FCT Hospital').Response_Due__c, 'an extension agreed on the Case moves the due date');
    }

    @IsTest
    static void whatTheCustomerReportedIsEnteredOnTheCase() {
        Field_Action__c fa = makeFa('Distributor');
        Field_Action_Customer__c h = row('FCT Hospital');
        Test.startTest();
        CqFieldActionCases.CaseView v = CqFieldActionCases.caseView(h.Case__c);
        System.assertEquals(true, v.fieldAction);
        System.assertEquals('FCT Hospital', v.customer);
        System.assertEquals(1, v.lines.size());
        System.assertEquals(10, v.lines[0].shipped);
        CqFieldActionCases.saveCaseLine(h.Case__c, 'FCT-L1', 'used', 3);
        v = CqFieldActionCases.saveCaseLine(h.Case__c, 'FCT-L1', 'returning', 5);
        System.assertEquals(2, v.lines[0].unknown, '10 shipped less 3 used and 5 returning');
        Boolean refused = false;
        try { CqFieldActionCases.saveCaseLine(h.Case__c, 'FCT-L1', 'colour', 1); } catch (AuraHandledException e) { refused = true; }
        System.assert(refused);
        update new Case(Id = h.Case__c, Status = 'Closed');
        Test.stopTest();
        System.assertEquals('Acknowledged', row('FCT Hospital').Status__c, 'with the figures in, the Case closes as Response Received');
        Case plain = new Case(Subject = 'An ordinary case');
        insert plain;
        System.assertEquals(false, CqFieldActionCases.caseView(plain.Id).fieldAction);
    }
}

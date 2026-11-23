/** How Far It Goes decides who is notified: at distributor level, only the distributors that received the lots. */
@IsTest
private class CqFieldActionDepthTest {

    /** One lot shipped to a distributor, a hospital and an account with no type. */
    static Field_Action__c makeFa(String depth) {
        List<Account> accs = new List<Account>{
            new Account(Name = 'FDT Distributor', Customer_Type__c = 'Distributor'),
            new Account(Name = 'FDT Hospital', Customer_Type__c = 'Hospital'),
            new Account(Name = 'FDT Untyped') };
        insert accs;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Depth test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.WITHDRAWAL, Depth__c = depth,
            Check_Level__c = 'Level C', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FDT-L1', In_Scope__c = true, Approved_In_Scope__c = true, Added_How__c = 'Automatic');
        insert new List<Lot_Shipment__c>{
            new Lot_Shipment__c(Lot_Number__c = 'FDT-L1', Units__c = 40, Customer__c = accs[0].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FDT-L1', Units__c = 10, Customer__c = accs[1].Id),
            new Lot_Shipment__c(Lot_Number__c = 'FDT-L1', Units__c = 5, Customer__c = accs[2].Id) };
        return fa;
    }
    static Set<String> names(CqFieldActionNotify.View v) {
        Set<String> out = new Set<String>();
        for (CqFieldActionNotify.Cust c : v.customers) { out.add(c.name); }
        return out;
    }

    @IsTest
    static void distributorLevelNotifiesOnlyTheDistributors() {
        Field_Action__c fa = makeFa('Distributor');
        Test.startTest();
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        Test.stopTest();
        System.assertEquals(new Set<String>{ 'FDT Distributor', 'FDT Untyped' }, names(v), 'the hospital that bought direct is left out; an untyped account stays in');
        System.assert(v.leftOut.contains('1 hospital bought these lots direct'), v.leftOut);
        System.assert(v.leftOut.contains('no Customer Type'), v.leftOut);
        System.assertEquals('Distributor', v.customers[0].type);
        System.assertEquals(2, CqFieldActionNotify.counts(fa.Id).get('total'));
        System.assertEquals(3, [SELECT COUNT() FROM Field_Action_Customer__c WHERE Field_Action__c = :fa.Id], 'the hospital is kept, just not notified at this depth');

        v = CqFieldActionNotify.markSent(fa.Id, null);
        System.assertEquals(null, [SELECT Notice_Sent_On__c FROM Field_Action_Customer__c WHERE Customer_Name__c = 'FDT Hospital'].Notice_Sent_On__c,
            'Mark Sent does not mark a customer this depth leaves out');
    }

    @IsTest
    static void hospitalLevelNotifiesEveryone() {
        Field_Action__c fa = makeFa('Hospital');
        CqFieldActionNotify.View v = CqFieldActionNotify.getView(fa.Id);
        System.assertEquals(3, v.customers.size());
        System.assertEquals(null, v.leftOut, 'nobody is left out at hospital level');
    }

    @IsTest
    static void recoveryListsTheSameCustomers() {
        Field_Action__c fa = makeFa('Distributor');
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(2, v.total, 'Recovery measures the customers this depth reaches');
        for (CqFieldActionTasks.Suggestion s : v.tasks.suggestions) {
            System.assertNotEquals('FDT Hospital', s.customer, 'no tasks are suggested for a customer left out');
        }
    }
}

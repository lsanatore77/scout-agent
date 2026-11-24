/** How Far It Goes decides who is listed: everyone we shipped to, and a distributor's own customers from Hospital depth down. */
@IsTest
private class CqFieldActionDepthTest {
    @IsTest
    static void everyoneWeShippedToIsListedAtEveryDepth() {
        for (String depth : new List<String>{ 'Distributor', 'Hospital', 'Patient', null }) {
            System.assert(CqFieldActionDepth.listed(depth, CqFieldActionDepth.DISTRIBUTOR), depth);
            System.assert(CqFieldActionDepth.listed(depth, CqFieldActionDepth.DIRECT), depth);
            System.assert(CqFieldActionDepth.listed(depth, null), 'a customer added by hand is always listed');
        }
    }
    @IsTest
    static void aDistributorsCustomersAreListedBelowDistributorDepth() {
        System.assertEquals(false, CqFieldActionDepth.listed('Distributor', CqFieldActionDepth.CUSTOMER));
        System.assertEquals(true, CqFieldActionDepth.listed('Hospital', CqFieldActionDepth.CUSTOMER));
        System.assertEquals(true, CqFieldActionDepth.listed('Patient', CqFieldActionDepth.CUSTOMER));
        System.assertEquals(false, CqFieldActionDepth.listsCustomers('Distributor'));
        System.assertEquals(true, CqFieldActionDepth.listsCustomers('Hospital'));
    }
    @IsTest
    static void kindComesFromTheAccountsCustomerType() {
        System.assertEquals('Distributor', CqFieldActionDepth.kindOf('Distributor'));
        System.assertEquals('Direct Customer', CqFieldActionDepth.kindOf('Hospital'));
        System.assertEquals('Direct Customer', CqFieldActionDepth.kindOf(null), 'an Account with no type that we shipped to is a direct customer');
    }
}

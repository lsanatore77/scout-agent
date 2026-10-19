@IsTest
private class PhrLeadListOrderTest {
    @IsTest
    static void priorityTypesAreNonconformanceCapaAndChangeOrder() {
        System.assertEquals(true, PhrLeadListController.isPriorityType('Nonconformance'));
        System.assertEquals(true, PhrLeadListController.isPriorityType('CAPA'));
        System.assertEquals(true, PhrLeadListController.isPriorityType('Change Order'));
    }

    @IsTest
    static void otherTypesAreNotPriority() {
        System.assertEquals(false, PhrLeadListController.isPriorityType('Inspection'));
        System.assertEquals(false, PhrLeadListController.isPriorityType('Investigation'));
        System.assertEquals(false, PhrLeadListController.isPriorityType(null));
    }
}

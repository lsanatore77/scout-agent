/**
 * Test data for the mobile intake tests. A CQ part needs Title and Part Definition when the CQ add-on that adds them
 * (cqext) is installed; they are set here only when the org has them, so the tests run with core CQ alone too.
 */
@IsTest
public class CqIntakeTestData {
    public static compliancequest__SQX_Part__c part(compliancequest__SQX_Part__c p) {
        Map<String, Schema.SObjectField> f = Schema.SObjectType.compliancequest__SQX_Part__c.fields.getMap();
        if (f.containsKey('cqext__Title__c')) { p.put('cqext__Title__c', p.Name); }
        if (f.containsKey('cqext__Part_Definition__c')) { p.put('cqext__Part_Definition__c', 'Individual'); }
        return p;
    }
}

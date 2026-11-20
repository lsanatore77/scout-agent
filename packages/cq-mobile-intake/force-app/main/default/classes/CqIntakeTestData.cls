/**
 * Test data for the mobile intake tests. A CQ part needs Title and Part Definition when the CQ add-on that adds them
 * (cqext) is installed; they are set here only when the org has them, so the tests run with core CQ alone too.
 */
@IsTest
public class CqIntakeTestData {
    /**
     * Gives the running user the package's permission sets (when they are in the org), so the intake code, which
     * reads and writes as the user, can see its own fields. Needed wherever the running admin has no field access to
     * the new fields: a scratch org and the package build org. In an org without these permission sets it does nothing.
     */
    public static void grantAccess() {
        Id me = UserInfo.getUserId();
        Set<Id> have = new Set<Id>();
        for (PermissionSetAssignment a : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :me]) { have.add(a.PermissionSetId); }
        List<PermissionSetAssignment> add = new List<PermissionSetAssignment>();
        for (PermissionSet p : [SELECT Id FROM PermissionSet WHERE Name IN ('CQ_Mobile_Intake_User', 'CQ_Mobile_Intake_Admin')]) {
            if (!have.contains(p.Id)) { add.add(new PermissionSetAssignment(AssigneeId = me, PermissionSetId = p.Id)); }
        }
        if (add.isEmpty()) { return; }
        System.runAs(new User(Id = me)) { insert add; }   // runAs keeps this setup change apart from the test's data
    }

    public static compliancequest__SQX_Part__c part(compliancequest__SQX_Part__c p) {
        Map<String, Schema.SObjectField> f = Schema.SObjectType.compliancequest__SQX_Part__c.fields.getMap();
        if (f.containsKey('cqext__Title__c')) { p.put('cqext__Title__c', p.Name); }
        if (f.containsKey('cqext__Part_Definition__c')) { p.put('cqext__Part_Definition__c', 'Individual'); }
        return p;
    }
}

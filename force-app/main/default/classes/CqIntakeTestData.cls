/**
 * Test data for the mobile intake tests.
 *
 * runner(): the user the intake tests run as. The intake code reads and writes as the user, so the tests need a user
 * with the package's permission sets: in a scratch org or the package build org the running admin has no access to the
 * new fields. When the permission sets are in the org, a test user is made with them (System Administrator profile, for
 * CQ's own objects); in an org without them (dev, where admins already have access) it is the running user.
 *
 * part(): a CQ part needs Title and Part Definition when the CQ add-on that adds them (cqext) is installed; they are set
 * only when the org has them, so the tests run with core CQ alone too.
 */
@IsTest
public class CqIntakeTestData {
    static final String RUNNER_PREFIX = 'intake.runner.';

    public static User runner() {
        List<User> existing = [SELECT Id FROM User WHERE Username LIKE :(RUNNER_PREFIX + '%') AND IsActive = true LIMIT 1];
        if (!existing.isEmpty()) { return existing[0]; }
        List<PermissionSet> sets = [SELECT Id FROM PermissionSet WHERE Name IN ('CQ_Mobile_Intake_User', 'CQ_Mobile_Intake_Admin')];
        User me = new User(Id = UserInfo.getUserId());
        if (sets.isEmpty()) { return me; }
        Profile admin = [SELECT Id FROM Profile WHERE PermissionsModifyAllData = true AND UserType = 'Standard' ORDER BY CreatedDate LIMIT 1];
        User u = new User(LastName = 'Intake Runner', Alias = 'intrun', Email = 'intake.runner@example.com',
            Username = RUNNER_PREFIX + UserInfo.getOrganizationId() + '.' + Crypto.getRandomInteger() + '@example.com',
            ProfileId = admin.Id, EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US',
            TimeZoneSidKey = 'America/Chicago');
        System.runAs(me) {   // keeps the user and permission set setup apart from the test's records
            insert u;
            List<PermissionSetAssignment> a = new List<PermissionSetAssignment>();
            for (PermissionSet p : sets) { a.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = p.Id)); }
            insert a;
        }
        return u;
    }

    public static compliancequest__SQX_Part__c part(compliancequest__SQX_Part__c p) {
        Map<String, Schema.SObjectField> f = Schema.SObjectType.compliancequest__SQX_Part__c.fields.getMap();
        if (f.containsKey('cqext__Title__c')) { p.put('cqext__Title__c', p.Name); }
        if (f.containsKey('cqext__Part_Definition__c')) { p.put('cqext__Part_Definition__c', 'Individual'); }
        return p;
    }
}

/**
 * Where the coordinator is in the Field Action workspace, kept on the record for reports and the record page:
 * Workspace Step (short names) and Started On (the first time the workspace was opened). A closed field action stays Complete.
 */
public with sharing class CqFieldActionProgress {

    /** The workspace's steps in order, by their short names on the record. */
    public static final List<String> STEPS = new List<String>{ 'Glance', 'Scope', 'Strategy', 'Notifications', 'Reporting', 'Recovery', 'Closure' };
    public static final String COMPLETE = 'Complete';

    /** Saves the step the coordinator opened (0 to 6) and, the first time, Started On. */
    @AuraEnabled
    public static void saveStep(Id recordId, Integer step) {
        Field_Action__c fa = [SELECT Status__c, Workspace_Step__c, Started_On__c FROM Field_Action__c WHERE Id = :recordId];
        String name = fa.Status__c == 'Closed' ? COMPLETE
            : step != null && step >= 0 && step < STEPS.size() ? STEPS[step] : fa.Workspace_Step__c;
        if (name == fa.Workspace_Step__c && fa.Started_On__c != null) { return; }
        update new Field_Action__c(Id = recordId, Workspace_Step__c = name,
            Started_On__c = fa.Started_On__c == null ? Datetime.now() : fa.Started_On__c);
    }
}

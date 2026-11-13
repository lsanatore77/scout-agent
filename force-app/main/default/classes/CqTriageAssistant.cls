/**
 * CqTriageAssistant: reads and saves the outcome of the Triage Assistant on a Nonconformance.
 * The outcome is kept in our own Triage_* fields. CQ containment records and CQ's own Required
 * flags are written as separate steps, so a CQ rule that rejects them does not lose the triage.
 */
public with sharing class CqTriageAssistant {
    public static final Set<String> RISKS = new Set<String>{ 'Low', 'Medium', 'High' };
    public static final Set<String> PATHS = new Set<String>{ 'Continue with Investigation', 'Join Investigation', 'New Investigation', 'Log Only' };

    public class Triage {
        @AuraEnabled public String risk; @AuraEnabled public String path; @AuraEnabled public String notes;
        @AuraEnabled public String setBy; @AuraEnabled public Datetime setOn;
        @AuraEnabled public List<String> created = new List<String>();   // containment numbers created by this save
        @AuraEnabled public String warning;                              // set when CQ would not accept something
    }

    @AuraEnabled
    public static Triage getTriage(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT Triage_Risk__c, Triage_Path__c, Triage_Notes__c, Triage_By__r.Name, Triage_On__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
        Triage t = new Triage();
        t.risk = nc.Triage_Risk__c; t.path = nc.Triage_Path__c; t.notes = nc.Triage_Notes__c;
        t.setBy = nc.Triage_By__r?.Name; t.setOn = nc.Triage_On__c;
        return t;
    }

    @AuraEnabled
    public static Triage saveTriage(Id recordId, String risk, String path, String notes, Boolean containment, Boolean investigate,
                                    List<String> containmentTitles, String dueDate) {
        if (!RISKS.contains(risk)) { throw new AuraHandledException('Choose a risk.'); }
        if (!PATHS.contains(path)) { throw new AuraHandledException('Choose a path.'); }
        compliancequest__SQX_Nonconformance__c nc = new compliancequest__SQX_Nonconformance__c(Id = recordId);
        nc.Triage_Risk__c = risk; nc.Triage_Path__c = path; nc.Triage_Notes__c = notes;
        nc.Triage_By__c = UserInfo.getUserId(); nc.Triage_On__c = Datetime.now();
        update nc;

        List<String> warnings = new List<String>();
        List<String> created = new List<String>();

        // One CQ containment per action chosen at triage, assigned to the triager.
        if (containmentTitles != null && !containmentTitles.isEmpty()) {
            Savepoint sp = Database.setSavepoint();
            try {
                Date due = String.isBlank(dueDate) ? Date.today().addDays(1) : Date.valueOf(dueDate);
                String ncName = [SELECT Name FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId].Name;
                List<compliancequest__SQX_Containment__c> rows = new List<compliancequest__SQX_Containment__c>();
                for (String title : containmentTitles) {
                    if (String.isBlank(title)) { continue; }
                    rows.add(new compliancequest__SQX_Containment__c(
                        compliancequest__SQX_Nonconformance__c = recordId,
                        compliancequest__Title__c = title.trim().left(255),
                        compliancequest__Description__c = 'Raised at triage of ' + ncName + '.',
                        compliancequest__Due_Date__c = due,
                        compliancequest__SQX_User__c = UserInfo.getUserId()));
                }
                insert rows;
                for (compliancequest__SQX_Containment__c c : [SELECT Name FROM compliancequest__SQX_Containment__c WHERE Id IN :rows ORDER BY Name]) {
                    created.add(c.Name);
                }
            } catch (Exception e) {
                Database.rollback(sp);
                created.clear();
                warnings.add('CQ did not accept the containment records: ' + e.getMessage());
            }
        }

        try {
            compliancequest__SQX_Nonconformance__c flags = new compliancequest__SQX_Nonconformance__c(Id = recordId);
            flags.compliancequest__Containment_Required__c = containment == true;
            flags.compliancequest__Investigation_Required__c = investigate == true;
            flags.compliancequest__Disposition_Required__c = investigate != true;
            update flags;
        } catch (Exception e) {
            warnings.add('CQ did not accept its Containment / Investigation / Disposition Required flags: ' + e.getMessage());
        }

        Triage t = getTriage(recordId);
        t.created = created;
        t.warning = warnings.isEmpty() ? null : 'Triage saved. ' + String.join(warnings, ' ');
        return t;
    }
}

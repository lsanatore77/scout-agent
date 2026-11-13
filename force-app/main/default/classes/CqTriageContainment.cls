/** Add Containment in the Triage Assistant: creates one CQ containment on the Nonconformance straight away. */
public with sharing class CqTriageContainment {
    @AuraEnabled
    public static String create(Id recordId, String title, String description, String dueDate, Id assigneeId) {
        if (recordId == null || String.isBlank(title)) { throw new AuraHandledException('Give the containment a title.'); }
        compliancequest__SQX_Containment__c c = new compliancequest__SQX_Containment__c(
            compliancequest__SQX_Nonconformance__c = recordId,
            compliancequest__Title__c = title.trim().left(255),
            compliancequest__Description__c = String.isBlank(description) ? null : description.trim(),
            compliancequest__Due_Date__c = String.isBlank(dueDate) ? Date.today().addDays(1) : Date.valueOf(dueDate),
            compliancequest__SQX_User__c = assigneeId == null ? UserInfo.getUserId() : assigneeId);
        try {
            insert c;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not accept the containment: ' + e.getDmlMessage(0));
        }
        return [SELECT Name FROM compliancequest__SQX_Containment__c WHERE Id = :c.Id].Name;
    }
}

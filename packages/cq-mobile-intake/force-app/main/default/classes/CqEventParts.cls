/** Part search for the Report a Problem part picker: suggested parts (most recently used on events, NCs and complaints) and search by number or name. */
public with sharing class CqEventParts {
    public class Part {
        @AuraEnabled public Id id; @AuraEnabled public String partNumber; @AuraEnabled public String name;
    }

    @AuraEnabled(cacheable=true)
    public static List<Part> suggested() {
        List<Id> order = new List<Id>();
        Set<Id> seen = new Set<Id>();
        for (Quality_Event__c e : [SELECT Part__c FROM Quality_Event__c WHERE Part__c != null WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50]) { add(e.Part__c, order, seen); }
        for (compliancequest__SQX_Nonconformance__c n : [SELECT compliancequest__SQX_Part__c FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__SQX_Part__c != null WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50]) { add(n.compliancequest__SQX_Part__c, order, seen); }
        for (compliancequest__SQX_Complaint__c c : [SELECT compliancequest__SQX_Part__c FROM compliancequest__SQX_Complaint__c
                WHERE compliancequest__SQX_Part__c != null WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 50]) { add(c.compliancequest__SQX_Part__c, order, seen); }
        Map<Id, compliancequest__SQX_Part__c> parts = new Map<Id, compliancequest__SQX_Part__c>(
            [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id IN :seen WITH USER_MODE]);
        List<Part> out = new List<Part>();
        for (Id i : order) {
            if (parts.containsKey(i) && out.size() < 8) { out.add(part(parts.get(i))); }
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static List<Part> search(String term) {
        List<Part> out = new List<Part>();
        if (String.isBlank(term) || term.trim().length() < 2) { return out; }
        String pat = '%' + term.trim() + '%';
        for (compliancequest__SQX_Part__c p : [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                WHERE compliancequest__Part_Number__c LIKE :pat OR Name LIKE :pat WITH USER_MODE ORDER BY compliancequest__Part_Number__c LIMIT 10]) {
            out.add(part(p));
        }
        return out;
    }

    static void add(Id i, List<Id> order, Set<Id> seen) { if (!seen.contains(i)) { seen.add(i); order.add(i); } }
    static Part part(compliancequest__SQX_Part__c p) {
        Part x = new Part(); x.id = p.Id; x.partNumber = p.compliancequest__Part_Number__c; x.name = p.Name;
        return x;
    }
}

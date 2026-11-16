/** The lots CQ has for a part (Lot Info, matched on the part number), newest first, for the Lot dropdowns on Report a Problem. */
public with sharing class CqEventLots {
    @AuraEnabled(cacheable=true)
    public static List<String> getLots(Id partId) {
        List<String> out = new List<String>();
        if (partId == null) { return out; }
        Set<String> keys = new Set<String>();
        for (compliancequest__SQX_Part__c p : [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id = :partId WITH USER_MODE]) {
            if (p.compliancequest__Part_Number__c != null) { keys.add(p.compliancequest__Part_Number__c); }
            keys.add(p.Name);
        }
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c IN :keys
                                                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 200]) {
            out.add(l.Name);
        }
        return out;
    }
}

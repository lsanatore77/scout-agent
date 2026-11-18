/** Lots CQ has (Lot Info): the lots for a part, and the lot search for Report a Problem, where the lot is chosen first and the part fills in from it. */
public with sharing class CqEventLots {
    public class Lot {
        @AuraEnabled public String lot; @AuraEnabled public String partNumber; @AuraEnabled public Id partId; @AuraEnabled public String partName;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getLots(Id partId) {
        List<String> out = new List<String>();
        if (partId == null) { return out; }
        Set<String> keys = partKeys(partId);
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c IN :keys
                                                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 200]) {
            out.add(l.Name);
        }
        return out;
    }

    /** Lots matching a lot number (2 or more characters), or the newest lots when the term is blank; only the part's lots when a part is given. Each lot carries its part. */
    @AuraEnabled(cacheable=true)
    public static List<Lot> searchLots(String term, Id partId) {
        String t = term == null ? '' : term.trim();
        Boolean searching = t.length() >= 2;
        String pat = '%' + t.replace('%', '\\%').replace('_', '\\_') + '%';
        List<compliancequest__SQX_Lot_Info__c> lots;
        if (partId != null) {
            Set<String> keys = partKeys(partId);
            lots = searching
                ? [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c IN :keys AND Name LIKE :pat
                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 50]
                : [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c WHERE compliancequest__Part_Number__c IN :keys
                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 50];
        } else {
            lots = searching
                ? [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c WHERE Name LIKE :pat
                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 20]
                : [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Lot_Info__c
                   WITH USER_MODE ORDER BY compliancequest__Manufacturing_Date__c DESC NULLS LAST, Name DESC LIMIT 8];
        }
        Set<String> nums = new Set<String>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            if (l.compliancequest__Part_Number__c != null) { nums.add(l.compliancequest__Part_Number__c); }
        }
        // Lot Info holds the part as text: match it to a Part by part number first, then by name
        Map<String, compliancequest__SQX_Part__c> byNumber = new Map<String, compliancequest__SQX_Part__c>();
        Map<String, compliancequest__SQX_Part__c> byName = new Map<String, compliancequest__SQX_Part__c>();
        if (!nums.isEmpty()) {
            for (compliancequest__SQX_Part__c p : [SELECT Id, Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c
                                                   WHERE compliancequest__Part_Number__c IN :nums OR Name IN :nums WITH USER_MODE]) {
                if (p.compliancequest__Part_Number__c != null) { byNumber.put(p.compliancequest__Part_Number__c.toLowerCase(), p); }
                byName.put(p.Name.toLowerCase(), p);
            }
        }
        List<Lot> out = new List<Lot>();
        for (compliancequest__SQX_Lot_Info__c l : lots) {
            Lot o = new Lot();
            o.lot = l.Name;
            o.partNumber = l.compliancequest__Part_Number__c;
            String k = l.compliancequest__Part_Number__c == null ? null : l.compliancequest__Part_Number__c.toLowerCase();
            compliancequest__SQX_Part__c p = k == null ? null : (byNumber.containsKey(k) ? byNumber.get(k) : byName.get(k));
            if (p != null) { o.partId = p.Id; o.partName = p.Name; if (p.compliancequest__Part_Number__c != null) { o.partNumber = p.compliancequest__Part_Number__c; } }
            out.add(o);
        }
        return out;
    }

    static Set<String> partKeys(Id partId) {
        Set<String> keys = new Set<String>();
        for (compliancequest__SQX_Part__c p : [SELECT Name, compliancequest__Part_Number__c FROM compliancequest__SQX_Part__c WHERE Id = :partId WITH USER_MODE]) {
            if (p.compliancequest__Part_Number__c != null) { keys.add(p.compliancequest__Part_Number__c); }
            keys.add(p.Name);
        }
        return keys;
    }
}

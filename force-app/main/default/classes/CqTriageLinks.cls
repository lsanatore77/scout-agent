/**
 * CqTriageLinks: the Investigation Links step of the Triage Assistant.
 * Every NC gets its own investigation. Other investigations can be linked to the NC as research only;
 * a link is a CQ Nonconformance Investigation row and never replaces the NC's own investigation.
 * CQ.AI suggests investigations on the same part, strongest first (same lot, then ones with findings written up).
 */
public with sharing class CqTriageLinks {
    public class Inv {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String ncName; @AuraEnabled public String status;
        @AuraEnabled public String summary; @AuraEnabled public String why;
        @AuraEnabled public Boolean suggested = false; @AuraEnabled public Boolean linked = false;
    }
    public class Links {
        @AuraEnabled public String ownName; @AuraEnabled public Date due; @AuraEnabled public Boolean required;
        @AuraEnabled public List<Inv> items = new List<Inv>();
    }

    private static Inv toInv(compliancequest__SQX_Investigation__c i, String lot) {
        Inv v = new Inv();
        v.id = i.Id; v.name = i.Name; v.status = i.compliancequest__Status__c;
        v.ncName = i.compliancequest__SQX_Nonconformance__r?.Name;
        String s = i.compliancequest__Investigation_Summary__c;
        if (String.isNotBlank(s)) { v.summary = s.stripHtmlTags().abbreviate(180); }
        Boolean sameLot = lot != null && i.compliancequest__SQX_Nonconformance__r != null
            && i.compliancequest__SQX_Nonconformance__r.compliancequest__Lot_Number__c == lot;
        v.why = sameLot ? 'Same part and same lot' : 'Same part';
        v.suggested = sameLot || v.summary != null;
        return v;
    }

    @AuraEnabled
    public static Links getLinks(Id recordId) {
        compliancequest__SQX_Nonconformance__c nc = [
            SELECT compliancequest__SQX_Part__c, compliancequest__Lot_Number__c, compliancequest__Investigation_Required__c,
                   compliancequest__Due_Date_Investigation__c, compliancequest__SQX_Investigation__c, compliancequest__SQX_Investigation__r.Name,
                   compliancequest__SQX_Investigation__r.compliancequest__SQX_Nonconformance__c
            FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId];
        Links r = new Links();
        r.required = nc.compliancequest__Investigation_Required__c == true;
        r.due = nc.compliancequest__Due_Date_Investigation__c;
        // Only count the investigation as this NC's own when it really belongs to this NC
        Boolean own = nc.compliancequest__SQX_Investigation__c != null
            && nc.compliancequest__SQX_Investigation__r.compliancequest__SQX_Nonconformance__c == recordId;
        if (own) { r.ownName = nc.compliancequest__SQX_Investigation__r.Name; }

        Set<Id> linked = new Set<Id>();
        for (compliancequest__SQX_NC_Investigation__c x : [
                SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_NC_Investigation__c
                WHERE compliancequest__SQX_Nonconformance__c = :recordId]) {
            linked.add(x.compliancequest__SQX_Investigation__c);
        }

        List<Inv> strong = new List<Inv>(); List<Inv> rest = new List<Inv>();
        if (nc.compliancequest__SQX_Part__c != null || !linked.isEmpty()) {
            for (compliancequest__SQX_Investigation__c i : [
                    SELECT Id, Name, compliancequest__Status__c, compliancequest__Investigation_Summary__c,
                           compliancequest__SQX_Nonconformance__r.Name, compliancequest__SQX_Nonconformance__r.compliancequest__Lot_Number__c
                    FROM compliancequest__SQX_Investigation__c
                    WHERE compliancequest__SQX_Nonconformance__c != :recordId
                      AND (Id IN :linked OR (compliancequest__SQX_Nonconformance__r.compliancequest__SQX_Part__c = :nc.compliancequest__SQX_Part__c
                                             AND compliancequest__SQX_Nonconformance__r.compliancequest__SQX_Part__c != null))
                    ORDER BY CreatedDate DESC LIMIT 25]) {
                Inv v = toInv(i, nc.compliancequest__Lot_Number__c);
                v.linked = linked.contains(i.Id);
                if (v.suggested || v.linked) { strong.add(v); } else { rest.add(v); }
            }
        }
        r.items.addAll(strong); r.items.addAll(rest);
        return r;
    }

    /** One investigation picked by hand, in the same shape as a suggestion. */
    @AuraEnabled
    public static Inv getOne(Id recordId, Id investigationId) {
        String lot = [SELECT compliancequest__Lot_Number__c FROM compliancequest__SQX_Nonconformance__c WHERE Id = :recordId].compliancequest__Lot_Number__c;
        Inv v = toInv([
            SELECT Id, Name, compliancequest__Status__c, compliancequest__Investigation_Summary__c,
                   compliancequest__SQX_Nonconformance__r.Name, compliancequest__SQX_Nonconformance__r.compliancequest__Lot_Number__c
            FROM compliancequest__SQX_Investigation__c WHERE Id = :investigationId], lot);
        v.why = 'Added by you'; v.suggested = false;
        return v;
    }

    /** Links the chosen investigations to the NC. Ones already linked are skipped. Returns the names linked now. */
    @AuraEnabled
    public static List<String> saveLinks(Id recordId, List<Id> investigationIds) {
        List<String> names = new List<String>();
        if (investigationIds == null || investigationIds.isEmpty()) { return names; }
        Set<Id> have = new Set<Id>();
        for (compliancequest__SQX_NC_Investigation__c x : [
                SELECT compliancequest__SQX_Investigation__c FROM compliancequest__SQX_NC_Investigation__c
                WHERE compliancequest__SQX_Nonconformance__c = :recordId]) {
            have.add(x.compliancequest__SQX_Investigation__c);
        }
        List<compliancequest__SQX_NC_Investigation__c> rows = new List<compliancequest__SQX_NC_Investigation__c>();
        Set<Id> adding = new Set<Id>();
        for (Id i : investigationIds) {
            if (i == null || have.contains(i) || adding.contains(i)) { continue; }
            adding.add(i);
            rows.add(new compliancequest__SQX_NC_Investigation__c(compliancequest__SQX_Nonconformance__c = recordId, compliancequest__SQX_Investigation__c = i));
        }
        if (rows.isEmpty()) { return names; }
        try {
            insert rows;
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not accept the investigation links: ' + e.getDmlMessage(0));
        }
        for (compliancequest__SQX_Investigation__c i : [SELECT Name FROM compliancequest__SQX_Investigation__c WHERE Id IN :adding ORDER BY Name]) { names.add(i.Name); }
        return names;
    }
}

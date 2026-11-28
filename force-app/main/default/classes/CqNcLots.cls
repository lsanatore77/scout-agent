/**
 * An NC's lot is always one of its lots (Lou, 28 Nov 2026). The NC's own Lot Number is where the problem was found; the
 * lots it affects are CQ Impacted Products (part, lot, quantity), which Disposition works from. Nothing in CQ copies the
 * one into the other, so an NC could reach Disposition with a lot and nothing to dispose (NC-000049). People only ever
 * see "lot"; Impacted Products are how CQ stores them.
 *
 * After an NC is saved with a lot, by any screen, import or script: if that lot is not among its Impacted Products, it is
 * added, with the NC's part and its Defective Quantity. CQ needs a quantity for a lot, so with none the lot is not added
 * here; the Triage Impact step and Dispose by Lot ask for it (CqTriageImpact.missingLot).
 *
 * From Implement on, CQ refuses changes to an NC's lots, so changing the NC's Lot Number then is refused too: the two
 * could no longer match. Closed and Void NCs are locked by CQ itself.
 *
 * Never blocks saving the NC for the add: a lot CQ refuses is left for the Impact step to ask about.
 * Loads by users with CQ's Data Migration permission are left alone (CQ's own rule for imports).
 * without sharing: the person saving the NC may not be able to add its lots themselves; keeping them in step is the system's job.
 */
public without sharing class CqNcLots {
    public static final Set<String> FIXED = new Set<String>{ 'Implement', 'Verification' };
    public static final Set<String> LOCKED = new Set<String>{ 'Implement', 'Verification', 'Closed' };
    public static final String LOT_FIXED = 'The lot can\'t change once the NC is in Implement.';

    /** Other classes' tests insert NCs with lots and add their own lots; only this class's tests turn it on. */
    @TestVisible static Boolean runInTests = false;
    static Boolean active() { return !Test.isRunningTest() || runInTests; }
    static Boolean migrating() { return FeatureManagement.checkPermission('compliancequest__SQXDataMigrationCustomPermission'); }

    /** Before update: the lot is fixed from Implement on. */
    public static void beforeUpdate(List<compliancequest__SQX_Nonconformance__c> rows, Map<Id, compliancequest__SQX_Nonconformance__c> old) {
        if (!active() || migrating()) { return; }
        for (compliancequest__SQX_Nonconformance__c n : rows) {
            compliancequest__SQX_Nonconformance__c o = old.get(n.Id);
            if (o == null || same(n.compliancequest__Lot_Number__c, o.compliancequest__Lot_Number__c)) { continue; }
            if (FIXED.contains(o.compliancequest__Record_Stage__c)) { n.compliancequest__Lot_Number__c.addError(LOT_FIXED); }
        }
    }

    /** After insert or update: the NC's lot is added to its lots when it is not there yet. */
    public static void afterSave(List<compliancequest__SQX_Nonconformance__c> rows, Map<Id, compliancequest__SQX_Nonconformance__c> old) {
        if (!active() || migrating()) { return; }
        Set<Id> ids = new Set<Id>();
        for (compliancequest__SQX_Nonconformance__c n : rows) {
            if (String.isBlank(n.compliancequest__Lot_Number__c) || LOCKED.contains(n.compliancequest__Record_Stage__c)) { continue; }
            compliancequest__SQX_Nonconformance__c o = old == null ? null : old.get(n.Id);
            // on update, only when something the add depends on changed
            if (o != null && same(n.compliancequest__Lot_Number__c, o.compliancequest__Lot_Number__c)
                    && n.compliancequest__SQX_Part__c == o.compliancequest__SQX_Part__c
                    && n.compliancequest__Defective_Quantity__c == o.compliancequest__Defective_Quantity__c) { continue; }
            ids.add(n.Id);
        }
        if (ids.isEmpty()) { return; }
        try {
            ensure(ids);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'CqNcLots: ' + e.getMessage());
        }
    }

    /** Adds each NC's own lot to its lots where it is missing and the NC has a quantity. Returns how many were added. */
    public static Integer ensure(Set<Id> ncIds) {
        List<compliancequest__SQX_NC_Impacted_Product__c> adds = new List<compliancequest__SQX_NC_Impacted_Product__c>();
        Map<Id, List<compliancequest__SQX_NC_Impacted_Product__c>> lotsOf = lotsOf(ncIds);
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c, compliancequest__Defective_Quantity__c,
                       compliancequest__Record_Stage__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id IN :ncIds]) {
            if (String.isBlank(n.compliancequest__Lot_Number__c) || LOCKED.contains(n.compliancequest__Record_Stage__c)) { continue; }
            if (has(lotsOf.get(n.Id), n.compliancequest__Lot_Number__c)) { continue; }
            Decimal qty = n.compliancequest__Defective_Quantity__c;
            if (qty == null || qty <= 0) { continue; }   // CQ needs a quantity: the Impact step asks for it
            adds.add(new compliancequest__SQX_NC_Impacted_Product__c(compliancequest__SQX_Nonconformance__c = n.Id,
                compliancequest__SQX_Impacted_Part__c = n.compliancequest__SQX_Part__c,
                compliancequest__Lot_Number__c = n.compliancequest__Lot_Number__c.trim().left(80),
                compliancequest__Lot_Quantity__c = qty));
        }
        if (adds.isEmpty()) { return 0; }
        Integer n = 0;
        for (Database.SaveResult r : Database.insert(adds, false)) { if (r.isSuccess()) { n++; } else { System.debug(LoggingLevel.WARN, 'CqNcLots add: ' + r.getErrors()); } }
        return n;
    }

    /** Each NC's lots (Impacted Products), oldest first. */
    public static Map<Id, List<compliancequest__SQX_NC_Impacted_Product__c>> lotsOf(Set<Id> ncIds) {
        Map<Id, List<compliancequest__SQX_NC_Impacted_Product__c>> out = new Map<Id, List<compliancequest__SQX_NC_Impacted_Product__c>>();
        for (compliancequest__SQX_NC_Impacted_Product__c l : [SELECT Id, compliancequest__SQX_Nonconformance__c, compliancequest__Lot_Number__c
                FROM compliancequest__SQX_NC_Impacted_Product__c WHERE compliancequest__SQX_Nonconformance__c IN :ncIds ORDER BY CreatedDate, Name]) {
            if (!out.containsKey(l.compliancequest__SQX_Nonconformance__c)) { out.put(l.compliancequest__SQX_Nonconformance__c, new List<compliancequest__SQX_NC_Impacted_Product__c>()); }
            out.get(l.compliancequest__SQX_Nonconformance__c).add(l);
        }
        return out;
    }

    public static Boolean has(List<compliancequest__SQX_NC_Impacted_Product__c> lots, String lot) {
        if (lots == null) { return false; }
        for (compliancequest__SQX_NC_Impacted_Product__c l : lots) { if (same(l.compliancequest__Lot_Number__c, lot)) { return true; } }
        return false;
    }

    public static Boolean same(String a, String b) {
        return (a == null ? '' : a.trim().toUpperCase()) == (b == null ? '' : b.trim().toUpperCase());
    }
}

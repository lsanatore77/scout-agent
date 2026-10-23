/**
 * Works out which complaint (and which Product History Review) an agent action is about,
 * whatever record page the agent was opened from.
 *
 * Accepted record Ids:
 *  - Complaint                  -> that complaint
 *  - Product History Review     -> its complaint
 *  - CQ Task (Task)             -> the complaint (or the PHR's complaint) it belongs to
 *  - Investigation              -> the complaint it is the primary investigation of, else the complaint
 *                                  it was opened from, else the first complaint it is linked to
 *
 * Every lookup runs in USER_MODE, so the running user's access is respected. Unknown Ids give null.
 */
public with sharing class PhrRecordContext {

    public static final String COMPLAINT_OBJ = 'compliancequest__SQX_Complaint__c';
    public static final String PHR_OBJ = 'compliancequest__SQX_Product_History_Review__c';
    public static final String INVESTIGATION_OBJ = 'compliancequest__SQX_Investigation__c';

    /** The type of record an Id points to, as an object API name ('' for null). */
    public static String objectOf(Id recordId) {
        return recordId == null ? '' : String.valueOf(recordId.getSobjectType());
    }

    public static Boolean isInvestigation(Id recordId) { return objectOf(recordId) == INVESTIGATION_OBJ; }
    public static Boolean isPhr(Id recordId) { return objectOf(recordId) == PHR_OBJ; }

    /** Text Id version: blank or invalid text gives null. */
    public static Id complaintIdFor(String recordId) {
        if (String.isBlank(recordId)) { return null; }
        Id rid;
        try { rid = (Id) recordId.trim(); } catch (Exception e) { return null; }
        return complaintIdFor(rid);
    }

    /** The complaint behind a Complaint, PHR, CQ Task or Investigation Id, or null. */
    public static Id complaintIdFor(Id recordId) {
        if (recordId == null) { return null; }
        String t = objectOf(recordId);
        if (t == COMPLAINT_OBJ) { return recordId; }
        if (t == PHR_OBJ) { return complaintOfPhr(recordId); }
        if (t == INVESTIGATION_OBJ) { return complaintOfInvestigation(recordId); }
        if (t == 'Task') {
            for (Task tk : [SELECT WhatId FROM Task WHERE Id = :recordId WITH USER_MODE LIMIT 1]) {
                String what = objectOf(tk.WhatId);
                if (what == COMPLAINT_OBJ) { return tk.WhatId; }
                if (what == PHR_OBJ) { return complaintOfPhr(tk.WhatId); }
                if (what == INVESTIGATION_OBJ) { return complaintOfInvestigation(tk.WhatId); }
            }
        }
        return null;
    }

    /**
     * The Product History Review to use: the record itself when the agent was opened on a PHR,
     * otherwise the complaint's most recent PHR. Null when the complaint has none.
     */
    public static Id phrIdFor(Id recordId) {
        if (recordId == null) { return null; }
        if (isPhr(recordId)) { return recordId; }
        Id complaintId = complaintIdFor(recordId);
        if (complaintId == null) { return null; }
        for (compliancequest__SQX_Product_History_Review__c p : [
            SELECT Id FROM compliancequest__SQX_Product_History_Review__c
            WHERE compliancequest__SQX_Complaint__c = :complaintId
            WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1
        ]) {
            return p.Id;
        }
        return null;
    }

    static Id complaintOfPhr(Id phrId) {
        for (compliancequest__SQX_Product_History_Review__c p : [
            SELECT compliancequest__SQX_Complaint__c FROM compliancequest__SQX_Product_History_Review__c
            WHERE Id = :phrId WITH USER_MODE LIMIT 1
        ]) {
            return p.compliancequest__SQX_Complaint__c;
        }
        return null;
    }

    static Id complaintOfInvestigation(Id invId) {
        for (compliancequest__SQX_Complaint__c c : [
            SELECT Id FROM compliancequest__SQX_Complaint__c
            WHERE compliancequest__SQX_Primary_Investigation__c = :invId
            WITH USER_MODE ORDER BY CreatedDate DESC LIMIT 1
        ]) {
            return c.Id;
        }
        for (compliancequest__SQX_Investigation__c inv : [
            SELECT compliancequest__SQX_Complaint__c FROM compliancequest__SQX_Investigation__c
            WHERE Id = :invId WITH USER_MODE LIMIT 1
        ]) {
            if (inv.compliancequest__SQX_Complaint__c != null) { return inv.compliancequest__SQX_Complaint__c; }
        }
        for (compliancequest__SQX_Linked_Investigation__c l : [
            SELECT compliancequest__SQX_Complaint__c FROM compliancequest__SQX_Linked_Investigation__c
            WHERE compliancequest__SQX_Investigation__c = :invId AND compliancequest__SQX_Complaint__c != null
            WITH USER_MODE ORDER BY CreatedDate ASC LIMIT 1
        ]) {
            return l.compliancequest__SQX_Complaint__c;
        }
        return null;
    }
}

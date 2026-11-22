/**
 * CqAuditTrail: what the Audit Trail pop-up (c-cq-audit-trail) shows for a record: one timeline, newest first, of every
 * change, every CQ.AI Suggestion with its facts and records, every decision on a suggestion, and every signature;
 * and the signatures on their own, with the committee seats still waiting.
 *
 * Field Action Reviews and Field Actions; other workspaces add their record type here as they move to the workspace model.
 * Every electronic signature (CqEsign) shows here, in the timeline and in the Signatures list (docs/esignature.md).
 * The person must be able to read the record; the entries themselves are read in system mode, as they are written.
 */
public with sharing class CqAuditTrail {

    public class Src { @AuraEnabled public String label; @AuraEnabled public String id; }
    public class Entry implements Comparable {
        /** Newest first. */
        public Integer compareTo(Object o) {
            Datetime b = ((Entry) o).at;
            if (at == b) { return 0; }
            if (at == null) { return 1; }
            if (b == null) { return -1; }
            return at > b ? -1 : 1;
        }
        @AuraEnabled public String id; @AuraEnabled public Datetime at; @AuraEnabled public String who; @AuraEnabled public Boolean cq = false;
        @AuraEnabled public String kind;      // suggestion, decision, edit, signature, create, delete
        @AuraEnabled public String title; @AuraEnabled public String detail;
        @AuraEnabled public List<String> facts = new List<String>();
        @AuraEnabled public List<Src> sources = new List<Src>();
        @AuraEnabled public String result;    // for a suggestion: Accepted, Changed, Not Answered Yet, Replaced
        @AuraEnabled public String resultBy;
        @AuraEnabled public Boolean changed = false;   // a decision that went against CQ.AI, or a suggestion that was changed
        @AuraEnabled public String cqValue; @AuraEnabled public String personValue; @AuraEnabled public String reason;
        @AuraEnabled public String suggestionId; @AuraEnabled public Datetime suggestionAt;
    }
    public class Sign {
        @AuraEnabled public String key; @AuraEnabled public Datetime at; @AuraEnabled public String who; @AuraEnabled public String seat;
        @AuraEnabled public String meaning; @AuraEnabled public String comment; @AuraEnabled public String verified;
        @AuraEnabled public Boolean waiting = false;
    }
    public class Trail {
        @AuraEnabled public String name;
        @AuraEnabled public List<Entry> entries = new List<Entry>();
        @AuraEnabled public List<Sign> signatures = new List<Sign>();
        @AuraEnabled public String signLine;     // e.g. 2 of 3 committee seats signed, 1 waiting
    }

    @AuraEnabled
    public static Trail get(Id recordId) {
        if (recordId != null && recordId.getSObjectType() == Field_Action__c.SObjectType) { return fieldAction(recordId); }
        if (recordId == null || recordId.getSObjectType() != Field_Action_Review__c.SObjectType) {
            throw new AuraHandledException('The audit trail is not available for this record yet.');
        }
        Field_Action_Review__c r;
        try {
            r = [SELECT Id, Name, Status__c, Committee_Approval__c, Emergency__c, Emergency_Reason__c, Recommended_By__r.Name, Recommended_On__c
                 FROM Field_Action_Review__c WHERE Id = :recordId WITH USER_MODE];
        } catch (QueryException e) {
            throw new AuraHandledException('You do not have access to this record.');
        }
        Trail t = new Trail();
        t.name = r.Name;
        t.entries = entries(recordId);
        signatures(t, r);
        return t;
    }

    /**
     * A Field Action's trail: every scope change, newest first. Each lot added or removed, by whom (or Automatic, when a
     * Full scope widened itself), and the reason given. The Scope step no longer lists these itself.
     */
    private static Trail fieldAction(Id recordId) {
        Field_Action__c fa;
        try {
            fa = [SELECT Id, Name, Status__c, Closed_By__r.Name, Closed_On__c, Closure_Summary__c FROM Field_Action__c WHERE Id = :recordId WITH USER_MODE];
        } catch (QueryException e) {
            throw new AuraHandledException('You do not have access to this record.');
        }
        Trail t = new Trail();
        t.name = fa.Name;
        for (Field_Action_Scope_Change__c c : [SELECT Id, Lot_Number__c, Change__c, How__c, Reason__c, CreatedBy.Name, CreatedDate
                                               FROM Field_Action_Scope_Change__c WHERE Field_Action__c = :recordId WITH USER_MODE
                                               ORDER BY CreatedDate DESC, Name DESC LIMIT 1000]) {
            Boolean removed = c.Change__c == 'Removed';
            Entry x = new Entry();
            x.id = c.Id; x.at = c.CreatedDate; x.kind = 'scope';
            x.who = c.How__c == 'Automatic' ? 'Automatic' : c.CreatedBy.Name;
            x.title = (removed ? 'Removed Lot ' : 'Added Lot ') + c.Lot_Number__c + (removed ? ' From Scope' : ' to Scope');
            List<String> bits = new List<String>();
            if (c.How__c == 'Review') { bits.add('With the review decision'); }
            if (String.isNotBlank(c.Reason__c)) { bits.add(c.Reason__c); }
            x.detail = bits.isEmpty() ? null : String.join(bits, ': ');
            t.entries.add(x);
        }
        // closing it, and the signatures: each in the timeline, and the signatures again in their own list
        if (fa.Closed_On__c != null) {
            Entry x = new Entry();
            x.id = fa.Id + '-closed'; x.at = fa.Closed_On__c; x.kind = 'decision'; x.who = fa.Closed_By__r?.Name;
            x.title = 'Closed the Field Action'; x.detail = cut(fa.Closure_Summary__c, 600);
            t.entries.add(x);
        }
        for (Field_Action_Record_Activity__c a : new Reader().faSignaturesOf(recordId)) {
            Sign s = new Sign();
            s.key = a.Id; s.at = a.CreatedDate; s.who = a.CreatedBy.Name; s.seat = 'Recall Coordinator';
            s.meaning = String.isNotBlank(a.Purpose_Of_Signature__c) ? a.Purpose_Of_Signature__c : 'Close Field Action';
            s.comment = String.isNotBlank(a.Comment_Long__c) ? a.Comment_Long__c : a.Comment__c;
            s.verified = a.Verified_By__c == CqEsigBridge.PASSWORD ? 'Password checked'
                : a.Verified_By__c == CqEsigBridge.PASSWORD + CqFaSignable.DEMO ? 'Password checked · signed in Demo Mode'
                : String.isBlank(a.Verified_By__c) ? 'Recorded by CQ' : a.Verified_By__c;
            t.signatures.add(s);
            Entry x = new Entry();
            x.id = a.Id; x.at = a.CreatedDate; x.kind = 'signature'; x.who = a.CreatedBy.Name;
            x.title = 'Signed: ' + s.meaning + (a.Verified_By__c == CqEsigBridge.PASSWORD + CqFaSignable.DEMO ? ' (Demo Mode)' : ''); x.detail = s.comment;
            t.entries.add(x);
        }
        t.entries.sort();
        t.signLine = t.signatures.isEmpty() ? (fa.Status__c == 'Closed' ? 'Closed without a signature' : 'Waiting for the recall coordinator')
            : t.signatures.size() == 1 ? '1 signature' : t.signatures.size() + ' signatures';
        return t;
    }

    private static String person(String changedBy) {
        if (String.isBlank(changedBy)) { return 'Unknown'; }
        Integer p = changedBy.lastIndexOf(' (');
        return p > 0 ? changedBy.left(p) : changedBy;
    }
    private static String cut(String s, Integer n) { return s == null ? null : s.abbreviate(n); }

    private static List<Entry> entries(Id recordId) {
        List<Field_Action_Review_Audit__c> rows = new Reader().rowsOf(String.valueOf(recordId));
        Map<String, String> named = names(rows);
        // the decisions on each suggestion, newest first (rows are newest first)
        Map<Id, Field_Action_Review_Audit__c> lastDecision = new Map<Id, Field_Action_Review_Audit__c>();
        Map<Id, Field_Action_Review_Audit__c> byId = new Map<Id, Field_Action_Review_Audit__c>(rows);
        Set<String> newerSuggestion = new Set<String>();     // keys whose latest suggestion has been seen (walking newest first)
        Set<Id> replaced = new Set<Id>();
        for (Field_Action_Review_Audit__c e : rows) {
            if (e.Suggestion__c != null && !lastDecision.containsKey(e.Suggestion__c)) { lastDecision.put(e.Suggestion__c, e); }
            if (e.Action__c == CqFarSuggestions.SUGGESTED) {
                if (newerSuggestion.contains(e.Suggestion_Key__c)) { replaced.add(e.Id); } else { newerSuggestion.add(e.Suggestion_Key__c); }
            }
        }

        List<Entry> out = new List<Entry>();
        for (Field_Action_Review_Audit__c e : rows) {
            Entry x = new Entry();
            x.id = e.Id; x.at = e.CreatedDate; x.who = person(e.Changed_By__c);
            if (e.Action__c == CqFarSuggestions.SUGGESTED) {
                x.kind = 'suggestion'; x.cq = true; x.who = 'CQ';
                x.title = 'Suggested ' + e.Suggestion_Key__c + ': ' + e.New_Value__c;
                if (String.isNotBlank(e.Facts__c)) { x.facts = e.Facts__c.split('\n'); }
                if (String.isNotBlank(e.Sources__c)) {
                    try { x.sources = (List<Src>) JSON.deserialize(e.Sources__c, List<Src>.class); } catch (Exception ex) { x.sources = new List<Src>(); }
                }
                Field_Action_Review_Audit__c d = lastDecision.get(e.Id);
                if (d != null) {
                    x.result = d.Action__c == CqFarSuggestions.CHANGED ? 'Changed' : 'Accepted';
                    x.changed = d.Action__c == CqFarSuggestions.CHANGED;
                    x.resultBy = person(d.Changed_By__c);
                } else {
                    x.result = replaced.contains(e.Id) ? 'Replaced' : 'Not Answered Yet';
                }
            } else if (e.Action__c == CqFarSuggestions.ACCEPTED || e.Action__c == CqFarSuggestions.CHANGED) {
                x.kind = 'decision';
                x.changed = e.Action__c == CqFarSuggestions.CHANGED;
                x.title = (x.changed ? 'Changed CQ.AI Suggestion: ' : 'Accepted CQ.AI Suggestion: ') + e.Suggestion_Key__c;
                x.cqValue = e.Old_Value__c; x.personValue = e.New_Value__c;
                x.detail = x.changed ? null : e.New_Value__c;
                x.reason = e.Reason__c;
                if (x.changed && String.isBlank(x.reason)) { x.reason = 'No reason recorded: submitted from the earlier Field Action Workspace.'; }
                Field_Action_Review_Audit__c s = e.Suggestion__c == null ? null : byId.get(e.Suggestion__c);
                if (s != null) { x.suggestionId = s.Id; x.suggestionAt = s.CreatedDate; }
            } else if (e.Action__c == CqFarAudit.SIGNED) {
                x.kind = 'signature';
                x.title = 'Signed';
                x.detail = 'Signature meaning: ' + e.New_Value__c;
            } else if (e.Action__c == CqFarAudit.CREATED) {
                x.kind = 'create'; x.title = 'Created ' + e.Record_Name__c;
            } else if (e.Action__c == CqFarAudit.DELETED) {
                x.kind = 'delete'; x.title = 'Deleted ' + e.Record_Name__c;
            } else {
                x.kind = 'edit';
                x.title = 'Edited ' + (e.Field_Label__c == null ? e.Field_Name__c : e.Field_Label__c);
                x.detail = 'Old: ' + (String.isBlank(e.Old_Value__c) ? '(blank)' : cut(shown(e.Old_Value__c, named), 300))
                    + ' · New: ' + (String.isBlank(e.New_Value__c) ? '(blank)' : cut(shown(e.New_Value__c, named), 300));
            }
            out.add(x);
        }
        return out;
    }

    // ---- lookups: an edit of a lookup field records the record id; the trail shows that record's name ----

    private static Id asId(String v) {
        if (String.isBlank(v) || (v.length() != 15 && v.length() != 18)) { return null; }
        try { return Id.valueOf(v); } catch (Exception e) { return null; }
    }
    private static String shown(String v, Map<String, String> named) {
        Id i = asId(v);
        return (i != null && named.containsKey(String.valueOf(i))) ? named.get(String.valueOf(i)) : v;
    }
    private static String nameFieldOf(Schema.SObjectType t) {
        for (Schema.SObjectField f : t.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult d = f.getDescribe();
            if (d.isNameField()) { return d.getName(); }
        }
        return null;
    }

    /**
     * The names of the records that lookup edits point to, by id. Read as the person (user mode): a record they cannot
     * see keeps showing its id. The entry itself still holds the id, which never changes, so the record stays traceable.
     */
    private static Map<String, String> names(List<Field_Action_Review_Audit__c> rows) {
        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Field_Action_Review__c.fields.getMap();
        Map<Schema.SObjectType, Set<Id>> byType = new Map<Schema.SObjectType, Set<Id>>();
        for (Field_Action_Review_Audit__c e : rows) {
            if (e.Action__c != CqFarAudit.EDITED || String.isBlank(e.Field_Name__c)) { continue; }
            Schema.SObjectField f = fieldMap.get(e.Field_Name__c.toLowerCase());
            if (f == null || f.getDescribe().getType() != Schema.DisplayType.REFERENCE) { continue; }
            for (String v : new List<String>{ e.Old_Value__c, e.New_Value__c }) {
                Id i = asId(v);
                if (i == null) { continue; }
                Schema.SObjectType t = i.getSObjectType();
                if (!byType.containsKey(t)) { byType.put(t, new Set<Id>()); }
                byType.get(t).add(i);
            }
        }
        Map<String, String> out = new Map<String, String>();
        for (Schema.SObjectType t : byType.keySet()) {
            try {
                String nameField = nameFieldOf(t);
                if (nameField == null) { continue; }
                Set<Id> ids = byType.get(t);
                String q = 'SELECT Id, ' + nameField + ' FROM ' + t.getDescribe().getName() + ' WHERE Id IN :ids';
                for (SObject r : Database.query(q, AccessLevel.USER_MODE)) {
                    Object n = r.get(nameField);
                    if (n != null) { out.put(String.valueOf(r.Id), String.valueOf(n)); }
                }
            } catch (Exception ex) { /* not readable: the id shows */ }
        }
        return out;
    }

    /** Every signature on the review, with its committee seat, and the seats still waiting on an open approval. */
    private static void signatures(Trail t, Field_Action_Review__c r) {
        // only the approval and its steps: the seat lists a coordinator chooses from (every active user) are not needed here
        CqFarCommittee.Info c;
        try {
            c = new CqFarCommittee.Info();
            if (r.Committee_Approval__c != null) { CqFarCommittee.loadApproval(c, r.Committee_Approval__c, false); }
        } catch (Exception e) { c = null; }
        Map<String, String> seatOf = new Map<String, String>();
        if (c != null) { for (CqFarCommittee.Step s : c.steps) { if (s.person != null) { seatOf.put(s.person, s.seat); } } }

        for (Field_Action_Review_Record_Activity__c a : new Reader().signaturesOf(r.Id)) {
            Sign s = new Sign();
            s.key = a.Id; s.at = a.CreatedDate; s.who = a.CreatedBy.Name; s.seat = seatOf.get(a.CreatedBy.Name);
            s.meaning = String.isNotBlank(a.Purpose_Of_Signature__c) ? a.Purpose_Of_Signature__c : a.Activity_Code__c;
            s.comment = String.isNotBlank(a.Comment_Long__c) ? a.Comment_Long__c : a.Comment__c;
            s.verified = a.Verified_By__c == CqEsigBridge.PASSWORD ? 'Password checked' : String.isBlank(a.Verified_By__c) ? 'Recorded by CQ' : a.Verified_By__c;
            t.signatures.add(s);
        }
        Integer seats = 0; Integer waiting = 0;
        if (c != null && r.Status__c == 'With Committee') {
            for (CqFarCommittee.Step s : c.steps) {
                seats++;
                if (s.status == 'Approved' || s.status == 'Rejected') { continue; }
                waiting++;
                Sign w = new Sign();
                w.key = s.id; w.who = s.person; w.seat = s.seat; w.meaning = 'Waiting'; w.waiting = true;
                t.signatures.add(w);
            }
            t.signLine = (seats - waiting) + ' of ' + seats + ' committee seats signed' + (waiting > 0 ? ' · ' + waiting + ' waiting' : '');
        } else {
            t.signLine = t.signatures.size() == 1 ? '1 signature' : t.signatures.size() + ' signatures';
        }
    }

    /** The entries and signature rows, read in system mode as they are written: the person's access is checked on the record. */
    private without sharing class Reader {
        List<Field_Action_Review_Audit__c> rowsOf(String recordId) {
            return [SELECT Id, Name, CreatedDate, Action__c, Changed_By__c, Field_Name__c, Field_Label__c, Old_Value__c, New_Value__c,
                           Record_Name__c, Suggestion_Key__c, Suggestion__c, Facts__c, Sources__c, Reason__c, Signature__c
                    FROM Field_Action_Review_Audit__c WHERE Record_Id__c = :recordId ORDER BY CreatedDate DESC, Name DESC LIMIT 1000];
        }
        List<Field_Action_Record_Activity__c> faSignaturesOf(Id recordId) {
            return [SELECT Id, CreatedDate, CreatedBy.Name, Activity_Code__c, Purpose_Of_Signature__c, Comment__c, Comment_Long__c, Verified_By__c
                    FROM Field_Action_Record_Activity__c WHERE Field_Action__c = :recordId ORDER BY CreatedDate DESC LIMIT 200];
        }
        List<Field_Action_Review_Record_Activity__c> signaturesOf(Id recordId) {
            return [SELECT Id, CreatedDate, CreatedBy.Name, Activity_Code__c, Purpose_Of_Signature__c, Comment__c, Comment_Long__c, Verified_By__c
                    FROM Field_Action_Review_Record_Activity__c
                    WHERE Field_Action_Review__c = :recordId AND (Type_of_Activity__c = 'E-Signature' OR Purpose_Of_Signature__c != null)
                    ORDER BY CreatedDate DESC LIMIT 200];
        }
    }
}

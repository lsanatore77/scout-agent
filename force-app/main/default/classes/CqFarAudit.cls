/**
 * CqFarAudit: the audit trail for Field Action Reviews (Field_Action_Review_Audit__c), and the locks that keep it and
 * the signatures (Field_Action_Review_Record_Activity__c) unchanged once written.
 *
 * Every create, field change and delete of a review writes one entry per field changed: the field, old and new values,
 * who and when, and the request id that ties together changes saved at once. A signature writes a Signature entry that
 * points to the signature row, so the audit trail is the one complete timeline and the signatures stay a clean list.
 *
 * Entries are written in system mode (without sharing, no user permission needed): people can read the trail but never
 * create, edit or delete entries themselves. Entries keep the review's id and number as text, so they outlive the review.
 *
 * Not logged: system fields that change on every save, formula fields, and Review_Draft__c, which is the workspace's
 * autosave of work in progress (written on every step change) rather than a value of the record.
 */
public without sharing class CqFarAudit {
    public static final String CREATED = 'Create';
    public static final String EDITED = 'Edit';
    public static final String DELETED = 'Delete';
    public static final String SIGNED = 'Signature';

    private static final Set<String> SKIP = new Set<String>{
        'id', 'isdeleted', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp',
        'lastvieweddate', 'lastreferenceddate', 'lastactivitydate', 'review_draft__c'
    };
    private static final Integer MAX = 32768;

    /** Edits are recorded; also true for tests that only check other things. */
    @TestVisible private static Boolean enabled = true;

    private static Map<String, Schema.DescribeFieldResult> fields {
        get {
            if (fields == null) {
                fields = new Map<String, Schema.DescribeFieldResult>();
                for (Schema.SObjectField f : Schema.SObjectType.Field_Action_Review__c.fields.getMap().values()) {
                    Schema.DescribeFieldResult d = f.getDescribe();
                    if (SKIP.contains(d.getName().toLowerCase()) || d.isCalculated()) { continue; }
                    fields.put(d.getName(), d);
                }
            }
            return fields;
        }
        set;
    }

    /** The person, as the trail records them: name and username. */
    public static String who() { return UserInfo.getName() + ' (' + UserInfo.getUserName() + ')'; }
    public static String request() {
        try { return Request.getCurrent().getRequestId(); } catch (Exception e) { return null; }
    }
    private static String text(Object v) {
        if (v == null) { return null; }
        String s = v instanceof Datetime ? ((Datetime) v).formatGmt('yyyy-MM-dd HH:mm:ss') + ' GMT' : String.valueOf(v);
        return s.left(MAX);
    }
    private static Field_Action_Review_Audit__c entry(SObject r, String action) {
        return new Field_Action_Review_Audit__c(
            Field_Action_Review__c = action == DELETED ? null : (Id) r.get('Id'),
            Record_Id__c = (String) String.valueOf(r.get('Id')), Record_Name__c = (String) r.get('Name'),
            Action__c = action, Changed_By__c = who().left(255), Request_Id__c = request());
    }

    /** After insert, update or delete of reviews: one entry per changed field, or one entry for a create or delete. */
    public static void log(List<SObject> rows, Map<Id, SObject> before, String action) {
        if (!enabled) { return; }
        List<Field_Action_Review_Audit__c> out = new List<Field_Action_Review_Audit__c>();
        for (SObject r : rows) {
            if (action != EDITED) {
                Field_Action_Review_Audit__c e = entry(r, action);
                if (action == DELETED) { e.Old_Value__c = text(r.get('Name')); }
                out.add(e);
                continue;
            }
            SObject old = before.get((Id) r.get('Id'));
            for (Schema.DescribeFieldResult d : fields.values()) {
                Object a = old.get(d.getName()), b = r.get(d.getName());
                if (a == b || (a != null && a.equals(b))) { continue; }
                Field_Action_Review_Audit__c e = entry(r, EDITED);
                e.Field_Name__c = d.getName(); e.Field_Label__c = d.getLabel().left(255);
                e.Old_Value__c = text(a); e.New_Value__c = text(b);
                out.add(e);
            }
        }
        if (!out.isEmpty()) { insert out; }
    }

    /** A signature row was written: the trail records it and points to it. */
    public static void signed(Field_Action_Review_Record_Activity__c s, String reviewName) {
        if (!enabled) { return; }
        insert new Field_Action_Review_Audit__c(
            Field_Action_Review__c = s.Field_Action_Review__c, Record_Id__c = String.valueOf(s.Field_Action_Review__c),
            Record_Name__c = reviewName, Action__c = SIGNED, Signature__c = s.Id,
            New_Value__c = (s.Purpose_Of_Signature__c == null ? s.Activity_Code__c : s.Purpose_Of_Signature__c)
                + (String.isBlank(s.Verified_By__c) ? '' : ' · verified by ' + s.Verified_By__c),
            Changed_By__c = who().left(255), Request_Id__c = request());
    }

    /** Writes entries made elsewhere (CQ.AI Suggestions and the decisions on them, see CqFarSuggestions), in system mode. */
    public static void write(List<Field_Action_Review_Audit__c> rows) {
        if (!enabled || rows == null || rows.isEmpty()) { return; }
        insert rows;
    }

    /** Before delete of reviews: a review with signatures stays. Deleting it would delete its signatures with it. */
    public static void keepSigned(List<SObject> rows) {
        Set<Id> ids = new Map<Id, SObject>(rows).keySet();
        Set<Id> signed = new Set<Id>();
        for (Field_Action_Review_Record_Activity__c s : [
                SELECT Field_Action_Review__c FROM Field_Action_Review_Record_Activity__c WHERE Field_Action_Review__c IN :ids]) {
            signed.add(s.Field_Action_Review__c);
        }
        for (SObject r : rows) {
            if (signed.contains((Id) r.get('Id'))) {
                r.addError('This review has electronic signatures, so it cannot be deleted.');
            }
        }
    }

    /** Before update or delete of an audit entry or a signature: never allowed, for anyone. */
    public static void refuseChange(List<SObject> rows, String what) {
        for (SObject r : rows) { r.addError(what + ' cannot be changed or deleted.'); }
    }
}

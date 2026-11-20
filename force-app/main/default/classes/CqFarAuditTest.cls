@IsTest
private class CqFarAuditTest {
    private static List<Field_Action_Review_Audit__c> trail(Id reviewId) {
        return [SELECT Action__c, Field_Name__c, Field_Label__c, Old_Value__c, New_Value__c, Changed_By__c, Record_Id__c, Record_Name__c,
                       Field_Action_Review__c, Request_Id__c
                FROM Field_Action_Review_Audit__c WHERE Record_Id__c = :String.valueOf(reviewId) ORDER BY Name];
    }

    @IsTest
    static void createThenEachChangedField() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        List<Field_Action_Review_Audit__c> t = trail(r.Id);
        System.assertEquals(1, t.size());
        System.assertEquals(CqFarAudit.CREATED, t[0].Action__c);
        System.assert(t[0].Changed_By__c.contains(UserInfo.getUserName()));

        update new Field_Action_Review__c(Id = r.Id, Title__c = 'Audit, renamed', Outcome_Rationale__c = 'Because');
        t = trail(r.Id);
        System.assertEquals(3, t.size(), 'one entry per changed field');
        Map<String, Field_Action_Review_Audit__c> byField = new Map<String, Field_Action_Review_Audit__c>();
        for (Field_Action_Review_Audit__c e : t) { if (e.Action__c == CqFarAudit.EDITED) { byField.put(e.Field_Name__c, e); } }
        System.assertEquals('Audit', byField.get('Title__c').Old_Value__c);
        System.assertEquals('Audit, renamed', byField.get('Title__c').New_Value__c);
        System.assertEquals(null, byField.get('Outcome_Rationale__c').Old_Value__c);
        System.assertEquals(byField.get('Title__c').Request_Id__c, byField.get('Outcome_Rationale__c').Request_Id__c, 'saved together');
    }

    @IsTest
    static void draftAutosaveIsNotLogged() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        update new Field_Action_Review__c(Id = r.Id, Review_Draft__c = '{"step":1}');
        System.assertEquals(1, trail(r.Id).size(), 'only the create');
    }

    @IsTest
    static void deleteIsLoggedAndTheTrailOutlivesTheReview() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        delete r;
        List<Field_Action_Review_Audit__c> t = trail(r.Id);
        System.assertEquals(2, t.size());
        System.assertEquals(CqFarAudit.DELETED, t[1].Action__c);
        System.assertEquals(null, t[0].Field_Action_Review__c, 'the link is cleared, the id and number stay');
        System.assertNotEquals(null, t[0].Record_Name__c);
    }

    @IsTest
    static void signedReviewCannotBeDeleted() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        insert new Field_Action_Review_Record_Activity__c(Field_Action_Review__c = r.Id, Activity_Code__c = 'approve');
        Boolean refused = false;
        try { delete r; } catch (DmlException e) { refused = e.getMessage().contains('electronic signatures'); }
        System.assert(refused, 'a review with signatures stays');
        System.assertEquals(1, [SELECT COUNT() FROM Field_Action_Review__c WHERE Id = :r.Id]);
    }

    @IsTest
    static void entriesAndSignaturesAreLocked() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        Field_Action_Review_Record_Activity__c s = new Field_Action_Review_Record_Activity__c(Field_Action_Review__c = r.Id, Activity_Code__c = 'approve');
        insert s;
        CqFarAudit.signed(s, 'FAR-TEST');
        Field_Action_Review_Audit__c e = [SELECT Id, Action__c, Signature__c FROM Field_Action_Review_Audit__c WHERE Action__c = :CqFarAudit.SIGNED];
        System.assertEquals(s.Id, e.Signature__c);

        Integer refused = 0;
        try { update new Field_Action_Review_Audit__c(Id = e.Id, New_Value__c = 'x'); } catch (DmlException x) { refused++; }
        try { delete e; } catch (DmlException x) { refused++; }
        try { update new Field_Action_Review_Record_Activity__c(Id = s.Id, Comment__c = 'x'); } catch (DmlException x) { refused++; }
        try { delete s; } catch (DmlException x) { refused++; }
        System.assertEquals(4, refused, 'no edit or delete of an audit entry or a signature');
    }

    @IsTest
    static void switchedOffForOtherTests() {
        CqFarAudit.enabled = false;
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Audit');
        insert r;
        System.assertEquals(0, trail(r.Id).size());
    }
}

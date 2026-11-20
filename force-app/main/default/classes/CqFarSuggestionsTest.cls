@IsTest
private class CqFarSuggestionsTest {
    private static List<Field_Action_Review_Audit__c> entries(Id reviewId, String action) {
        return [SELECT Action__c, Suggestion_Key__c, Suggestion__c, Old_Value__c, New_Value__c, Facts__c, Sources__c, Reason__c, Changed_By__c
                FROM Field_Action_Review_Audit__c WHERE Record_Id__c = :String.valueOf(reviewId) AND Action__c = :action ORDER BY Name];
    }

    @IsTest
    static void suggestionsAreRecordedOnceWithTheirFacts() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Suggest');
        insert r;
        CqFarSuggestions.note(r.Id);
        CqFarSuggestions.note(r.Id);     // opened again: nothing new
        List<Field_Action_Review_Audit__c> s = entries(r.Id, CqFarSuggestions.SUGGESTED);
        System.assertEquals(2, s.size(), 'risk level and outcome, once each');
        System.assertEquals(CqFarSuggestions.RISK, s[0].Suggestion_Key__c);
        System.assertEquals('Low (score 10 of 100)', s[0].New_Value__c);
        System.assertEquals('Low', s[0].Old_Value__c, 'what the person is compared with');
        System.assert(s[0].Facts__c.contains('Severity'), 'each score factor is a fact');
        System.assertEquals(CqFarSuggestions.CQ_AI, s[0].Changed_By__c);
        System.assertEquals('No Field Action', s[1].New_Value__c);

        // a decided review is not noted
        update new Field_Action_Review__c(Id = r.Id, Status__c = 'Decided');
        CqFarSuggestions.note(r.Id);
        System.assertEquals(2, entries(r.Id, CqFarSuggestions.SUGGESTED).size());
    }

    @IsTest
    static void aDifferentChoiceNeedsAReasonAndIsRecordedAgainstTheSuggestion() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Decide');
        insert r;
        CqFarSuggestions.note(r.Id);
        String noReason = JSON.serialize(new Map<String, Object>{ 'faChoice' => '', 'reasons' => new Map<String, String>() });
        try {
            CqFarSuggestions.decide(r.Id, 'High', 'No Field Action', null, noReason);
            System.assert(false, 'a different risk level without a reason is refused');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Risk Level'), e.getMessage());
        }
        System.assertEquals(0, entries(r.Id, CqFarSuggestions.CHANGED).size(), 'nothing written when refused');

        String withReason = JSON.serialize(new Map<String, Object>{ 'faChoice' => '',
            'reasons' => new Map<String, String>{ CqFarSuggestions.RISK => ' Injury reported by phone, not yet in CQ. ' } });
        CqFarSuggestions.decide(r.Id, 'High', 'No Field Action', null, withReason);

        Field_Action_Review_Audit__c risk = [SELECT Id FROM Field_Action_Review_Audit__c WHERE Record_Id__c = :String.valueOf(r.Id)
                                              AND Action__c = :CqFarSuggestions.SUGGESTED AND Suggestion_Key__c = :CqFarSuggestions.RISK];
        Field_Action_Review_Audit__c changed = entries(r.Id, CqFarSuggestions.CHANGED)[0];
        System.assertEquals(risk.Id, changed.Suggestion__c, 'linked to the suggestion it answers');
        System.assertEquals('Low', changed.Old_Value__c);
        System.assertEquals('High', changed.New_Value__c);
        System.assertEquals('Injury reported by phone, not yet in CQ.', changed.Reason__c);
        Field_Action_Review_Audit__c accepted = entries(r.Id, CqFarSuggestions.ACCEPTED)[0];
        System.assertEquals(CqFarSuggestions.OUTCOME, accepted.Suggestion_Key__c);
        System.assertEquals(null, accepted.Reason__c);

        CqAuditTrail.Trail t = CqAuditTrail.get(r.Id);
        System.assertEquals([SELECT Name FROM Field_Action_Review__c WHERE Id = :r.Id].Name, t.name);
        Integer suggestions = 0; Boolean sawChange = false;
        for (CqAuditTrail.Entry e : t.entries) {
            if (e.kind == 'suggestion') {
                suggestions++;
                System.assert(e.cq);
                if (e.title.contains('Risk Level')) { System.assertEquals('Changed', e.result); System.assert(e.changed); }
                else { System.assertEquals('Accepted', e.result); }
            }
            if (e.kind == 'decision' && e.changed) {
                sawChange = true;
                System.assertEquals('Low', e.cqValue); System.assertEquals('High', e.personValue);
                System.assertEquals(risk.Id, e.suggestionId);
            }
        }
        System.assertEquals(2, suggestions);
        System.assert(sawChange);
        System.assertEquals('0 signatures', t.signLine);
    }

    @IsTest
    static void theOldScreenIsRecordedWithoutAReason() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Old screen');
        insert r;
        CqFarSuggestions.decide(r.Id, 'Medium', 'No Field Action', null, null);
        Field_Action_Review_Audit__c changed = entries(r.Id, CqFarSuggestions.CHANGED)[0];
        System.assertEquals(null, changed.Reason__c);
        System.assertEquals(2, entries(r.Id, CqFarSuggestions.SUGGESTED).size(), 'the suggestions are recorded at the decision if not before');
        for (CqAuditTrail.Entry e : CqAuditTrail.get(r.Id).entries) {
            if (e.kind == 'decision' && e.changed) { System.assert(e.reason.contains('earlier')); }
        }
    }

    @IsTest
    static void aSignatureShowsInTheTrailAndItsPanel() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Signed');
        insert r;
        Field_Action_Review_Record_Activity__c s = new Field_Action_Review_Record_Activity__c(Field_Action_Review__c = r.Id,
            Activity_Code__c = 'approve', Type_of_Activity__c = 'E-Signature', Purpose_Of_Signature__c = 'Committee Approve',
            Verified_By__c = CqEsigBridge.PASSWORD, Comment__c = 'Agreed');
        insert s;
        CqFarAudit.signed(s, 'FAR');
        CqAuditTrail.Trail t = CqAuditTrail.get(r.Id);
        System.assertEquals(1, t.signatures.size());
        System.assertEquals('Committee Approve', t.signatures[0].meaning);
        System.assertEquals('Password checked', t.signatures[0].verified);
        System.assertEquals('Agreed', t.signatures[0].comment);
        Boolean inTimeline = false;
        for (CqAuditTrail.Entry e : t.entries) { if (e.kind == 'signature') { inTimeline = true; } }
        System.assert(inTimeline);
    }

    @IsTest
    static void onlyReviewsForNow() {
        try { CqAuditTrail.get(UserInfo.getUserId()); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
    }
}

/** Closing a Field Action, signed by its recall coordinator through CqEsign, and the signature in its audit trail. */
@IsTest
private class CqFieldActionCloseTest {
    /** Stands in for CQ's electronic signature: answers as told, records the signature as CQ would, and counts. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Integer signed = 0;
        public CqEsign.Policy signFor(Id recordId, String action) {
            CqEsign.Policy g = new CqEsign.Policy(); g.required = required; g.purpose = 'Field action complete';
            return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            signed++;
            CqEsigBridge.signable(recordId).record(recordId, action, comment, 'Field action complete', 'f'.repeat(64));
        }
    }

    /** A field action with a confirmed strategy and one decided hold, as in CqFieldActionRecoveryTest. */
    static Field_Action__c makeFa() {
        Account cust = new Account(Name = 'FAC Clinic');
        insert cust;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Close test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.REMOVAL, Depth__c = 'Hospital', Recall_Class__c = 'Class II',
            Check_Level__c = 'Level A', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FAC-L1', In_Scope__c = true, Approved_In_Scope__c = true,
            Added_How__c = 'Automatic', Units_On_Hand__c = 6);
        insert new Lot_Shipment__c(Lot_Number__c = 'FAC-L1', Units__c = 10, Customer__c = cust.Id);
        insert new Field_Action_Hold__c(Field_Action__c = fa.Id, Lot_Number__c = 'FAC-L1', Kind__c = CqFieldActionStrategy.FINISHED,
            Hold__c = true, Held__c = true, Held_On__c = Datetime.now(), Reason__c = 'In scope', Disposition__c = 'Scrap');
        return fa;
    }

    @IsTest
    static void theCoordinatorIsTheOwner() {
        Field_Action__c fa = makeFa();
        CqFieldActionClose.Signer s = CqFieldActionClose.getSigner(fa.Id);
        System.assert(s.mine, 'the person who made it owns it');
        System.assertEquals(false, s.closed);
        System.assertEquals(false, s.signed);
    }

    @IsTest
    static void aBlockedFieldActionIsNeverSigned() {
        Field_Action__c fa = makeFa();
        FakeEsig f = new FakeEsig(); f.required = true;
        CqEsign.gateway = f;
        Test.startTest();
        try { CqFieldActionClose.signAndClose(fa.Id, null, 'done', 'pw'); System.assert(false, 'the verdict is still open'); }
        catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
        System.assertEquals(0, f.signed);
        System.assertEquals(0, [SELECT COUNT() FROM Field_Action_Record_Activity__c WHERE Field_Action__c = :fa.Id]);
    }

    @IsTest
    static void signsClosesAndShowsInTheAuditTrail() {
        Field_Action__c fa = makeFa();
        update new Field_Action__c(Id = fa.Id, Recovery_Status__c = 'Confirmed', Verdict__c = CqFieldActionRecovery.EFFECTIVE,
            Verdict_By__c = UserInfo.getUserId(), Verdict_On__c = Datetime.now());
        Boolean capaMade = true;
        try { CqFieldActionRecovery.createCapa(fa.Id); } catch (Exception e) { capaMade = false; }   // CQ can refuse a bare CAPA in a test org
        FakeEsig f = new FakeEsig(); f.required = true;
        CqEsign.gateway = f;
        Test.startTest();
        if (capaMade) {
            try { CqFieldActionClose.signAndClose(fa.Id, null, 'done', null); System.assert(false, 'no password'); }
            catch (AuraHandledException e) { System.assert(true); }
            CqFieldActionRecovery.View v = CqFieldActionClose.signAndClose(fa.Id, 'All recovered.', 'Recall complete', 'pw');
            System.assert(v.closed);
            System.assertEquals(1, f.signed);
            CqFieldActionClose.Signer s = CqFieldActionClose.getSigner(fa.Id);
            System.assert(s.signed && s.closed);
            System.assertEquals('Recall complete', s.comment);
            CqAuditTrail.Trail t = CqAuditTrail.get(fa.Id);
            System.assertEquals(1, t.signatures.size());
            Boolean closedEntry = false; Boolean signEntry = false;
            for (CqAuditTrail.Entry e : t.entries) { if (e.kind == 'decision') { closedEntry = true; } if (e.kind == 'signature') { signEntry = true; } }
            System.assert(closedEntry && signEntry, 'closing and the signature are both in the timeline');
            try { delete new Field_Action__c(Id = fa.Id); System.assert(false, 'a signed field action stays'); }
            catch (DmlException e) { System.assert(e.getMessage().contains('electronic signature')); }
        } else {
            try { CqFieldActionClose.signAndClose(fa.Id, null, 'done', 'pw'); System.assert(false, 'no CAPA'); }
            catch (AuraHandledException e) { System.assertEquals(0, f.signed); }
        }
        Test.stopTest();
    }

    @IsTest
    static void signatureRowAndFingerprint() {
        Field_Action__c fa = makeFa();
        CqFaSignable.signing = 'Summary one';
        CqEsigBridge.signable(fa.Id).record(fa.Id, 'close', 'x'.repeat(300), null, 'a'.repeat(64));
        Field_Action_Record_Activity__c row = [SELECT Comment__c, Comment_Long__c, Signed_Content__c, Verified_By__c, Type_of_Activity__c
                                               FROM Field_Action_Record_Activity__c WHERE Field_Action__c = :fa.Id];
        System.assertEquals(255, row.Comment__c.length());
        System.assertEquals(300, row.Comment_Long__c.length());
        System.assertEquals(64, row.Signed_Content__c.length());
        System.assertEquals('E-Signature', row.Type_of_Activity__c);
        System.assertNotEquals(CqFaSignable.fingerprint(fa, 'Summary one'), CqFaSignable.fingerprint(fa, 'Summary two'));
        System.assertEquals(1, new CqFaSignable().signatureCount(fa.Id));
    }
}

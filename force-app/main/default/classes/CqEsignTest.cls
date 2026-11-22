@IsTest
private class CqEsignTest {
    /** Stands in for CQ's electronic signature: answers as told, and counts signatures. */
    private class FakeEsig implements CqEsigGateway {
        Boolean required = false; Boolean comment = false; Boolean fail = false; Boolean accept = true;
        Integer signed = 0;
        public CqEsign.Policy signFor(Id recordId, String action) {
            if (fail) { throw new CalloutException('no session'); }
            CqEsign.Policy g = new CqEsign.Policy();
            g.required = required; g.comment = comment; g.purpose = 'Close ' + action;
            return g;
        }
        public void sign(Id recordId, String action, String comment, String password) {
            if (!accept) { throw new AuraHandledException('Signature not accepted'); }
            signed++;
        }
    }
    private static String error(Id recordId, String comment, String password, Boolean isSigner) {
        try { CqEsign.sign(recordId, 'approve', comment, password, isSigner); } catch (AuraHandledException e) { return e.getMessage(); }
        return null;
    }

    @IsTest
    static void policiesForEachAction() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Esign');
        insert r;
        FakeEsig f = new FakeEsig(); f.required = true; f.comment = true;
        CqEsign.gateway = f;
        Map<String, CqEsign.Policy> p = CqEsign.getPolicies(r.Id, new List<String>{ 'approve', 'reject' });
        System.assertEquals(2, p.size());
        System.assert(p.get('approve').required && p.get('approve').comment);
        System.assertEquals('Close reject', p.get('reject').purpose);
        f.fail = true;
        System.assert(CqEsign.policyFor(r.Id, 'approve').unknown, 'CQ could not be asked: unknown');
        for (List<String> bad : new List<List<String>>{ null, new List<String>(), new List<String>{ 'a', 'b', 'c', 'd', 'e' } }) {
            try { CqEsign.getPolicies(r.Id, bad); System.assert(false, 'refused'); } catch (AuraHandledException e) { System.assert(true); }
        }
    }

    @IsTest
    static void signsOnlyWhenEverythingIsThere() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Esign');
        insert r;
        FakeEsig f = new FakeEsig(); f.required = true; f.comment = true;
        CqEsign.gateway = f;
        System.assertNotEquals(null, error(r.Id, 'ok', 'pw', false), 'never for someone else');
        System.assertNotEquals(null, error(r.Id, 'ok', null, true), 'no password');
        System.assertNotEquals(null, error(r.Id, ' ', 'pw', true), 'comment required');
        f.accept = false;
        System.assertNotEquals(null, error(r.Id, 'ok', 'pw', true), 'CQ refused');
        f.accept = true; f.fail = true;
        System.assertNotEquals(null, error(r.Id, 'ok', 'pw', true), 'CQ could not be asked');
        System.assertEquals(0, f.signed);
        f.fail = false;
        System.assert(CqEsign.sign(r.Id, 'approve', 'ok', 'pw', true));
        System.assertEquals(1, f.signed);
    }

    @IsTest
    static void noPolicyNoSignature() {
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Esign');
        insert r;
        FakeEsig f = new FakeEsig();
        CqEsign.gateway = f;
        System.assertEquals(false, CqEsign.sign(r.Id, 'approve', null, null, false), 'nothing to sign');
        System.assertEquals(0, f.signed);
    }

    @IsTest
    static void onlyRegisteredObjectsCanBeSigned() {
        try { CqEsigBridge.signable(UserInfo.getUserId()); System.assert(false); } catch (AuraHandledException e) { System.assert(true); }
        Field_Action_Review__c r = new Field_Action_Review__c(Title__c = 'Esign');
        insert r;
        System.assert(CqEsigBridge.signable(r.Id) instanceof CqFarSignable);
        System.assertEquals(0, CqEsigBridge.signable(r.Id).signatureCount(r.Id));
    }
}

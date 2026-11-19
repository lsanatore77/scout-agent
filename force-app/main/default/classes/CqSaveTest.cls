@isTest
private class CqSaveTest {
    @isTest static void saysWhyInPlainWords() {
        System.assertEquals(CqSave.DENIED, CqSave.why(new SecurityException('Access to entity denied')));
        System.assertEquals('plain', CqSave.why(new IllegalArgumentException('plain')));
        try { insert new Account(); System.assert(false, 'an account with no name should not save'); }
        catch (DmlException e) { System.assert(String.isNotBlank(CqSave.why(e))); }
    }
}

/** A lot's Release Status from everything that controls it (CqLotStatus): the strictest wins, a hold lets go, a status set by hand stays, a conflict is flagged. */
@IsTest
private class CqLotStatusTest {

    static compliancequest__SQX_Part__c part() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Lot Status Family');
        insert fam;
        compliancequest__SQX_Part__c p = new compliancequest__SQX_Part__c(
            Name = 'Lot Status Part', cqext__Title__c = 'Lot Status Part', compliancequest__Part_Number__c = 'LST-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert p;
        return p;
    }
    static Field_Action__c fa(Id partId, String title) {
        Field_Action__c f = new Field_Action__c(Title__c = title, Part__c = partId);
        insert f;
        return f;
    }
    static compliancequest__SQX_Lot_Info__c lot(String name) {
        return [SELECT Release_Status__c, Manual_Status__c, Hold_Reason__c, Status_Set_By__c, Status_Conflict__c
                FROM compliancequest__SQX_Lot_Info__c WHERE Name = :name];
    }

    @IsTest
    static void aHoldPutsTheLotOnHoldAndReleaseLetsGo() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-A', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        Field_Action__c f = fa(p.Id, 'Hold test');
        Field_Action_Hold__c h = new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-A', Kind__c = 'Finished Lot',
            Hold__c = true, Held__c = true, Held_On__c = Datetime.now());
        insert h;
        System.assertEquals('On Hold', lot('LST-A').Release_Status__c);
        System.assertEquals('Released', lot('LST-A').Manual_Status__c, 'the hold is not a decision by hand');

        update new Field_Action_Hold__c(Id = h.Id, Disposition__c = 'Release', Disposition_On__c = Datetime.now());
        System.assertEquals('Released', lot('LST-A').Release_Status__c, 'released by the only control on it');
        System.assertEquals(null, lot('LST-A').Hold_Reason__c);
    }

    @IsTest
    static void reworkStaysHeldAndScrapRejects() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-B', compliancequest__Part_Number__c = 'LST-1');
        Field_Action__c f = fa(p.Id, 'Rework test');
        Field_Action_Hold__c h = new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-B', Hold__c = true, Held__c = true,
            Disposition__c = 'Rework', Disposition_On__c = Datetime.now());
        insert h;
        System.assertEquals('On Hold', lot('LST-B').Release_Status__c, 'rework stays held until it is done');
        update new Field_Action_Hold__c(Id = h.Id, Disposition__c = 'Scrap');
        System.assertEquals('Rejected', lot('LST-B').Release_Status__c);
    }

    @IsTest
    static void reworkDoneLetsGo() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-J', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        Field_Action__c f = fa(p.Id, 'Rework done test');
        Field_Action_Hold__c h = new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-J', Hold__c = true, Held__c = true,
            Disposition__c = 'Rework', Disposition_On__c = Datetime.now());
        insert h;
        System.assertEquals('On Hold', lot('LST-J').Release_Status__c);
        update new Field_Action_Hold__c(Id = h.Id, Rework_Done_On__c = Datetime.now(), Rework_Done_By__c = UserInfo.getUserId());
        System.assertEquals('Released', lot('LST-J').Release_Status__c, 'reworked: the field action lets go');
    }

    @IsTest
    static void aFullScopeRecallCoversANewLot() {
        compliancequest__SQX_Part__c p = part();
        insert new Field_Action__c(Title__c = 'Full recall', Part__c = p.Id, Action_Type__c = 'Removal (Recall)', Scope__c = 'Full');
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-K', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        System.assertEquals('Recalled', lot('LST-K').Release_Status__c, 'a full scope covers every lot of the part, a new one too');
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-K2', compliancequest__Part_Number__c = 'LST-OTHER', Release_Status__c = 'Released');
        System.assertEquals('Released', lot('LST-K2').Release_Status__c, 'another part is not covered');
    }

    @IsTest
    static void anExpiredLotIsHeld() {
        insert new List<compliancequest__SQX_Lot_Info__c>{
            new compliancequest__SQX_Lot_Info__c(Name = 'LST-X', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released',
                compliancequest__Expiration_Date__c = Date.today().addDays(-1)),
            new compliancequest__SQX_Lot_Info__c(Name = 'LST-Y', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released',
                compliancequest__Expiration_Date__c = Date.today()) };
        System.assertEquals('Expired', lot('LST-X').Release_Status__c);
        System.assertEquals('Expiry', lot('LST-X').Status_Set_By__c);
        System.assertEquals('Released', lot('LST-Y').Release_Status__c, 'usable through its expiry date');
        System.assertEquals(null, CqLotStatus.expirySay(Date.today(), Date.today()));
        System.assertEquals('Expired', CqLotStatus.expirySay(Date.today(), Date.today().addDays(1)).status, 'the day after, it is expired');
        Test.startTest();
        System.schedule('Lot Expiry test', '0 15 1 * * ?', new CqLotExpiry());
        System.assertEquals(0, CqLotExpiry.run(), 'nothing new to hold');
        Test.stopTest();
    }

    @IsTest
    static void aStatusSetByHandIsNeverLoosened() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-C', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        compliancequest__SQX_Lot_Info__c l = [SELECT Id FROM compliancequest__SQX_Lot_Info__c WHERE Name = 'LST-C'];
        update new compliancequest__SQX_Lot_Info__c(Id = l.Id, Release_Status__c = 'Quarantined');
        Field_Action__c f = fa(p.Id, 'Manual test');
        Field_Action_Hold__c h = new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-C', Hold__c = true, Held__c = true);
        insert h;
        System.assertEquals('On Hold', lot('LST-C').Release_Status__c, 'the hold is stricter than the quarantine');
        update new Field_Action_Hold__c(Id = h.Id, Disposition__c = 'Release', Disposition_On__c = Datetime.now());
        System.assertEquals('Quarantined', lot('LST-C').Release_Status__c, 'only a person clears a status set by hand');
        System.assertEquals('Manual', lot('LST-C').Status_Set_By__c);

        update new compliancequest__SQX_Lot_Info__c(Id = l.Id, Release_Status__c = 'Released');
        System.assertEquals('Released', lot('LST-C').Release_Status__c, 'the person lets go');
    }

    @IsTest
    static void twoFieldActionsThatDisagreeAreFlagged() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-D', compliancequest__Part_Number__c = 'LST-1');
        Field_Action__c a = fa(p.Id, 'Release it');
        Field_Action__c b = fa(p.Id, 'Scrap it');
        insert new List<Field_Action_Hold__c>{
            new Field_Action_Hold__c(Field_Action__c = a.Id, Lot_Number__c = 'LST-D', Hold__c = true, Held__c = true, Disposition__c = 'Release', Disposition_On__c = Datetime.now()),
            new Field_Action_Hold__c(Field_Action__c = b.Id, Lot_Number__c = 'LST-D', Hold__c = true, Held__c = true, Disposition__c = 'Scrap', Disposition_On__c = Datetime.now()) };
        compliancequest__SQX_Lot_Info__c l = lot('LST-D');
        System.assertEquals('Rejected', l.Release_Status__c, 'the strictest wins');
        System.assertNotEquals(null, l.Status_Conflict__c, 'opposite final decisions are flagged');
    }

    @IsTest
    static void aRecallScopeMakesTheLotRecallPendingThenRecalled() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-F', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        Field_Action__c f = new Field_Action__c(Title__c = 'Recall test', Part__c = p.Id, Action_Type__c = 'Removal (Recall)');
        insert f;
        Field_Action_Lot__c r = new Field_Action_Lot__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-F', In_Scope__c = true);
        insert r;
        System.assertEquals('Recall Pending', lot('LST-F').Release_Status__c, 'in the scope, not yet approved');
        update new Field_Action_Lot__c(Id = r.Id, Approved_In_Scope__c = true);
        System.assertEquals('Recalled', lot('LST-F').Release_Status__c, 'the scope is approved');
        System.assertEquals([SELECT Name FROM Field_Action__c WHERE Id = :f.Id].Name, lot('LST-F').Status_Set_By__c);

        // the recall's own decision on the lot replaces the recall
        insert new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-F', Hold__c = true, Held__c = true,
            Disposition__c = 'Release', Disposition_On__c = Datetime.now());
        System.assertEquals('Released', lot('LST-F').Release_Status__c, 'checked and found fine');
    }

    @IsTest
    static void aWithdrawalHasItsOwnStatuses() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-W', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Released');
        Field_Action__c f = new Field_Action__c(Title__c = 'Withdrawal test', Part__c = p.Id, Action_Type__c = 'Withdrawal');
        insert f;
        Field_Action_Lot__c r = new Field_Action_Lot__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-W', In_Scope__c = true);
        insert r;
        System.assertEquals('Withdrawal Pending', lot('LST-W').Release_Status__c, 'in the scope, not yet approved');
        update new Field_Action_Lot__c(Id = r.Id, Approved_In_Scope__c = true);
        System.assertEquals('Withdrawn', lot('LST-W').Release_Status__c, 'the scope is approved');
        update new Field_Action__c(Id = f.Id, Action_Type__c = 'Removal (Recall)');
        System.assertEquals('Recalled', lot('LST-W').Release_Status__c, 'it became a recall');
        System.assert(CqLotStatus.rank('Recall Pending') > CqLotStatus.rank('Withdrawn'), 'a recall is stricter than a withdrawal');
    }

    @IsTest
    static void aCorrectionIsNotARecallAndTheTypeCanChange() {
        compliancequest__SQX_Part__c p = part();
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-G', compliancequest__Part_Number__c = 'LST-1');
        Field_Action__c f = new Field_Action__c(Title__c = 'Correction test', Part__c = p.Id, Action_Type__c = 'Correction');
        insert f;
        insert new Field_Action_Lot__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-G', In_Scope__c = true, Approved_In_Scope__c = true);
        System.assertEquals('Released', lot('LST-G').Release_Status__c);
        update new Field_Action__c(Id = f.Id, Action_Type__c = 'Removal (Recall)');
        System.assertEquals('Recalled', lot('LST-G').Release_Status__c, 'it became a recall');
    }

    @IsTest
    static void theBatchRecordReleasesTheLot() {
        CqLotStatus.Say s = CqLotStatus.batchSay('BR-1', 'Released', Date.newInstance(2026, 9, 8));
        System.assertEquals(null, s.status, 'a released batch lets the lot go');
        System.assert(s.basis, 'and names Status Set By when nothing holds the lot');
        System.assertEquals(false, s.finalRelease, 'a batch release is no final decision, so a later scrap is no conflict');
        System.assertEquals('Pending QA', CqLotStatus.batchSay('BR-1', 'Draft', null).status);
        System.assertEquals('Pending QA', CqLotStatus.batchSay('BR-1', 'Approved', null).status, 'approved is not yet released');
        System.assertEquals('Rejected', CqLotStatus.batchSay('BR-1', 'Void', null).status);
    }

    @IsTest
    static void releasingAHoldSaysWhatStillHoldsTheLot() {
        compliancequest__SQX_Part__c p = part();
        insert new List<compliancequest__SQX_Lot_Info__c>{
            new compliancequest__SQX_Lot_Info__c(Name = 'LST-H', compliancequest__Part_Number__c = 'LST-1', Release_Status__c = 'Quarantined'),
            new compliancequest__SQX_Lot_Info__c(Name = 'LST-I', compliancequest__Part_Number__c = 'LST-1') };
        Field_Action__c f = new Field_Action__c(Title__c = 'Outlook test', Part__c = p.Id, Action_Type__c = 'Removal (Recall)');
        insert f;
        insert new List<Field_Action_Hold__c>{
            new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-H', Hold__c = true, Held__c = true),
            new Field_Action_Hold__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-I', Hold__c = true, Held__c = true) };
        insert new Field_Action_Lot__c(Field_Action__c = f.Id, Lot_Number__c = 'LST-I', In_Scope__c = true, Approved_In_Scope__c = true);

        // Recovery: the field action's own decision replaces its hold and its recall
        Map<String, CqLotStatus.Outlook> rec = CqLotStatus.outlook(new Set<String>{ 'LST-H', 'LST-I' }, f.Id, true);
        System.assertEquals('Quarantined', rec.get('LST-H').status, 'set by hand, so releasing the hold does not release the lot');
        System.assertEquals('Manual', rec.get('LST-H').heldBy);
        System.assert(!rec.containsKey('LST-I'), 'nothing else holds it: releasing it frees the lot');

        // Strategy: unticking the hold leaves the field action's recall in place
        Map<String, CqLotStatus.Outlook> strat = CqLotStatus.outlook(new Set<String>{ 'LST-I' }, f.Id, false);
        System.assertEquals('Recalled', strat.get('LST-I').status);
        System.assertEquals(f.Id, strat.get('LST-I').heldById);
    }

    @IsTest
    static void receivingRejectionRejectsTheLot() {
        insert new compliancequest__SQX_Lot_Info__c(Name = 'LST-E', Lot_Type__c = 'Purchased', Receiving_Inspection__c = 'Rejected');
        System.assertEquals('Rejected', lot('LST-E').Release_Status__c);
        System.assertEquals('Receiving inspection', lot('LST-E').Status_Set_By__c);
    }
}

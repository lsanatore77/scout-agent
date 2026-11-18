/** The Scope step of the Field Action workspace: the lots of the part, the Partial draft and its confirm, and a Full scope that fills itself. */
@IsTest
private class CqFieldActionScopeTest {

    static compliancequest__SQX_Part__c makePart() {
        compliancequest__SQX_Part_Family__c fam = new compliancequest__SQX_Part_Family__c(Name = 'Scope Family');
        insert fam;
        compliancequest__SQX_Part__c part = new compliancequest__SQX_Part__c(
            Name = 'Scope Part', cqext__Title__c = 'Scope Part', compliancequest__Part_Number__c = 'FAS-PART-1',
            compliancequest__Part_Family__c = fam.Id, compliancequest__Part_Type__c = 'Finished Product',
            compliancequest__Active__c = true, cqext__Part_Definition__c = 'Individual');
        insert part;
        insert new List<compliancequest__SQX_Lot_Info__c>{
            new compliancequest__SQX_Lot_Info__c(Name = 'FAS-L1', compliancequest__Part_Number__c = 'FAS-PART-1'),
            new compliancequest__SQX_Lot_Info__c(Name = 'FAS-L2', compliancequest__Part_Number__c = 'FAS-PART-1') };
        return part;
    }

    static Field_Action__c makeFa(Id partId, String scope) {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Scope test', Part__c = partId, Scope__c = scope,
            Scope_Status__c = scope == 'Full' ? 'Full Scope' : scope == 'Partial' ? 'Being Defined' : null);
        insert fa;
        return fa;
    }

    static CqFieldActionScope.LotRow row(CqFieldActionScope.View v, String lot) {
        for (CqFieldActionScope.LotRow x : v.lots) { if (x.name == lot) { return x; } }
        return null;
    }

    static String refused(Id faId, String lot, Boolean add) {
        try {
            CqFieldActionScope.setLot(faId, lot, add);
        } catch (AuraHandledException e) {
            return 'refused';
        }
        return 'allowed';
    }

    @IsTest
    static void partialScopeIsADraftUntilConfirmed() {
        compliancequest__SQX_Part__c part = makePart();
        insert new Signal__c(Part__c = part.Id, Lot_Number__c = 'FAS-L2', Strength__c = 'Escalate', Status__c = 'New', Summary__c = 'Three complaints on one lot');
        Field_Action__c fa = makeFa(part.Id, 'Partial');

        Test.startTest();
        CqFieldActionScope.View v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals('Partial', v.scope);
        System.assertEquals('FAS-PART-1', v.partNumber);
        System.assertEquals(2, v.lots.size(), 'both lots of the part are offered');
        System.assertEquals(1, v.signals.size());
        System.assertEquals(true, row(v, 'FAS-L2').suggested, 'a lot with a signal of its own is suggested');
        System.assertEquals('Manual at Escalate', row(v, 'FAS-L2').why);
        System.assertEquals(false, row(v, 'FAS-L1').suggested);
        System.assertEquals('FAS-L2', v.lots[0].name, 'suggested lots come before the rest');

        // tick a lot: saved as a draft, not yet confirmed
        Id rowId = CqFieldActionScope.setLot(fa.Id, 'FAS-L1', true);
        System.assertEquals(rowId, CqFieldActionScope.setLot(fa.Id, 'FAS-L1', true), 'ticking it again changes nothing');
        v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals(1, v.pendingAdds);
        System.assertEquals(true, row(v, 'FAS-L1').inScope);
        System.assertEquals(false, row(v, 'FAS-L1').confirmed);
        System.assertEquals(0, v.changes.size(), 'nothing is logged until Confirm Scope');

        v = CqFieldActionScope.confirmScope(fa.Id);
        System.assertEquals('Confirmed', v.scopeStatus);
        System.assertEquals(true, row(v, 'FAS-L1').confirmed);
        System.assertEquals(1, v.changes.size());
        System.assertEquals('Added', v.changes[0].change);
        System.assertEquals('FAS-L1', [SELECT Lot_Numbers__c FROM Field_Action__c WHERE Id = :fa.Id].Lot_Numbers__c);
        try {
            CqFieldActionScope.confirmScope(fa.Id);
            System.assert(false, 'confirming with no change is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }

        // a second lot is ticked with its signal as the reason, then the draft is discarded
        Id second = CqFieldActionScope.setLot(fa.Id, 'FAS-L2', true);
        System.assertEquals('Manual at Escalate', [SELECT Reason__c FROM Field_Action_Lot__c WHERE Id = :second].Reason__c);
        System.assertEquals('Being Defined', [SELECT Scope_Status__c FROM Field_Action__c WHERE Id = :fa.Id].Scope_Status__c, 'a change reopens the scope');
        v = CqFieldActionScope.discardChanges(fa.Id);
        System.assertEquals('Confirmed', v.scopeStatus);
        System.assertEquals(false, row(v, 'FAS-L2').inScope, 'the unconfirmed lot is gone');
        System.assertEquals(0, v.pendingAdds);
        Test.stopTest();
    }

    @IsTest
    static void removalsAreDraftsToo() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c fa = makeFa(part.Id, 'Partial');
        CqFieldActionScope.setLot(fa.Id, 'FAS-L1', true);
        CqFieldActionScope.confirmScope(fa.Id);

        Test.startTest();
        CqFieldActionScope.View v;
        // unticking a confirmed lot is a pending removal; discarding puts it back
        CqFieldActionScope.setLot(fa.Id, 'FAS-L1', false);
        v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals(1, v.pendingRemoves);
        v = CqFieldActionScope.discardChanges(fa.Id);
        System.assertEquals(true, row(v, 'FAS-L1').inScope);

        // a scope needs at least one lot
        CqFieldActionScope.setLot(fa.Id, 'FAS-L1', false);
        try {
            CqFieldActionScope.confirmScope(fa.Id);
            System.assert(false, 'an empty scope is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        CqFieldActionScope.discardChanges(fa.Id);

        // an unconfirmed lot that is unticked goes away
        CqFieldActionScope.setLot(fa.Id, 'FAS-L2', true);
        System.assertEquals(null, CqFieldActionScope.setLot(fa.Id, 'FAS-L2', false));
        System.assertEquals(null, CqFieldActionScope.setLot(fa.Id, 'FAS-NOT-THERE', false));
        System.assertEquals('refused', refused(fa.Id, ' ', true), 'a lot must be named');
        Test.stopTest();
    }

    @IsTest
    static void unitsAreSavedOnALotInScope() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c fa = makeFa(part.Id, 'Partial');
        Field_Action__c other = makeFa(part.Id, 'Partial');
        Id rowId = CqFieldActionScope.setLot(fa.Id, 'FAS-L1', true);

        CqFieldActionScope.View v = CqFieldActionScope.saveLot(fa.Id, rowId, 12, 5, 'Dock 4');
        System.assertEquals(12, row(v, 'FAS-L1').shipped);
        System.assertEquals(5, row(v, 'FAS-L1').onHand);
        System.assertEquals('Dock 4', row(v, 'FAS-L1').location);
        try {
            CqFieldActionScope.saveLot(fa.Id, rowId, -1, 5, null);
            System.assert(false, 'negative units are refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            CqFieldActionScope.saveLot(other.Id, rowId, 1, 1, null);
            System.assert(false, 'a lot of another field action is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void fullScopeFillsItself() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c fa = makeFa(part.Id, 'Full');

        Test.startTest();
        CqFieldActionScope.View v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals(2, v.lots.size());
        System.assertEquals(true, row(v, 'FAS-L1').inScope);
        System.assertEquals(true, row(v, 'FAS-L1').confirmed);
        System.assertEquals(true, row(v, 'FAS-L1').locked, 'a lot added automatically cannot be unticked');
        System.assertEquals('Full scope covers every lot of FAS-PART-1', row(v, 'FAS-L1').reason);
        System.assertEquals(2, v.changes.size());
        System.assertEquals('FAS-L1, FAS-L2', [SELECT Lot_Numbers__c FROM Field_Action__c WHERE Id = :fa.Id].Lot_Numbers__c);
        System.assertEquals('refused', refused(fa.Id, 'FAS-L1', false), 'a Full scope is not edited by hand');

        // a lot that appears later comes in on the next sync, with where it was found
        insert new compliancequest__SQX_Lot_Info__c(Name = 'FAS-L3', compliancequest__Part_Number__c = 'FAS-PART-1');
        CqFieldActionScope.syncFull();
        v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals(3, v.lots.size());
        System.assertEquals('New lot of FAS-PART-1 found in CQ', row(v, 'FAS-L3').reason);
        CqFieldActionScope.syncFull();   // nothing new: no change
        System.assertEquals(3, [SELECT COUNT() FROM Field_Action_Lot__c WHERE Field_Action__c = :fa.Id]);
        Test.stopTest();
    }

    @IsTest
    static void closedOrUnscopedFieldActionsAreNotChanged() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c none = makeFa(part.Id, null);
        System.assertEquals('refused', refused(none.Id, 'FAS-L1', true), 'no scope set');
        Field_Action__c closed = makeFa(part.Id, 'Partial');
        update new Field_Action__c(Id = closed.Id, Status__c = 'Closed');
        System.assertEquals('refused', refused(closed.Id, 'FAS-L1', true), 'closed');

        CqFieldActionScope.Genealogy g = CqFieldActionScope.genealogy(none.Id, 'FAS-L1');
        System.assertEquals('FAS-L1', g.lot);
        System.assert(g.note.startsWith('No batch record is linked'), g.note);
        System.assertEquals(0, g.rows.size());
    }

    @IsTest
    static void anApprovedReviewBringsItsLotAndScope() {
        compliancequest__SQX_Part__c part = makePart();
        Field_Action__c fa = makeFa(part.Id, null);
        Field_Action_Review__c review = new Field_Action_Review__c(Title__c = 'Review', Field_Action__c = fa.Id, Part__c = part.Id, Lot_Number__c = 'FAS-L1',
            Scope__c = 'Partial', Status__c = 'Decided', Outcome__c = 'Field Action Needed', Risk_Score__c = 72, Risk_Level__c = 'High',
            Health_Hazard_Summary__c = 'Seal can open in use', Outcome_Rationale__c = 'Two lots affected', Decided_On__c = Datetime.now(), Decided_By__c = UserInfo.getUserId());
        insert review;

        // no approval matches: nothing happens
        CqFieldActionScope.onClosed(new Map<Id, String>{ UserInfo.getUserId() => 'Approved' });
        System.assertEquals(0, [SELECT COUNT() FROM Field_Action_Lot__c WHERE Field_Action__c = :fa.Id]);

        CqFieldActionScope.View v = CqFieldActionScope.getView(fa.Id);
        System.assertEquals(1, v.reviews.size(), 'the review that led here is listed');
        System.assertEquals(72, v.score);
        System.assertEquals('High', v.riskLevel);
        System.assertEquals('Seal can open in use', v.hazard);
        System.assertEquals('FAS-L1', v.reviews[0].lot);
    }
}

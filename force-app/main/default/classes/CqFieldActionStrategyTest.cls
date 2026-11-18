/** The Strategy step of the Field Action workspace: CQ.AI's suggestions by recall class, the draft saves, the holds and Confirm Strategy. */
@IsTest
private class CqFieldActionStrategyTest {

    static Field_Action__c makeFa(String recallClass, Decimal shipped) {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Strategy test', Scope__c = 'Full', Scope_Status__c = 'Full Scope', Recall_Class__c = recallClass);
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FST-L1', In_Scope__c = true, Approved_In_Scope__c = true,
            Added_How__c = 'Automatic', Units_Shipped__c = shipped, Units_On_Hand__c = 5);
        return fa;
    }

    static Map<String, String> choices(String level, String percent) {
        return new Map<String, String>{
            'action' => CqFieldActionStrategy.REMOVAL, 'depth' => 'Hospital', 'instruction' => CqFieldActionStrategy.RETURN_IT,
            'message' => 'Stop using the product and return it.', 'level' => level, 'percent' => percent,
            'method' => 'Phone call', 'checkBy' => String.valueOf(Date.today().addDays(30)) };
    }

    static String confirmRefused(Id faId, Map<String, String> values) {
        try {
            CqFieldActionStrategy.confirmStrategy(faId, values);
        } catch (AuraHandledException e) {
            return 'refused';
        }
        return 'confirmed';
    }

    @IsTest
    static void theInstructionMustFitTheAction() {
        System.assertEquals(true, CqFieldActionStrategy.fits(CqFieldActionStrategy.REMOVAL, CqFieldActionStrategy.RETURN_IT));
        System.assertEquals(true, CqFieldActionStrategy.fits(CqFieldActionStrategy.REMOVAL, CqFieldActionStrategy.DESTROY));
        System.assertEquals(false, CqFieldActionStrategy.fits(CqFieldActionStrategy.REMOVAL, CqFieldActionStrategy.WARN));
        System.assertEquals(true, CqFieldActionStrategy.fits(CqFieldActionStrategy.CORRECTION, CqFieldActionStrategy.FIX));
        System.assertEquals(true, CqFieldActionStrategy.fits(CqFieldActionStrategy.NOTICE, CqFieldActionStrategy.WARN));
        System.assertEquals(false, CqFieldActionStrategy.fits(null, CqFieldActionStrategy.WARN));
    }

    @IsTest
    static void suggestionsFollowTheRecallClass() {
        Field_Action__c one = makeFa('Class I', 100);
        Field_Action__c twoSmall = makeFa('Class II', 100);
        Field_Action__c twoLarge = makeFa('Class II', 5000);
        Field_Action__c three = makeFa('Class III', 100);
        Field_Action__c none = makeFa(null, null);
        insert new Field_Action_Review__c(Title__c = 'Review', Field_Action__c = one.Id, Risk_Score__c = 80, Health_Hazard_Summary__c = 'The seal can open in use.');

        Test.startTest();
        CqFieldActionStrategy.View v = CqFieldActionStrategy.getView(one.Id);
        System.assertEquals(true, v.scopeConfirmed, 'a Full scope needs no confirming');
        System.assertEquals(CqFieldActionStrategy.REMOVAL, v.sAction);
        System.assertEquals('Patient', v.sDepth);
        System.assertEquals('Level A', v.sLevel);
        System.assertEquals(CqFieldActionStrategy.RETURN_IT, v.sInstruction);
        System.assert(v.sMessage.contains('lot FST-L1'), v.sMessage);
        System.assert(v.sMessage.endsWith('Why: The seal can open in use.'), 'the key message carries the health hazard: ' + v.sMessage);
        System.assertEquals(1, v.lotCount);
        System.assertEquals(100, v.shipped);

        v = CqFieldActionStrategy.getView(twoSmall.Id);
        System.assertEquals('Hospital', v.sDepth);
        System.assertEquals('Level A', v.sLevel, 'few units out: every customer can be reached');
        v = CqFieldActionStrategy.getView(twoLarge.Id);
        System.assertEquals('Level B', v.sLevel, 'too many to check them all');

        v = CqFieldActionStrategy.getView(three.Id);
        System.assertEquals(CqFieldActionStrategy.NOTICE, v.sAction);
        System.assertEquals('Distributor', v.sDepth);
        System.assertEquals('Level C', v.sLevel);
        System.assertEquals(CqFieldActionStrategy.WARN, v.sInstruction);
        System.assert(v.sMessage.startsWith('You can keep using'), v.sMessage);

        v = CqFieldActionStrategy.getView(none.Id);
        System.assertEquals(null, v.sAction, 'no recall class: the action follows the review');
        System.assertEquals('Level B', v.sLevel);
        Test.stopTest();
    }

    @IsTest
    static void theStrategyWaitsForAConfirmedScope() {
        Field_Action__c fa = new Field_Action__c(Title__c = 'Strategy test', Scope__c = 'Partial', Scope_Status__c = 'Being Defined');
        insert fa;
        CqFieldActionStrategy.View v = CqFieldActionStrategy.getView(fa.Id);
        System.assertEquals(false, v.scopeConfirmed);
        System.assertEquals(0, v.holds.size());
        try {
            CqFieldActionStrategy.saveField(fa.Id, 'depth', 'Hospital');
            System.assert(false, 'no saves before the scope is confirmed');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        // confirmed, but with a lot ticked and not yet confirmed: still waiting
        update new Field_Action__c(Id = fa.Id, Scope_Status__c = 'Confirmed');
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FST-L9', In_Scope__c = true, Approved_In_Scope__c = false, Added_How__c = 'Coordinator');
        System.assertEquals(false, CqFieldActionStrategy.getView(fa.Id).scopeConfirmed);
    }

    @IsTest
    static void eachChoiceIsSavedAsADraft() {
        Field_Action__c fa = makeFa('Class II', 100);
        update new Field_Action__c(Id = fa.Id, Strategy_Status__c = 'Confirmed');

        Test.startTest();
        CqFieldActionStrategy.View v = CqFieldActionStrategy.saveField(fa.Id, 'action', CqFieldActionStrategy.CORRECTION);
        System.assertEquals('Being Defined', v.status, 'a change after confirming reopens the strategy');
        System.assertEquals(CqFieldActionStrategy.CORRECTION, v.action);
        System.assertEquals(CqFieldActionStrategy.FIX, v.sInstruction, 'the suggested instruction follows the chosen action');
        CqFieldActionStrategy.saveField(fa.Id, 'depth', 'Hospital');
        CqFieldActionStrategy.saveField(fa.Id, 'instruction', CqFieldActionStrategy.DESTROY);
        CqFieldActionStrategy.saveField(fa.Id, 'message', 'Destroy the units on site.');
        CqFieldActionStrategy.saveField(fa.Id, 'level', 'Level B');
        CqFieldActionStrategy.saveField(fa.Id, 'percent', '40');
        CqFieldActionStrategy.saveField(fa.Id, 'method', 'Site visit');
        v = CqFieldActionStrategy.saveField(fa.Id, 'checkBy', String.valueOf(Date.today().addDays(14)));
        Test.stopTest();

        System.assertEquals('Hospital', v.depth);
        System.assertEquals(CqFieldActionStrategy.DESTROY, v.instruction);
        System.assertEquals('Destroy the units on site.', v.message);
        System.assertEquals('Level B', v.level);
        System.assertEquals(40, v.percent);
        System.assertEquals('Site visit', v.method);
        System.assertEquals(Date.today().addDays(14), v.checkBy);
        System.assert(v.sMessage.contains('Destroy the units on site'), 'the suggested message follows the saved instruction');

        v = CqFieldActionStrategy.saveField(fa.Id, 'percent', '');
        System.assertEquals(null, v.percent, 'a blank value clears the choice');
        try {
            CqFieldActionStrategy.saveField(fa.Id, 'colour', 'blue');
            System.assert(false, 'an unknown choice is refused');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void confirmPlacesAndReleasesHolds() {
        Field_Action__c fa = makeFa('Class II', 100);
        insert new Lot_Stock__c(Lot_Number__c = 'FST-L1', Units_On_Hand__c = 5);

        Test.startTest();
        CqFieldActionStrategy.View v = CqFieldActionStrategy.getView(fa.Id);
        System.assertEquals(1, v.holds.size(), 'one hold row per finished lot in scope');
        CqFieldActionStrategy.HoldRow h = v.holds[0];
        System.assertEquals('FST-L1', h.lot);
        System.assertEquals(CqFieldActionStrategy.FINISHED, h.kind);
        System.assertEquals(true, h.hold);
        System.assertEquals(true, h.suggested);
        System.assertEquals(false, h.held, 'ticked, not yet placed');
        System.assertEquals(5, h.onHand);
        System.assertEquals(1, h.places.size(), 'where the stock sits comes from Lot Stock');

        Map<String, String> missing = choices('Level B', null);
        missing.remove('message');
        System.assertEquals('refused', confirmRefused(fa.Id, missing), 'the key message and the share are missing');
        Map<String, String> mismatch = choices('Level A', null);
        mismatch.put('instruction', CqFieldActionStrategy.WARN);
        System.assertEquals('refused', confirmRefused(fa.Id, mismatch), 'a removal does not say keep using it');
        System.assertEquals('refused', confirmRefused(fa.Id, choices('Level B', '5')), 'Level B checks more than 10%');

        v = CqFieldActionStrategy.confirmStrategy(fa.Id, choices('Level B', '50'));
        System.assertEquals('Confirmed', v.status);
        System.assertEquals(50, v.percent);
        System.assertEquals(true, v.holds[0].held, 'Confirm Strategy places the ticked hold');
        System.assertNotEquals(null, v.holds[0].heldOn);

        // untick the hold: the strategy reopens, and the next confirm releases it
        v = CqFieldActionStrategy.setHold(fa.Id, h.id, null, false);
        System.assertEquals('Being Defined', v.status);
        v = CqFieldActionStrategy.confirmStrategy(fa.Id, choices('Level E', null));
        System.assertEquals(false, v.holds[0].held);
        System.assertEquals(null, v.method, 'Level E has no check, so no method or date');
        System.assertEquals(null, v.checkBy);

        try {
            CqFieldActionStrategy.setHold(fa.Id, null, 'NOT-A-COMPONENT', true);
            System.assert(false, 'only a component of a lot in scope can be added');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void holdsFollowTheScopeAndClosedIsLocked() {
        Field_Action__c fa = makeFa('Class II', 100);
        System.assertEquals(1, CqFieldActionStrategy.getView(fa.Id).holds.size());
        // the lot leaves the scope: a hold that was never placed goes with it
        delete [SELECT Id FROM Field_Action_Lot__c WHERE Field_Action__c = :fa.Id];
        System.assertEquals(0, CqFieldActionStrategy.getView(fa.Id).holds.size());

        update new Field_Action__c(Id = fa.Id, Status__c = 'Closed');
        System.assertEquals(true, CqFieldActionStrategy.getView(fa.Id).closed);
        System.assertEquals('refused', confirmRefused(fa.Id, choices('Level A', null)), 'a closed field action is not changed');
    }
}

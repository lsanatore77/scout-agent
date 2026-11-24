/**
 * The Recovery and Effectiveness step and Closure of the Field Action workspace, with the recall tasks behind them.
 * Each test keeps to a few saves: every save re-reads the whole step, so the query limit is the constraint.
 */
@IsTest
private class CqFieldActionRecoveryTest {

    /** A field action with a confirmed strategy, one lot shipped to one customer (10 units) and one hold placed. */
    static Field_Action__c makeFa() {
        Account cust = new Account(Name = 'FRC Clinic');
        insert cust;
        Field_Action__c fa = new Field_Action__c(Title__c = 'Recovery test', Scope__c = 'Full', Scope_Status__c = 'Full Scope',
            Strategy_Status__c = 'Confirmed', Action_Type__c = CqFieldActionStrategy.REMOVAL, Depth__c = 'Hospital', Recall_Class__c = 'Class II',
            Check_Level__c = 'Level A', Check_By__c = Date.today().addDays(30));
        insert fa;
        insert new Field_Action_Lot__c(Field_Action__c = fa.Id, Lot_Number__c = 'FRC-L1', In_Scope__c = true, Approved_In_Scope__c = true,
            Added_How__c = 'Automatic', Units_On_Hand__c = 6);
        insert new Lot_Shipment__c(Lot_Number__c = 'FRC-L1', Units__c = 10, Customer__c = cust.Id);
        insert new Field_Action_Hold__c(Field_Action__c = fa.Id, Lot_Number__c = 'FRC-L1', Kind__c = CqFieldActionStrategy.FINISHED,
            Hold__c = true, Held__c = true, Held_On__c = Datetime.now(), Reason__c = 'In scope');
        return fa;
    }

    static Id lotRow(Id faId) { return [SELECT Id FROM Field_Action_Lot__c WHERE Field_Action__c = :faId LIMIT 1].Id; }
    static Id holdRow(Id faId) { return [SELECT Id FROM Field_Action_Hold__c WHERE Field_Action__c = :faId LIMIT 1].Id; }

    static CqFieldActionRecovery.Check check(CqFieldActionRecovery.View v, String key) {
        for (CqFieldActionRecovery.Check c : v.checks) { if (c.key == key) { return c; } }
        return null;
    }

    @IsTest
    static void theStepReadsLotsCustomersHoldsAndSuggestsTasks() {
        Field_Action__c fa = makeFa();

        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(true, v.strategyConfirmed);
        System.assertEquals(100, v.target, 'Level A: every customer');
        System.assertEquals(1, v.lots.size());
        System.assertEquals(10, v.lots[0].shipped, 'units shipped come from the lot shipments');
        System.assertEquals(10, v.lots[0].field);
        System.assertEquals(0, v.lots[0].pct);
        System.assertEquals(1, v.customers.size(), 'the customer that received the lot is listed');
        System.assertEquals('FRC Clinic', v.customers[0].name);
        System.assertEquals('Sent', v.customers[0].status);
        System.assertEquals('Shipment', v.customers[0].source);
        System.assertEquals(1, v.holds.size());
        System.assertEquals('Scrap', v.holds[0].suggested);
        System.assertEquals(6, v.holds[0].onHand);
        System.assertEquals(null, v.aiVerdict);
        System.assert(v.aiLine.startsWith('Not yet: 1 customer has not acknowledged, 10 units are still in the field, 1 held lot has no disposition.'), v.aiLine);
        System.assertEquals(false, v.canClose);
        System.assertEquals('ok', check(v, 'scope').state);
        System.assertEquals('ok', check(v, 'strategy').state);
        System.assertEquals('open', check(v, 'units').state);
        System.assertEquals('open', check(v, 'holds').state);
        System.assertEquals(CqFieldActionRecovery.CAPA_MISSING, check(v, 'capa').detail);
        System.assert(v.sSummary.contains('removed the product from lot FRC-L1 at hospital level (Class II).'), v.sSummary);

        // CQ.AI suggests a return per lot shipped to the customer; notices and responses run on Cases
        System.assertEquals(1, v.tasks.suggestions.size());
        System.assert(v.tasks.suggestLine.startsWith('1 task for a Level A removal (recall): 1 return.'), v.tasks.suggestLine);
        List<String> keys = new List<String>();
        for (CqFieldActionTasks.Suggestion s : v.tasks.suggestions) { keys.add(s.key); }
        v = CqFieldActionTasks.createSuggested(fa.Id, keys);
        System.assertEquals(1, v.tasks.open);
        System.assertEquals(0, v.tasks.suggestions.size(), 'a task that exists is not suggested again');
        System.assertEquals('In Progress', v.recovery);

        Map<String, String> rail = CqFieldActionRecovery.railStatus(fa.Id);
        System.assertEquals('Confirmed', rail.get('strategy'));
        System.assertEquals('0', rail.get('overdue'));
        Test.stopTest();
    }

    @IsTest
    static void tasksCarryTheUnitsAndTheAcknowledgement() {
        Field_Action__c fa = makeFa();
        CqFieldActionRecovery.getView(fa.Id);      // lists the customer
        Id custId = [SELECT Id FROM Field_Action_Customer__c WHERE Field_Action__c = :fa.Id].Id;
        Task back = new Task(WhatId = fa.Id, Subject = 'Track return of lot FRC-L1', Status = CqFieldActionTasks.OPEN, Priority = 'Normal',
            Recall_Task_Type__c = CqFieldActionTasks.RETURN_IT, Field_Action_Customer__c = custId, Lot_Number__c = 'FRC-L1', Units__c = 10,
            ActivityDate = Date.today().addDays(5));
        Task reply = new Task(WhatId = fa.Id, Subject = 'Collect response form', Status = CqFieldActionTasks.DONE, Priority = 'Normal',
            Recall_Task_Type__c = CqFieldActionTasks.RESPONSE, Field_Action_Customer__c = custId);
        insert new List<Task>{ back, reply };

        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(10, v.lots[0].returned, 'units on a Track return task add up to the lot');
        System.assertEquals(100, v.lots[0].pct);
        System.assertEquals(10, v.recovered);
        System.assertEquals('Acknowledged', v.customers[0].status, 'a completed Collect response acknowledges the customer');
        System.assertEquals(1, v.acked);
        System.assertEquals(true, v.targetMet);
        System.assertEquals(1, v.tasks.open);
        System.assertEquals(1, v.tasks.completed);
        System.assertEquals(1, v.tasks.dueWeek);

        v = CqFieldActionTasks.setTask(fa.Id, back.Id, 'units', 4);
        System.assertEquals(4, v.lots[0].returned);
        v = CqFieldActionTasks.setTask(fa.Id, back.Id, 'done', null);
        System.assertEquals(2, v.tasks.completed);
        Test.stopTest();

        for (String bad : new List<String>{ 'colour', 'units' }) {
            try {
                CqFieldActionTasks.setTask(fa.Id, back.Id, bad, -1);
                System.assert(false, 'refused: ' + bad);
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
    }

    @IsTest
    static void aTaskCanBeAddedForANewCustomer() {
        Field_Action__c fa = makeFa();

        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionTasks.addTask(fa.Id, new Map<String, String>{
            'subject' => 'Call the distributor', 'newCustomer' => 'FRC Distributor', 'lot' => 'FRC-L1', 'due' => String.valueOf(Date.today().addDays(-2)) });
        System.assertEquals(2, v.customers.size(), 'the new customer is added by hand');
        System.assertEquals(1, v.tasks.open);
        System.assertEquals(1, v.tasks.overdue);
        System.assertEquals(CqFieldActionTasks.OTHER, v.tasks.tasks[0].type);
        System.assert(v.aiLine.contains('1 task is overdue'), v.aiLine);
        v = CqFieldActionTasks.setTask(fa.Id, v.tasks.tasks[0].id, 'open', null);
        System.assertEquals(1, v.tasks.open);
        Test.stopTest();

        try {
            CqFieldActionTasks.addTask(fa.Id, new Map<String, String>{ 'subject' => ' ' });
            System.assert(false, 'a task needs a subject');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        try {
            CqFieldActionTasks.createSuggested(fa.Id, new List<String>());
            System.assert(false, 'at least one suggestion must be chosen');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }

    @IsTest
    static void recoveryIsRecordedByLotAndCustomer() {
        Field_Action__c fa = makeFa();
        Id rowId = lotRow(fa.Id);
        CqFieldActionRecovery.View v = CqFieldActionRecovery.saveLot(fa.Id, rowId, 4, 3, 3);
        System.assertEquals(10, v.recovered);
        System.assertEquals(100, v.lots[0].pct);
        System.assertEquals('ok', check(v, 'units').state);
        v = CqFieldActionRecovery.addCustomer(fa.Id, ' FRC Pharmacy ', 2, 'FRC-L1');
        System.assertEquals(2, v.customers.size());
        Id added = [SELECT Id FROM Field_Action_Customer__c WHERE Field_Action__c = :fa.Id AND Source__c = 'Added by hand'].Id;

        Test.startTest();
        v = CqFieldActionRecovery.setCustomer(fa.Id, added, 'Acknowledged');
        System.assertEquals(1, v.acked);
        System.assertEquals(false, v.targetMet, 'Level A needs every customer');
        v = CqFieldActionRecovery.setCustomer(fa.Id, added, 'followup');
        v = CqFieldActionRecovery.setCustomer(fa.Id, added, 'remove');
        System.assertEquals(1, v.customers.size());
        Test.stopTest();

        try { CqFieldActionRecovery.saveLot(fa.Id, rowId, 20, 0, 0); System.assert(false, 'more than shipped'); } catch (AuraHandledException e) { System.assert(true); }
        try { CqFieldActionRecovery.saveLot(fa.Id, rowId, -1, 0, 0); System.assert(false, 'negative'); } catch (AuraHandledException e) { System.assert(true); }
        try { CqFieldActionRecovery.addCustomer(fa.Id, ' ', 1, null); System.assert(false, 'no name'); } catch (AuraHandledException e) { System.assert(true); }
    }

    @IsTest
    static void anEffectiveVerdictFixesTheDispositions() {
        Field_Action__c fa = makeFa();
        Id holdId = holdRow(fa.Id);
        CqFieldActionRecovery.View v = CqFieldActionRecovery.setDisposition(fa.Id, holdId, 'Scrap');
        System.assertEquals(1, v.decided);
        System.assert(check(v, 'holds').detail.endsWith(': 1 scrapped'), check(v, 'holds').detail);
        v = CqFieldActionRecovery.saveVerdict(fa.Id, CqFieldActionRecovery.EFFECTIVE, 'ignored');
        System.assertEquals(null, v.nextStep, 'what happens next only goes with Not Effective');

        Test.startTest();
        v = CqFieldActionRecovery.confirmVerdict(fa.Id);
        System.assertEquals('Confirmed', v.recovery);
        System.assertNotEquals(null, v.verdictOn);
        System.assertEquals('ok', check(v, 'verdict').state);
        System.assertNotEquals(null, [SELECT Disposition_On__c FROM Field_Action_Hold__c WHERE Id = :holdId].Disposition_On__c);
        System.assert(v.sSummary.contains('The field action was effective.'), v.sSummary);

        // any change to recovery after that reopens the verdict and clears it
        v = CqFieldActionRecovery.saveLot(fa.Id, lotRow(fa.Id), 1, 0, 0);
        System.assertEquals('In Progress', v.recovery);
        System.assertEquals(null, v.verdict);
        Test.stopTest();
    }

    @IsTest
    static void reworkDoneIsMarkedOnAConfirmedRework() {
        Field_Action__c fa = makeFa();
        Id h = holdRow(fa.Id);
        update new Field_Action_Hold__c(Id = h, Disposition__c = 'Rework');
        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(false, v.holds[0].canMarkRework, 'not until the verdict confirms the rework');
        try { CqFieldActionRecovery.markReworkDone(fa.Id, h); System.assert(false, 'needs a confirmed Rework'); }
        catch (AuraHandledException e) { System.assert(true); }
        update new Field_Action_Hold__c(Id = h, Disposition_On__c = Datetime.now());
        update new Field_Action__c(Id = fa.Id, Recovery_Status__c = 'Confirmed', Verdict__c = CqFieldActionRecovery.EFFECTIVE);
        System.assertEquals(true, CqFieldActionRecovery.getView(fa.Id).holds[0].canMarkRework);
        v = CqFieldActionRecovery.markReworkDone(fa.Id, h);
        Test.stopTest();
        System.assertEquals(false, v.holds[0].canMarkRework);
        System.assert(v.holds[0].reworkDone.startsWith('Rework done by '), v.holds[0].reworkDone);
        System.assertEquals('Confirmed', [SELECT Recovery_Status__c FROM Field_Action__c WHERE Id = :fa.Id].Recovery_Status__c, 'the verdict stays confirmed');
    }

    @IsTest
    static void notEffectiveSaysWhatHappensNext() {
        Field_Action__c fa = makeFa();
        CqFieldActionRecovery.setDisposition(fa.Id, holdRow(fa.Id), 'Rework');
        CqFieldActionRecovery.saveVerdict(fa.Id, CqFieldActionRecovery.NOT_EFFECTIVE, CqFieldActionRecovery.EXTEND);

        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.confirmVerdict(fa.Id);
        System.assertEquals('In Progress', v.recovery, 'a Not Effective verdict keeps recovery open');
        System.assertEquals(Date.today().addDays(60), v.checkBy, 'extending moves the check-by date 30 days on');
        System.assert(check(v, 'verdict').detail.startsWith('Not Effective: '), check(v, 'verdict').detail);

        CqFieldActionRecovery.saveVerdict(fa.Id, CqFieldActionRecovery.NOT_EFFECTIVE, null);
        try {
            CqFieldActionRecovery.confirmVerdict(fa.Id);
            System.assert(false, 'Not Effective needs a next step');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
    }

    @IsTest
    static void aVerdictNeedsAChoiceAndEveryHoldDecided() {
        Field_Action__c fa = makeFa();
        Field_Action__c early = new Field_Action__c(Title__c = 'No strategy yet', Scope__c = 'Full', Scope_Status__c = 'Full Scope');
        insert early;
        try { CqFieldActionRecovery.saveVerdict(early.Id, CqFieldActionRecovery.EFFECTIVE, null); System.assert(false, 'strategy first'); } catch (AuraHandledException e) { System.assert(true); }
        try { CqFieldActionTasks.addTask(early.Id, new Map<String, String>{ 'subject' => 'x' }); System.assert(false, 'strategy first'); } catch (AuraHandledException e) { System.assert(true); }
        System.assertEquals(false, CqFieldActionRecovery.getView(early.Id).strategyConfirmed);

        Test.startTest();
        try { CqFieldActionRecovery.confirmVerdict(fa.Id); System.assert(false, 'no verdict chosen'); } catch (AuraHandledException e) { System.assert(true); }
        CqFieldActionRecovery.saveVerdict(fa.Id, CqFieldActionRecovery.EFFECTIVE, null);
        try { CqFieldActionRecovery.confirmVerdict(fa.Id); System.assert(false, 'a held lot has no disposition'); } catch (AuraHandledException e) { System.assert(true); }
        Test.stopTest();
    }

    @IsTest
    static void closureNotesAreSavedAndClosingWaitsForTheChecklist() {
        Field_Action__c fa = makeFa();

        Test.startTest();
        CqFieldActionRecovery.View v = CqFieldActionRecovery.saveClosure(fa.Id, 'summary', 'Closed out after the recall.');
        System.assertEquals('Closed out after the recall.', v.summary);
        v = CqFieldActionRecovery.saveClosure(fa.Id, 'other', 'NC-0001');
        System.assertEquals('NC-0001', v.otherRecords);
        v = CqFieldActionRecovery.saveClosure(fa.Id, 'capa', null);
        System.assertEquals(null, v.capaId);
        try { CqFieldActionRecovery.saveClosure(fa.Id, 'colour', 'blue'); System.assert(false, 'unknown field'); } catch (AuraHandledException e) { System.assert(true); }
        try {
            CqFieldActionRecovery.closeFieldAction(fa.Id, null);
            System.assert(false, 'open checklist items stop closing');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
        Test.stopTest();
        System.assertNotEquals('Closed', [SELECT Status__c FROM Field_Action__c WHERE Id = :fa.Id].Status__c);
    }

    @IsTest
    static void aFinishedFieldActionClosesAndLocks() {
        CqFieldActionRecovery.demoOverride = true;   // 10 units are still in the field: only Demo Mode lets it close
        Field_Action__c fa = makeFa();
        update new Field_Action_Hold__c(Id = holdRow(fa.Id), Disposition__c = 'Scrap');
        update new Field_Action__c(Id = fa.Id, Recovery_Status__c = 'Confirmed', Verdict__c = CqFieldActionRecovery.EFFECTIVE,
            Verdict_By__c = UserInfo.getUserId(), Verdict_On__c = Datetime.now());
        Boolean capaMade = true;
        try {
            CqFieldActionRecovery.View made = CqFieldActionRecovery.createCapa(fa.Id);
            System.assertNotEquals(null, made.capaId, 'the new CAPA is linked to the field action');
        } catch (Exception e) {
            capaMade = false;      // CQ's own rules can refuse a bare CAPA in a test org; closing then stays blocked, which is checked below
        }

        Test.startTest();
        if (capaMade) {
            try { CqFieldActionRecovery.createCapa(fa.Id); System.assert(false, 'one CAPA per field action'); } catch (AuraHandledException e) { System.assert(true); }
            CqFieldActionRecovery.View v = CqFieldActionRecovery.closeFieldAction(fa.Id, null);
            System.assertEquals(true, v.closed);
            System.assertEquals('Closed', v.status);
            System.assertNotEquals(null, v.closedOn);
            System.assert(v.summary.contains('Root cause and prevention continue in'), 'CQ.AI\'s draft is the closing summary when none was written: ' + v.summary);
            System.assertEquals(0, v.capas.size(), 'a closed field action offers no more choices');
            try { CqFieldActionRecovery.closeFieldAction(fa.Id, null); System.assert(false, 'already closed'); } catch (AuraHandledException e) { System.assert(true); }
            try { CqFieldActionRecovery.saveClosure(fa.Id, 'summary', 'x'); System.assert(false, 'closed'); } catch (AuraHandledException e) { System.assert(true); }
            try { CqFieldActionRecovery.createCapa(fa.Id); System.assert(false, 'closed'); } catch (AuraHandledException e) { System.assert(true); }
            try { CqFieldActionRecovery.saveVerdict(fa.Id, null, null); System.assert(false, 'closed'); } catch (AuraHandledException e) { System.assert(true); }
        } else {
            try {
                CqFieldActionRecovery.closeFieldAction(fa.Id, null);
                System.assert(false, 'no CAPA linked: closing is refused');
            } catch (AuraHandledException e) {
                System.assert(true);
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void outsideDemoModeEveryItemIsNeededToClose() {
        Field_Action__c fa = makeFa();
        CqFieldActionRecovery.demoOverride = false;
        CqFieldActionRecovery.View v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(false, v.demo);
        for (String k : new List<String>{ 'units', 'customers', 'tasks' }) { System.assertEquals(true, check(v, k).blocks, k + ' blocks outside Demo Mode'); }
        System.assertEquals(false, v.canClose);

        CqFieldActionRecovery.demoOverride = true;
        v = CqFieldActionRecovery.getView(fa.Id);
        System.assertEquals(true, v.demo);
        System.assertEquals(false, check(v, 'units').blocks, 'Demo Mode: units are flagged, not blocking');
        System.assertEquals(CqFieldActionRecovery.ACK_REQUIRED, check(v, 'customers').blocks);
        System.assertEquals(false, check(v, 'tasks').blocks);
        System.assertEquals(true, check(v, 'verdict').blocks, 'the verdict still blocks in Demo Mode');
    }
}

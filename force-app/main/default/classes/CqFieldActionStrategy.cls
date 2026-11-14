/**
 * CqFieldActionStrategy: data and saves for step 3 of the Field Action workspace, Strategy.
 *
 * Four parts, decided once the scope is confirmed:
 *  1. Action and Depth: Removal, Correction or Advisory Notice (the Action Type on the field action), and how far it
 *     goes: distributors, hospitals or patients.
 *  2. What We Tell Customers: the instruction, and the key message the Notifications step builds the letter from.
 *  3. Holds on Our Stock and Components: one Field Action Hold row per finished lot in scope, plus component lots
 *     used in them. CQ.AI suggests every finished lot, and any component lot with a nonconformance against it.
 *  4. Effectiveness Check: level A to E, the share for Level B, how it is done, and the date it is due.
 *
 * Each choice is saved straight away as a draft (Strategy Status Being Defined). Confirm Strategy saves what is on
 * screen, places the ticked holds (Held, Held On), releases unticked ones, and marks the strategy Confirmed.
 * A change after confirming returns it to Being Defined. Where nothing is saved yet, CQ.AI's suggestion is shown.
 */
public with sharing class CqFieldActionStrategy {
    public static final String REMOVAL = 'Removal (Recall)';
    public static final String CORRECTION = 'Correction';
    public static final String NOTICE = 'Advisory Notice';
    public static final String RETURN_IT = 'Stop use, quarantine and return';
    public static final String DESTROY = 'Stop use and destroy on site';
    public static final String FIX = 'Hold for our technician to correct on site';
    public static final String WARN = 'Continue use with the added warning';
    public static final String FINISHED = 'Finished Lot';
    public static final String COMPONENT = 'Component Lot';

    public class HoldRow {
        @AuraEnabled public Id id; @AuraEnabled public String lot; @AuraEnabled public String kind; @AuraEnabled public String part;
        @AuraEnabled public String item; @AuraEnabled public Boolean hold = false; @AuraEnabled public Boolean held = false;
        @AuraEnabled public Datetime heldOn; @AuraEnabled public Boolean suggested = false; @AuraEnabled public String reason;
        @AuraEnabled public Decimal onHand; @AuraEnabled public Boolean outOfScope = false;
    }
    public class Comp {
        @AuraEnabled public String lot; @AuraEnabled public String part; @AuraEnabled public String item; @AuraEnabled public String inLot;
    }
    public class View {
        @AuraEnabled public Id id; @AuraEnabled public String status; @AuraEnabled public String confirmedBy; @AuraEnabled public Datetime confirmedOn;
        @AuraEnabled public Boolean scopeConfirmed = false; @AuraEnabled public Boolean closed = false;
        @AuraEnabled public String partNumber; @AuraEnabled public String partName; @AuraEnabled public String recallClass;
        @AuraEnabled public Integer lotCount = 0; @AuraEnabled public Decimal built; @AuraEnabled public Decimal shipped;
        // saved values (null where nothing is saved yet)
        @AuraEnabled public String action; @AuraEnabled public String depth; @AuraEnabled public String instruction; @AuraEnabled public String message;
        @AuraEnabled public String level; @AuraEnabled public Decimal percent; @AuraEnabled public String method; @AuraEnabled public Date checkBy;
        // CQ.AI suggestions
        @AuraEnabled public String sAction; @AuraEnabled public String sDepth; @AuraEnabled public String sInstruction; @AuraEnabled public String sMessage;
        @AuraEnabled public String sLevel; @AuraEnabled public String sMethod; @AuraEnabled public Date sCheckBy;
        @AuraEnabled public String whyAction; @AuraEnabled public String whyLevel;
        @AuraEnabled public List<HoldRow> holds = new List<HoldRow>();
        @AuraEnabled public List<Comp> components = new List<Comp>();   // component lots that can be added as holds
    }

    private static Field_Action__c load(Id recordId) {
        return [SELECT Id, Name, Status__c, Action_Type__c, Recall_Class__c, Part__c, Part__r.Name, Part__r.compliancequest__Part_Number__c,
                       Scope__c, Scope_Status__c, Depth__c, Customer_Instruction__c, Key_Message__c, Check_Level__c, Check_Percent__c,
                       Check_Method__c, Check_By__c, Strategy_Status__c, Strategy_Confirmed_By__r.Name, Strategy_Confirmed_On__c
                FROM Field_Action__c WHERE Id = :recordId];
    }
    private static Boolean scopeConfirmed(Field_Action__c fa) {
        if (fa.Scope__c == CqFieldActionScope.FULL) { return true; }
        if (fa.Scope_Status__c != 'Confirmed') { return false; }
        return [SELECT COUNT() FROM Field_Action_Lot__c WHERE Field_Action__c = :fa.Id
                AND ((In_Scope__c = true AND Approved_In_Scope__c = false) OR (In_Scope__c = false AND Approved_In_Scope__c = true))] == 0;
    }
    private static void openForChange(Field_Action__c fa) {
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (!scopeConfirmed(fa)) { throw new AuraHandledException('Confirm the scope first: the strategy works from the confirmed lot list.'); }
    }
    private static void reopen(Field_Action__c fa) {
        if (fa.Strategy_Status__c != 'Being Defined') { update new Field_Action__c(Id = fa.Id, Strategy_Status__c = 'Being Defined'); }
    }

    // ---------------------------------------------------------------- read

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action__c fa = load(recordId);
        View v = new View();
        v.id = fa.Id; v.status = fa.Strategy_Status__c; v.confirmedBy = fa.Strategy_Confirmed_By__r?.Name; v.confirmedOn = fa.Strategy_Confirmed_On__c;
        v.closed = fa.Status__c == 'Closed'; v.scopeConfirmed = scopeConfirmed(fa);
        v.partNumber = fa.Part__r?.compliancequest__Part_Number__c; v.partName = fa.Part__r?.Name; v.recallClass = fa.Recall_Class__c;
        v.action = fa.Action_Type__c; v.depth = fa.Depth__c; v.instruction = fa.Customer_Instruction__c; v.message = fa.Key_Message__c;
        v.level = fa.Check_Level__c; v.percent = fa.Check_Percent__c; v.method = fa.Check_Method__c; v.checkBy = fa.Check_By__c;
        if (!v.scopeConfirmed) { return v; }

        List<Field_Action_Lot__c> lots = [SELECT Lot_Number__c, Units_Built__c, Units_Shipped__c, Units_On_Hand__c
                                          FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true ORDER BY Lot_Number__c];
        Map<String, Field_Action_Lot__c> byLot = new Map<String, Field_Action_Lot__c>();
        for (Field_Action_Lot__c l : lots) {
            byLot.put(l.Lot_Number__c, l); v.lotCount++;
            if (l.Units_Built__c != null) { v.built = (v.built == null ? 0 : v.built) + l.Units_Built__c; }
            if (l.Units_Shipped__c != null) { v.shipped = (v.shipped == null ? 0 : v.shipped) + l.Units_Shipped__c; }
        }
        suggest(v, fa, new List<String>(byLot.keySet()), hazard(recordId));

        // holds: one row per finished lot in scope, and per component lot with a nonconformance; kept in step with the scope
        Map<String, Field_Action_Hold__c> have = new Map<String, Field_Action_Hold__c>();
        for (Field_Action_Hold__c h : [SELECT Id, Lot_Number__c, Kind__c, Held__c FROM Field_Action_Hold__c WHERE Field_Action__c = :recordId]) {
            have.put(h.Kind__c + '|' + h.Lot_Number__c, h);
        }
        List<Field_Action_Hold__c> adds = new List<Field_Action_Hold__c>();
        List<Field_Action_Hold__c> drops = new List<Field_Action_Hold__c>();
        for (String n : byLot.keySet()) {
            if (!have.containsKey(FINISHED + '|' + n)) {
                adds.add(new Field_Action_Hold__c(Field_Action__c = recordId, Lot_Number__c = n, Kind__c = FINISHED, Part_Number__c = v.partNumber,
                    Item__c = v.partName, Hold__c = true, Suggested__c = true, Reason__c = 'In scope'));
            }
        }
        for (Field_Action_Hold__c h : have.values()) {
            if (h.Kind__c == FINISHED && !byLot.containsKey(h.Lot_Number__c) && !h.Held__c) { drops.add(h); }
        }
        Map<String, Comp> comps = components(byLot.keySet(), v);
        for (Comp c : comps.values()) {
            if (c.inLot == null || !c.inLot.startsWith('NC ')) { continue; }
            if (!have.containsKey(COMPONENT + '|' + c.lot)) {
                adds.add(new Field_Action_Hold__c(Field_Action__c = recordId, Lot_Number__c = c.lot, Kind__c = COMPONENT, Part_Number__c = c.part,
                    Item__c = c.item, Hold__c = true, Suggested__c = true, Reason__c = c.inLot.left(255)));
            }
        }
        if (!adds.isEmpty()) { insert adds; }
        if (!drops.isEmpty()) { delete drops; }

        Set<String> heldComps = new Set<String>();
        for (Field_Action_Hold__c h : [SELECT Id, Lot_Number__c, Kind__c, Part_Number__c, Item__c, Hold__c, Held__c, Held_On__c, Suggested__c, Reason__c
                                       FROM Field_Action_Hold__c WHERE Field_Action__c = :recordId ORDER BY Kind__c DESC, Lot_Number__c]) {
            HoldRow x = new HoldRow();
            x.id = h.Id; x.lot = h.Lot_Number__c; x.kind = h.Kind__c; x.part = h.Part_Number__c; x.item = h.Item__c; x.hold = h.Hold__c;
            x.held = h.Held__c; x.heldOn = h.Held_On__c; x.suggested = h.Suggested__c; x.reason = h.Reason__c;
            if (h.Kind__c == FINISHED) { x.outOfScope = !byLot.containsKey(h.Lot_Number__c); x.onHand = byLot.get(h.Lot_Number__c)?.Units_On_Hand__c; }
            else { heldComps.add(h.Lot_Number__c); }
            v.holds.add(x);
        }
        List<String> keys = new List<String>(comps.keySet()); keys.sort();
        for (String k : keys) { if (!heldComps.contains(k)) { v.components.add(comps.get(k)); } }
        return v;
    }

    private static String hazard(Id recordId) {
        String best; Decimal top;
        for (Field_Action_Review__c r : [SELECT Risk_Score__c, Health_Hazard_Summary__c FROM Field_Action_Review__c
                                         WHERE Field_Action__c = :recordId LIMIT 50]) {
            if (String.isBlank(r.Health_Hazard_Summary__c)) { continue; }
            if (best == null || (r.Risk_Score__c != null && (top == null || r.Risk_Score__c > top))) { best = r.Health_Hazard_Summary__c; top = r.Risk_Score__c; }
        }
        return best;
    }

    /** CQ.AI's suggestions, from the recall class, the units involved and the health hazard. */
    private static void suggest(View v, Field_Action__c fa, List<String> lotNames, String hazard) {
        String cls = fa.Recall_Class__c == null ? '' : fa.Recall_Class__c;
        Decimal units = v.shipped != null && v.shipped > 0 ? v.shipped : v.built;
        String unitText = units == null ? 'the units' : 'only ' + units.intValue() + ' units';
        if (cls.contains('III')) {
            v.sAction = NOTICE; v.sDepth = 'Distributor'; v.sLevel = 'Level C';
            v.whyAction = 'Class III: the product is unlikely to cause harm, so customers get the information and keep using it.';
            v.whyLevel = 'Level C: a 10% check is usual for a Class III action.';
        } else if (cls.contains('II')) {
            v.sAction = REMOVAL; v.sDepth = 'Hospital';
            v.whyAction = 'Class II: the product could cause temporary or reversible harm, so it comes back. It is used in procedures, so units sit on hospital shelves, not with patients.';
            Boolean small = units != null && units <= 500;
            v.sLevel = small ? 'Level A' : 'Level B';
            v.whyLevel = small ? 'Level A: ' + unitText + ' went out, so every customer can be reached.' : 'Level B: too many customers to check them all, so set a share.';
        } else if (cls.contains('I')) {
            v.sAction = REMOVAL; v.sDepth = 'Patient'; v.sLevel = 'Level A';
            v.whyAction = 'Class I: the product could cause serious harm, so it comes back from everyone who has it, patients included.';
            v.whyLevel = 'Level A: every customer must confirm for a Class I action.';
        } else {
            v.sAction = fa.Action_Type__c; v.sDepth = 'Hospital'; v.sLevel = 'Level B';
            v.whyAction = 'No recall class is set, so this follows the action decided at review.';
            v.whyLevel = 'Level B: set the share once the recall class is known.';
        }
        String act = v.action != null ? v.action : v.sAction;
        v.sInstruction = act == CORRECTION ? FIX : act == NOTICE ? WARN : RETURN_IT;
        v.sMethod = 'Signed response form, then phone';
        v.sCheckBy = Date.today().addDays(30);
        String part = v.partNumber == null ? 'the product' : v.partNumber + (v.partName == null || v.partName == v.partNumber ? '' : ' ' + v.partName);
        String lots = lotNames.size() == 1 ? 'lot ' + lotNames[0] : 'lots ' + String.join(lotNames, ', ');
        String instr = v.instruction != null ? v.instruction : v.sInstruction;
        String what = instr == RETURN_IT ? 'Stop using ' + part + ' from ' + lots + '. Set the units aside and return them using the enclosed form.'
            : instr == DESTROY ? 'Stop using ' + part + ' from ' + lots + '. Destroy the units on site and confirm using the enclosed form.'
            : instr == FIX ? 'Set aside ' + part + ' from ' + lots + ' until our technician corrects them on site.'
            : 'You can keep using ' + part + ' from ' + lots + '. Read the added warning before each use.';
        v.sMessage = what + (String.isBlank(hazard) ? '' : ' Why: ' + hazard.trim());
    }

    /**
     * Component lots used in the finished lots in scope, from the lots recorded on their batch records (one query for
     * all lots). A component lot with a nonconformance has inLot set to 'NC <number> · in lot <finished lot>', which
     * makes it a suggested hold.
     */
    private static Map<String, Comp> components(Set<String> finished, View v) {
        Map<String, Comp> out = new Map<String, Comp>();
        Map<Id, String> lotByBatch = new Map<Id, String>();
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name, Batch__c FROM compliancequest__SQX_Lot_Info__c WHERE Name IN :finished AND Batch__c != null]) {
            lotByBatch.put(l.Batch__c, l.Name);
        }
        if (lotByBatch.isEmpty()) { return out; }
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c, cqext__CQEBR_Operator_Product__r.Name,
                       cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c != null
                  AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c IN :lotByBatch.keySet()
                ORDER BY cqext__Lot_Number__c LIMIT 5000]) {
            String fin = lotByBatch.get(m.cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c);
            for (String c : m.cqext__Lot_Number__c.split(',\\s*')) {
                if (String.isBlank(c) || out.containsKey(c)) { continue; }
                Comp x = new Comp(); x.lot = c; x.inLot = 'In lot ' + fin;
                x.part = m.cqext__CQEBR_Operator_Product__r?.compliancequest__Part_Number__c; x.item = m.cqext__CQEBR_Operator_Product__r?.Name;
                out.put(c, x);
            }
        }
        if (out.isEmpty()) { return out; }
        for (compliancequest__SQX_Nonconformance__c nc : [SELECT Name, compliancequest__Lot_Number__c FROM compliancequest__SQX_Nonconformance__c
                                                          WHERE compliancequest__Lot_Number__c IN :out.keySet() ORDER BY CreatedDate LIMIT 500]) {
            Comp x = out.get(nc.compliancequest__Lot_Number__c);
            if (x != null && !x.inLot.startsWith('NC ')) { x.inLot = 'NC ' + nc.Name + ' · ' + x.inLot.uncapitalize(); }
        }
        return out;
    }

    // ---------------------------------------------------------------- saves

    /** Saves one choice straight away as a draft. */
    @AuraEnabled
    public static View saveField(Id recordId, String field, String value) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        Field_Action__c up = new Field_Action__c(Id = recordId, Strategy_Status__c = 'Being Defined');
        String val = String.isBlank(value) ? null : value;
        switch on field {
            when 'action' { up.Action_Type__c = val; }
            when 'depth' { up.Depth__c = val; }
            when 'instruction' { up.Customer_Instruction__c = val; }
            when 'message' { up.Key_Message__c = val; }
            when 'level' { up.Check_Level__c = val; }
            when 'percent' { up.Check_Percent__c = val == null ? null : Decimal.valueOf(val); }
            when 'method' { up.Check_Method__c = val; }
            when 'checkBy' { up.Check_By__c = val == null ? null : Date.valueOf(val); }
            when else { throw new AuraHandledException('Unknown choice: ' + field); }
        }
        update up;
        return getView(recordId);
    }

    /** Ticks or unticks a hold, or adds a component lot as a hold. Saved straight away as a draft. */
    @AuraEnabled
    public static View setHold(Id recordId, Id holdId, String lot, Boolean hold) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        if (holdId != null) {
            update new Field_Action_Hold__c(Id = holdId, Hold__c = hold == true);
        } else {
            Map<String, Comp> comps = components(new Set<String>(lotsInScope(recordId)), null);
            Comp c = comps.get(lot);
            if (c == null) { throw new AuraHandledException('Lot ' + lot + ' is not a component of a lot in scope.'); }
            insert new Field_Action_Hold__c(Field_Action__c = recordId, Lot_Number__c = c.lot, Kind__c = COMPONENT, Part_Number__c = c.part,
                Item__c = c.item, Hold__c = true, Reason__c = ('Added by the coordinator · ' + c.inLot).left(255));
        }
        reopen(fa);
        return getView(recordId);
    }

    private static List<String> lotsInScope(Id recordId) {
        List<String> out = new List<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true]) {
            out.add(l.Lot_Number__c);
        }
        return out;
    }

    /** The instruction must fit the action: a removal brings product back or destroys it, a correction fixes it, a notice warns. */
    public static Boolean fits(String action, String instruction) {
        if (action == REMOVAL) { return instruction == RETURN_IT || instruction == DESTROY; }
        if (action == CORRECTION) { return instruction == FIX; }
        if (action == NOTICE) { return instruction == WARN; }
        return false;
    }

    /** Confirm Strategy: saves what is on screen, places ticked holds, releases unticked ones. */
    @AuraEnabled
    public static View confirmStrategy(Id recordId, Map<String, String> values) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        String action = values.get('action'), depth = values.get('depth'), instruction = values.get('instruction');
        String message = values.get('message'), level = values.get('level'), method = values.get('method');
        String pct = values.get('percent'), dueOn = values.get('checkBy');
        List<String> missing = new List<String>();
        if (String.isBlank(action)) { missing.add('the action'); }
        if (String.isBlank(depth)) { missing.add('how far it goes'); }
        if (String.isBlank(instruction)) { missing.add('the customer instruction'); }
        if (String.isBlank(message)) { missing.add('the key message'); }
        if (String.isBlank(level)) { missing.add('the check level'); }
        if (level == 'Level B' && String.isBlank(pct)) { missing.add('the share to check'); }
        if (level != 'Level E' && String.isBlank(method)) { missing.add('how we check'); }
        if (level != 'Level E' && String.isBlank(dueOn)) { missing.add('the check-by date'); }
        if (!missing.isEmpty()) { throw new AuraHandledException('Choose ' + String.join(missing, ', ') + '.'); }
        if (!fits(action, instruction)) { throw new AuraHandledException('The customer instruction does not match the action.'); }
        Decimal p = level == 'Level B' ? Decimal.valueOf(pct) : null;
        if (p != null && (p <= 10 || p >= 100)) { throw new AuraHandledException('For Level B, check more than 10% and less than 100% of customers.'); }

        List<Field_Action_Hold__c> ups = new List<Field_Action_Hold__c>();
        Datetime now = Datetime.now();
        for (Field_Action_Hold__c h : [SELECT Id, Hold__c, Held__c FROM Field_Action_Hold__c WHERE Field_Action__c = :recordId]) {
            if (h.Hold__c && !h.Held__c) { ups.add(new Field_Action_Hold__c(Id = h.Id, Held__c = true, Held_On__c = now)); }
            if (!h.Hold__c && h.Held__c) { ups.add(new Field_Action_Hold__c(Id = h.Id, Held__c = false, Held_On__c = null)); }
        }
        update ups;
        update new Field_Action__c(Id = recordId, Action_Type__c = action, Depth__c = depth, Customer_Instruction__c = instruction,
            Key_Message__c = message, Check_Level__c = level, Check_Percent__c = p,
            Check_Method__c = level == 'Level E' ? null : method, Check_By__c = level == 'Level E' || String.isBlank(dueOn) ? null : Date.valueOf(dueOn),
            Strategy_Status__c = 'Confirmed', Strategy_Confirmed_By__c = UserInfo.getUserId(), Strategy_Confirmed_On__c = now);
        return getView(recordId);
    }
}

/**
 * CqFieldActionRecovery: data and saves for the last two steps of the Field Action workspace.
 *
 * Recovery and Effectiveness (step 6), open once the strategy is confirmed:
 *  1. Recovery by lot: units returned, destroyed and corrected against units shipped, per lot in scope.
 *  2. Customer responses: the customers that received the lots and whether each has acknowledged, measured against
 *     the check level from the strategy. Typed in here until the Notifications step is built.
 *  3. Held stock: a disposition for each lot held in the strategy.
 *  4. Effectiveness verdict: Effective, or Not Effective with what happens next. Confirm Verdict records it.
 *
 * Closure (step 7): a checklist from the earlier steps, the closing summary (drafted by CQ.AI), the CAPA that follows,
 * and Close Field Action, which sets the status to Closed. A closed field action takes no more changes.
 */
public with sharing class CqFieldActionRecovery {
    public static final String EFFECTIVE = 'Effective';
    public static final String NOT_EFFECTIVE = 'Not Effective';
    public static final String EXTEND = 'Extend the check by 30 days';

    public class LotRec {
        @AuraEnabled public Id id; @AuraEnabled public String lot; @AuraEnabled public Decimal shipped; @AuraEnabled public Decimal returned;
        @AuraEnabled public Decimal destroyed; @AuraEnabled public Decimal corrected; @AuraEnabled public Decimal field; @AuraEnabled public Integer pct;
    }
    public class Cust {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Decimal units; @AuraEnabled public String lots;
        @AuraEnabled public String status; @AuraEnabled public Decimal followUps; @AuraEnabled public Date respondedOn;
    }
    public class HoldDisp {
        @AuraEnabled public Id id; @AuraEnabled public String lot; @AuraEnabled public String kind; @AuraEnabled public String item;
        @AuraEnabled public Decimal onHand; @AuraEnabled public String disposition; @AuraEnabled public String suggested; @AuraEnabled public String reason;
    }
    public class Check {
        @AuraEnabled public String key; @AuraEnabled public String text; @AuraEnabled public String detail;
        @AuraEnabled public String state;            // ok | na | open
        @AuraEnabled public Boolean blocks = false;  // an open item that stops closing
    }
    public class Capa { @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title; }
    public class View {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String status; @AuraEnabled public Boolean closed = false;
        @AuraEnabled public Boolean strategyConfirmed = false; @AuraEnabled public String recovery; @AuraEnabled public String verdict;
        @AuraEnabled public String nextStep; @AuraEnabled public String verdictBy; @AuraEnabled public Datetime verdictOn;
        @AuraEnabled public String action; @AuraEnabled public String depth; @AuraEnabled public String level; @AuraEnabled public Decimal target;
        @AuraEnabled public Date checkBy;
        @AuraEnabled public List<LotRec> lots = new List<LotRec>();
        @AuraEnabled public List<Cust> customers = new List<Cust>();
        @AuraEnabled public List<HoldDisp> holds = new List<HoldDisp>();
        @AuraEnabled public Decimal shipped = 0; @AuraEnabled public Decimal recovered = 0; @AuraEnabled public Boolean shippedKnown = false;
        @AuraEnabled public Integer acked = 0; @AuraEnabled public Integer total = 0; @AuraEnabled public Boolean targetMet = false;
        @AuraEnabled public Integer decided = 0;
        @AuraEnabled public String aiVerdict; @AuraEnabled public String aiLine;
        // closure
        @AuraEnabled public List<Check> checks = new List<Check>();
        @AuraEnabled public Boolean canClose = false;
        @AuraEnabled public String summary; @AuraEnabled public String sSummary;
        @AuraEnabled public Id capaId; @AuraEnabled public String capaName;
        @AuraEnabled public List<Capa> capas = new List<Capa>();
        @AuraEnabled public String otherRecords; @AuraEnabled public String sOther;
        @AuraEnabled public String closedBy; @AuraEnabled public Datetime closedOn;
    }

    private static Field_Action__c load(Id recordId) {
        return [SELECT Id, Name, Status__c, Action_Type__c, Recall_Class__c, Depth__c, Part__r.Name, Part__r.compliancequest__Part_Number__c,
                       Scope__c, Scope_Status__c, Scope_Confirmed_By__r.Name, Scope_Confirmed_On__c,
                       Strategy_Status__c, Strategy_Confirmed_On__c, Check_Level__c, Check_Percent__c, Check_By__c,
                       Recovery_Status__c, Verdict__c, Next_Step__c, Verdict_By__r.Name, Verdict_On__c,
                       Closure_Summary__c, CAPA__c, CAPA__r.Name, Other_Records__c, Closed_By__r.Name, Closed_On__c
                FROM Field_Action__c WHERE Id = :recordId];
    }
    private static void openForChange(Field_Action__c fa) {
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (fa.Strategy_Status__c != 'Confirmed') { throw new AuraHandledException('Confirm the strategy first.'); }
    }
    /** Any change to recovery reopens a confirmed verdict. */
    private static void reopen(Field_Action__c fa) {
        if (fa.Recovery_Status__c != 'In Progress') { update new Field_Action__c(Id = fa.Id, Recovery_Status__c = 'In Progress'); }
    }
    private static Decimal targetOf(Field_Action__c fa) {
        switch on fa.Check_Level__c {
            when 'Level A' { return 100; }
            when 'Level B' { return fa.Check_Percent__c == null ? 100 : fa.Check_Percent__c; }
            when 'Level C' { return 10; }
            when 'Level D' { return 2; }
            when 'Level E' { return 0; }
            when else { return 100; }
        }
    }
    private static Decimal n(Decimal d) { return d == null ? 0 : d; }
    private static String day(Date d) { return d == null ? '' : d.format(); }

    /** The step statuses the workspace rail needs: strategy, recovery, verdict, status. */
    @AuraEnabled
    public static Map<String, String> railStatus(Id recordId) {
        Field_Action__c fa = [SELECT Status__c, Strategy_Status__c, Recovery_Status__c, Verdict__c FROM Field_Action__c WHERE Id = :recordId];
        return new Map<String, String>{ 'strategy' => fa.Strategy_Status__c, 'recovery' => fa.Recovery_Status__c,
            'verdict' => fa.Verdict__c, 'status' => fa.Status__c };
    }

    // ---------------------------------------------------------------- read

    @AuraEnabled
    public static View getView(Id recordId) {
        Field_Action__c fa = load(recordId);
        View v = new View();
        v.id = fa.Id; v.name = fa.Name; v.status = fa.Status__c; v.closed = fa.Status__c == 'Closed';
        v.strategyConfirmed = fa.Strategy_Status__c == 'Confirmed';
        v.recovery = fa.Recovery_Status__c; v.verdict = fa.Verdict__c; v.nextStep = fa.Next_Step__c;
        v.verdictBy = fa.Verdict_By__r?.Name; v.verdictOn = fa.Verdict_On__c;
        v.action = fa.Action_Type__c; v.depth = fa.Depth__c; v.level = fa.Check_Level__c; v.target = targetOf(fa); v.checkBy = fa.Check_By__c;
        v.summary = fa.Closure_Summary__c; v.capaId = fa.CAPA__c; v.capaName = fa.CAPA__r?.Name; v.otherRecords = fa.Other_Records__c;
        v.closedBy = fa.Closed_By__r?.Name; v.closedOn = fa.Closed_On__c;

        // 1. recovery by lot
        List<String> lotNames = new List<String>();
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c, Units_Shipped__c, Units_Returned__c, Units_Destroyed__c, Units_Corrected__c
                                      FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true ORDER BY Lot_Number__c]) {
            LotRec x = new LotRec();
            x.id = l.Id; x.lot = l.Lot_Number__c; x.shipped = l.Units_Shipped__c; x.returned = l.Units_Returned__c;
            x.destroyed = l.Units_Destroyed__c; x.corrected = l.Units_Corrected__c;
            Decimal back = n(x.returned) + n(x.destroyed) + n(x.corrected);
            if (x.shipped != null) {
                v.shippedKnown = true;
                x.field = x.shipped - back > 0 ? x.shipped - back : 0;
                Integer p = x.shipped > 0 ? (back * 100 / x.shipped).setScale(0, System.RoundingMode.FLOOR).intValue() : 100;
                x.pct = p > 100 ? 100 : p;
                v.shipped += x.shipped; v.recovered += Math.min(back, x.shipped);
            }
            v.lots.add(x); lotNames.add(x.lot);
        }

        // 2. customers
        for (Field_Action_Customer__c c : [SELECT Id, Customer_Name__c, Units__c, Lots__c, Status__c, Follow_Ups__c, Responded_On__c
                                           FROM Field_Action_Customer__c WHERE Field_Action__c = :recordId ORDER BY CreatedDate]) {
            Cust x = new Cust();
            x.id = c.Id; x.name = c.Customer_Name__c; x.units = c.Units__c; x.lots = c.Lots__c; x.status = c.Status__c == null ? 'Sent' : c.Status__c;
            x.followUps = c.Follow_Ups__c; x.respondedOn = c.Responded_On__c;
            v.customers.add(x); v.total++;
            if (x.status == 'Acknowledged') { v.acked++; }
        }
        v.targetMet = v.target == 0 || (v.total > 0 && v.acked * 100 >= v.target * v.total);

        // 3. held stock
        for (Field_Action_Hold__c h : [SELECT Id, Lot_Number__c, Kind__c, Item__c, Disposition__c, Reason__c FROM Field_Action_Hold__c
                                       WHERE Field_Action__c = :recordId AND Held__c = true ORDER BY Kind__c DESC, Lot_Number__c]) {
            HoldDisp x = new HoldDisp();
            x.id = h.Id; x.lot = h.Lot_Number__c; x.kind = h.Kind__c; x.item = h.Item__c; x.disposition = h.Disposition__c; x.reason = h.Reason__c;
            x.suggested = h.Kind__c == CqFieldActionStrategy.FINISHED ? 'Scrap' : 'Return to Supplier';
            v.holds.add(x);
            if (h.Disposition__c != null) { v.decided++; }
        }
        Map<String, Decimal> onHand = new Map<String, Decimal>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c, Units_On_Hand__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId]) {
            onHand.put(l.Lot_Number__c, l.Units_On_Hand__c);
        }
        for (HoldDisp x : v.holds) { x.onHand = onHand.get(x.lot); }

        // 4. CQ.AI on the verdict
        Decimal inField = v.shipped - v.recovered;
        List<String> gaps = new List<String>();
        if (v.total == 0) { gaps.add('no customers are listed yet'); }
        else if (!v.targetMet) {
            Integer left = v.total - v.acked;
            gaps.add(left + ' customer' + (left == 1 ? ' has' : 's have') + ' not acknowledged');
        }
        if (v.shippedKnown && inField > 0) { gaps.add(inField.intValue() + ' unit' + (inField == 1 ? ' is' : 's are') + ' still in the field'); }
        if (v.decided < v.holds.size()) { gaps.add((v.holds.size() - v.decided) + ' held lot' + (v.holds.size() - v.decided == 1 ? ' has' : 's have') + ' no disposition'); }
        if (gaps.isEmpty()) {
            v.aiVerdict = EFFECTIVE;
            v.aiLine = 'Effective: ' + (v.target == 0 ? 'no check was needed' : v.acked + ' of ' + v.total + ' customers acknowledged')
                + (v.shippedKnown ? ', every shipped unit is accounted for' : '') + ' and all held stock has a disposition.';
        } else {
            v.aiLine = 'Not yet: ' + String.join(gaps, ', ') + '.'
                + (v.checkBy == null ? '' : ' The ' + (fa.Check_Level__c == null ? 'check' : fa.Check_Level__c + ' check') + ' is due ' + day(v.checkBy) + '.');
        }

        // closure
        closure(v, fa, lotNames, inField);
        if (!v.closed) {
            for (compliancequest__SQX_CAPA__c c : [SELECT Id, Name, compliancequest__Title__c FROM compliancequest__SQX_CAPA__c ORDER BY CreatedDate DESC LIMIT 200]) {
                Capa x = new Capa(); x.id = c.Id; x.name = c.Name; x.title = c.compliancequest__Title__c; v.capas.add(x);
            }
        }
        return v;
    }

    private static void closure(View v, Field_Action__c fa, List<String> lotNames, Decimal inField) {
        Boolean scopeOk = fa.Scope__c == CqFieldActionScope.FULL || fa.Scope_Status__c == 'Confirmed';
        add(v, 'scope', 'Scope confirmed', scopeOk ? lotNames.size() + ' lot' + (lotNames.size() == 1 ? '' : 's')
            + (fa.Scope_Confirmed_By__r == null ? '' : ' · confirmed by ' + fa.Scope_Confirmed_By__r.Name + ', ' + fa.Scope_Confirmed_On__c.date().format())
            : 'The scope is not confirmed', scopeOk ? 'ok' : 'open', true);
        Boolean stratOk = fa.Strategy_Status__c == 'Confirmed';
        add(v, 'strategy', 'Strategy confirmed', stratOk ? (fa.Action_Type__c + (fa.Depth__c == null ? '' : ' to ' + fa.Depth__c.toLowerCase() + ' level')
            + (fa.Check_Level__c == null ? '' : ' · ' + fa.Check_Level__c + (fa.Check_By__c == null ? '' : ' by ' + day(fa.Check_By__c))))
            : 'The strategy is not confirmed', stratOk ? 'ok' : 'open', true);
        add(v, 'notifications', 'Notifications', 'Not Applicable: step not in use yet', 'na', false);
        add(v, 'report', 'Regulatory Report', 'Not Applicable: reported in a separate system', 'na', false);
        String unitsDetail = !v.shippedKnown ? 'Units shipped are not recorded on the Scope step'
            : inField == 0 ? v.recovered.intValue() + ' of ' + v.shipped.intValue() + ' shipped units accounted for'
            : inField.intValue() + ' of ' + v.shipped.intValue() + ' shipped units still in the field';
        add(v, 'units', 'Units recovered', unitsDetail, v.shippedKnown && inField == 0 ? 'ok' : 'open', false);
        add(v, 'customers', 'Customers confirmed', v.total == 0 ? 'No customers listed'
            : v.acked + ' of ' + v.total + ' acknowledged' + (v.targetMet ? ' · ' + (v.level == null ? 'target' : v.level) + ' met' : ' · ' + (v.level == null ? 'target' : v.level) + ' needs ' + v.target.intValue() + '%'),
            v.targetMet ? 'ok' : 'open', true);
        add(v, 'holds', 'Held stock decided', v.holds.isEmpty() ? 'No stock was held' : v.decided + ' of ' + v.holds.size() + ' lots' + dispSummary(v),
            v.decided == v.holds.size() ? 'ok' : 'open', true);
        Boolean verdictOk = fa.Recovery_Status__c == 'Confirmed' && fa.Verdict__c == EFFECTIVE;
        add(v, 'verdict', 'Effectiveness verdict', verdictOk ? 'Effective · confirmed by ' + fa.Verdict_By__r?.Name + ', ' + fa.Verdict_On__c?.date().format()
            : fa.Verdict__c == NOT_EFFECTIVE && fa.Verdict_On__c != null ? 'Not Effective: ' + fa.Next_Step__c : 'No verdict confirmed yet', verdictOk ? 'ok' : 'open', true);
        add(v, 'capa', 'CAPA linked', fa.CAPA__c == null ? 'Choose the CAPA that root cause and prevention continue in' : fa.CAPA__r.Name, fa.CAPA__c != null ? 'ok' : 'open', true);
        v.canClose = !v.closed;
        for (Check c : v.checks) { if (c.state == 'open' && c.blocks) { v.canClose = false; } }

        // CQ.AI's draft of the closing summary
        String part = fa.Part__r == null ? 'the product' : fa.Part__r.compliancequest__Part_Number__c;
        String act = fa.Action_Type__c == CqFieldActionStrategy.REMOVAL ? 'removed' : fa.Action_Type__c == CqFieldActionStrategy.CORRECTION ? 'corrected' : 'issued an advisory notice for';
        List<String> s = new List<String>();
        s.add(fa.Name + ' ' + act + ' ' + part + ' from ' + (lotNames.size() == 1 ? 'lot ' : 'lots ') + String.join(lotNames, ', ')
            + (fa.Depth__c == null ? '' : ' at ' + fa.Depth__c.toLowerCase() + ' level') + (fa.Recall_Class__c == null ? '' : ' (' + fa.Recall_Class__c + ')') + '.');
        if (v.shippedKnown) {
            Decimal r = 0, d = 0, c = 0;
            for (LotRec x : v.lots) { r += n(x.returned); d += n(x.destroyed); c += n(x.corrected); }
            List<String> how = new List<String>();
            if (r > 0) { how.add(r.intValue() + ' returned'); }
            if (d > 0) { how.add(d.intValue() + ' destroyed on site'); }
            if (c > 0) { how.add(c.intValue() + ' corrected'); }
            s.add(v.recovered.intValue() + ' of ' + v.shipped.intValue() + ' shipped units are accounted for' + (how.isEmpty() ? '' : ': ' + String.join(how, ', ')) + '.');
        }
        if (v.total > 0) {
            s.add(v.acked + ' of ' + v.total + ' customers acknowledged' + (v.targetMet ? ', meeting' : ', short of') + ' the ' + (v.level == null ? '' : v.level + ' ') + 'check.');
        }
        if (!v.holds.isEmpty() && v.decided > 0) { s.add('Held stock' + dispSummary(v) + '.'); }
        if (fa.Verdict__c != null && fa.Verdict_On__c != null) { s.add('The field action was ' + fa.Verdict__c.toLowerCase() + '.'); }
        if (fa.CAPA__c != null) { s.add('Root cause and prevention continue in ' + fa.CAPA__r.Name + '.'); }
        v.sSummary = String.join(s, ' ');

        // other records: the nonconformances and complaints behind the reviews, and nonconformances on held component lots
        Set<String> other = new Set<String>();
        for (Field_Action_Review__c r : [SELECT Nonconformance__r.Name, Complaint__r.Name FROM Field_Action_Review__c WHERE Field_Action__c = :fa.Id]) {
            if (r.Nonconformance__r != null) { other.add(r.Nonconformance__r.Name); }
            if (r.Complaint__r != null) { other.add(r.Complaint__r.Name); }
        }
        for (HoldDisp h : v.holds) {
            if (h.reason != null && h.reason.startsWith('NC ')) { other.add(h.reason.substringBetween('NC ', ' ')); }
        }
        other.remove(null);
        List<String> o = new List<String>(other); o.sort();
        v.sOther = String.join(o, ', ');
    }
    private static String dispSummary(View v) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (HoldDisp h : v.holds) {
            if (h.disposition == null) { continue; }
            counts.put(h.disposition, (counts.containsKey(h.disposition) ? counts.get(h.disposition) : 0) + 1);
        }
        if (counts.isEmpty()) { return ''; }
        List<String> parts = new List<String>();
        for (String k : new List<String>{ 'Scrap', 'Rework', 'Return to Supplier', 'Release' }) {
            if (!counts.containsKey(k)) { continue; }
            String verb = k == 'Scrap' ? 'scrapped' : k == 'Rework' ? 'reworked' : k == 'Return to Supplier' ? 'returned to supplier' : 'released';
            parts.add(counts.get(k) + ' ' + verb);
        }
        return ': ' + String.join(parts, ', ');
    }
    private static void add(View v, String key, String text, String detail, String state, Boolean blocks) {
        Check c = new Check(); c.key = key; c.text = text; c.detail = detail; c.state = state; c.blocks = blocks; v.checks.add(c);
    }

    // ---------------------------------------------------------------- recovery saves

    /** Units returned, destroyed and corrected for one lot in scope. */
    @AuraEnabled
    public static View saveLot(Id recordId, Id rowId, Decimal returned, Decimal destroyed, Decimal corrected) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        Field_Action_Lot__c l = [SELECT Id, Field_Action__c, Units_Shipped__c FROM Field_Action_Lot__c WHERE Id = :rowId];
        if (l.Field_Action__c != recordId) { throw new AuraHandledException('That lot belongs to another field action.'); }
        if (n(returned) < 0 || n(destroyed) < 0 || n(corrected) < 0) { throw new AuraHandledException('Units cannot be negative.'); }
        if (l.Units_Shipped__c != null && n(returned) + n(destroyed) + n(corrected) > l.Units_Shipped__c) {
            throw new AuraHandledException('That is more than the ' + l.Units_Shipped__c.intValue() + ' units shipped.');
        }
        update new Field_Action_Lot__c(Id = rowId, Units_Returned__c = returned, Units_Destroyed__c = destroyed, Units_Corrected__c = corrected);
        reopen(fa);
        return getView(recordId);
    }

    @AuraEnabled
    public static View addCustomer(Id recordId, String name, Decimal units, String lots) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        if (String.isBlank(name)) { throw new AuraHandledException('Enter the customer name.'); }
        insert new Field_Action_Customer__c(Field_Action__c = recordId, Customer_Name__c = name.trim().left(255), Units__c = units,
            Lots__c = String.isBlank(lots) ? null : lots.left(255), Status__c = 'Sent', Follow_Ups__c = 0);
        reopen(fa);
        return getView(recordId);
    }

    /** Changes one customer: status (Sent, Acknowledged, No reply), a follow-up, or removes it. */
    @AuraEnabled
    public static View setCustomer(Id recordId, Id customerId, String change) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        Field_Action_Customer__c c = [SELECT Id, Field_Action__c, Follow_Ups__c FROM Field_Action_Customer__c WHERE Id = :customerId];
        if (c.Field_Action__c != recordId) { throw new AuraHandledException('That customer belongs to another field action.'); }
        if (change == 'remove') { delete c; }
        else if (change == 'followup') { update new Field_Action_Customer__c(Id = c.Id, Follow_Ups__c = n(c.Follow_Ups__c) + 1); }
        else if (change == 'Sent' || change == 'Acknowledged' || change == 'No reply') {
            update new Field_Action_Customer__c(Id = c.Id, Status__c = change, Responded_On__c = change == 'Acknowledged' ? Date.today() : null);
        } else { throw new AuraHandledException('Unknown change: ' + change); }
        reopen(fa);
        return getView(recordId);
    }

    @AuraEnabled
    public static View setDisposition(Id recordId, Id holdId, String disposition) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        Field_Action_Hold__c h = [SELECT Id, Field_Action__c FROM Field_Action_Hold__c WHERE Id = :holdId];
        if (h.Field_Action__c != recordId) { throw new AuraHandledException('That hold belongs to another field action.'); }
        update new Field_Action_Hold__c(Id = holdId, Disposition__c = String.isBlank(disposition) ? null : disposition, Disposition_On__c = null);
        reopen(fa);
        return getView(recordId);
    }

    /** The verdict as a draft: Effective, or Not Effective with what happens next. */
    @AuraEnabled
    public static View saveVerdict(Id recordId, String verdict, String nextStep) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        update new Field_Action__c(Id = recordId, Verdict__c = String.isBlank(verdict) ? null : verdict,
            Next_Step__c = verdict == NOT_EFFECTIVE && String.isNotBlank(nextStep) ? nextStep : null,
            Recovery_Status__c = 'In Progress', Verdict_By__c = null, Verdict_On__c = null);
        return getView(recordId);
    }

    /**
     * Confirm Verdict. Effective needs every held lot decided and the check level met; it fixes the dispositions and
     * opens Closure. Not Effective records what happens next; extending the check moves the check-by date 30 days on.
     */
    @AuraEnabled
    public static View confirmVerdict(Id recordId) {
        Field_Action__c fa = load(recordId);
        openForChange(fa);
        View v = getView(recordId);
        Datetime now = Datetime.now();
        if (fa.Verdict__c == null) { throw new AuraHandledException('Choose a verdict.'); }
        if (v.decided < v.holds.size()) { throw new AuraHandledException('Choose what happens to all held stock.'); }
        Field_Action__c up = new Field_Action__c(Id = recordId, Verdict_By__c = UserInfo.getUserId(), Verdict_On__c = now);
        if (fa.Verdict__c == EFFECTIVE) {
            if (!v.targetMet) { throw new AuraHandledException(v.total == 0 ? 'Add the customers that received these lots.' : (fa.Check_Level__c == null ? 'The check' : fa.Check_Level__c) + ' needs ' + v.target.intValue() + '% of customers to acknowledge.'); }
            up.Recovery_Status__c = 'Confirmed';
            List<Field_Action_Hold__c> hs = new List<Field_Action_Hold__c>();
            for (HoldDisp h : v.holds) { hs.add(new Field_Action_Hold__c(Id = h.id, Disposition_On__c = now)); }
            update hs;
        } else {
            if (fa.Next_Step__c == null) { throw new AuraHandledException('Choose what happens next.'); }
            up.Recovery_Status__c = 'In Progress';
            if (fa.Next_Step__c == EXTEND) { up.Check_By__c = (fa.Check_By__c == null ? Date.today() : fa.Check_By__c).addDays(30); }
        }
        update up;
        return getView(recordId);
    }

    // ---------------------------------------------------------------- closure saves

    @AuraEnabled
    public static View saveClosure(Id recordId, String field, String value) {
        Field_Action__c fa = load(recordId);
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        Field_Action__c up = new Field_Action__c(Id = recordId);
        String val = String.isBlank(value) ? null : value;
        switch on field {
            when 'summary' { up.Closure_Summary__c = val; }
            when 'capa' { up.CAPA__c = val; }
            when 'other' { up.Other_Records__c = val == null ? null : val.left(255); }
            when else { throw new AuraHandledException('Unknown field: ' + field); }
        }
        update up;
        return getView(recordId);
    }

    /** Close Field Action: every blocking checklist item done, then the status is Closed and the record takes no more changes. */
    @AuraEnabled
    public static View closeFieldAction(Id recordId, String summary) {
        View v = getView(recordId);
        if (v.closed) { throw new AuraHandledException('This field action is already closed.'); }
        List<String> pending = new List<String>();
        for (Check c : v.checks) { if (c.state == 'open' && c.blocks) { pending.add(c.text.toLowerCase()); } }
        if (!pending.isEmpty()) { throw new AuraHandledException('Before closing: ' + String.join(pending, ', ') + '.'); }
        String text = String.isNotBlank(summary) ? summary : String.isNotBlank(v.summary) ? v.summary : v.sSummary;
        update new Field_Action__c(Id = recordId, Status__c = 'Closed', Closure_Summary__c = text,
            Other_Records__c = String.isNotBlank(v.otherRecords) ? v.otherRecords : v.sOther == null ? null : v.sOther.left(255),
            Closed_By__c = UserInfo.getUserId(), Closed_On__c = Datetime.now());
        return getView(recordId);
    }
}

/**
 * CqSignalJob: finds signals for field action. A signal is a pattern across complaints, nonconformances
 * and Field Action Reviews. Each run tests the active Signal Rules, creates a Signal the first time a
 * pattern appears and updates the same Signal after that, so its strength rises, holds or fades.
 *
 * Scoring follows the standard deviation model from the site scorecard: a score from 0 to 1 where
 * 0.05 and 0.20 are Watch, 0.60 is Assess and 1.00 is Escalate. A rule in Fixed mode uses its Raise and
 * Escalate thresholds. A rule in Baseline mode uses the average and standard deviation of monthly counts
 * over its lookback, with limits at 1, 2 and 3 standard deviations.
 *
 * Runs on a schedule, or on demand through run() or POST /services/apexrest/cqsignals/run.
 */
@RestResource(urlMapping='/cqsignals/run')
global with sharing class CqSignalJob implements Schedulable {
    private static final Set<String> DEAD = new Set<String>{ 'void', 'voided', 'cancelled', 'canceled' };

    private class Finding {
        String code; String key; Id partId; String lot; String summary; String label;
        Decimal value = 0; Decimal rate; Decimal baseline; Decimal sd;
        String strength; Decimal score; Decimal raise; Decimal escalate; Decimal next;
        Set<Id> complaints = new Set<Id>(); Set<Id> ncs = new Set<Id>(); Set<Id> reviews = new Set<Id>();
        Map<Id, String> numbers = new Map<Id, String>();
    }

    global void execute(SchedulableContext sc) { run(); }

    @HttpPost
    global static String runRest() { return run(); }

    @AuraEnabled
    public static String run() {
        Map<String, Signal_Rule__c> rules = new Map<String, Signal_Rule__c>();
        for (Signal_Rule__c r : [SELECT Id, Name, Code__c, Window_Days__c, Raise_Threshold__c, Escalate_Threshold__c,
                                        Threshold_Mode__c, Lookback_Months__c
                                 FROM Signal_Rule__c WHERE Active__c = true]) {
            rules.put(r.Code__c, r);
        }
        List<Finding> found = new List<Finding>();
        if (rules.containsKey('CROSS_SOURCE')) { found.addAll(crossSource()); }
        if (rules.containsKey('CLUSTER')) { found.addAll(cluster(rules.get('CLUSTER'))); }
        if (rules.containsKey('SHARED_COMPONENT_LOT')) { found.addAll(sharedComponentLot(rules.get('SHARED_COMPONENT_LOT'))); }
        return save(found, rules);
    }

    private static Boolean alive(String status) { return status == null || !DEAD.contains(status.toLowerCase()); }
    private static String plural(Integer n, String word) { return n + ' ' + word + (n == 1 ? '' : 's'); }
    private static Integer days(Signal_Rule__c r, Integer fallback) { return r.Window_Days__c == null ? fallback : r.Window_Days__c.intValue(); }

    // ---- Cross-Source: a complaint and a nonconformance on the same lot
    private static List<Finding> crossSource() {
        Map<String, Finding> byLot = new Map<String, Finding>();
        for (compliancequest__SQX_Complaint__c c : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c, compliancequest__Status__c
                FROM compliancequest__SQX_Complaint__c WHERE compliancequest__Lot_Number__c != null LIMIT 5000]) {
            if (!alive(c.compliancequest__Status__c)) { continue; }
            Finding f = forLot(byLot, c.compliancequest__Lot_Number__c, c.compliancequest__SQX_Part__c);
            f.complaints.add(c.Id); f.numbers.put(c.Id, c.Name);
        }
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c, compliancequest__Status__c
                FROM compliancequest__SQX_Nonconformance__c WHERE compliancequest__Lot_Number__c != null LIMIT 5000]) {
            if (!alive(n.compliancequest__Status__c)) { continue; }
            Finding f = forLot(byLot, n.compliancequest__Lot_Number__c, n.compliancequest__SQX_Part__c);
            f.ncs.add(n.Id); f.numbers.put(n.Id, n.Name);
        }
        List<Finding> out = new List<Finding>();
        for (Finding f : byLot.values()) {
            if (f.complaints.isEmpty() || f.ncs.isEmpty()) { continue; }
            f.code = 'CROSS_SOURCE'; f.key = 'CROSS_SOURCE|' + f.lot;
            f.value = f.complaints.size();
            f.summary = 'A problem found in the plant has also reached a customer on lot ' + f.lot;
            f.label = plural(f.complaints.size(), 'complaint') + ' and ' + plural(f.ncs.size(), 'nonconformance') + ' on lot ' + f.lot;
            out.add(f);
        }
        return out;
    }
    private static Finding forLot(Map<String, Finding> byLot, String lot, Id partId) {
        Finding f = byLot.get(lot);
        if (f == null) { f = new Finding(); f.lot = lot; byLot.put(lot, f); }
        if (f.partId == null) { f.partId = partId; }
        return f;
    }

    // ---- Cluster: complaints on the same part within the window
    private static List<Finding> cluster(Signal_Rule__c rule) {
        Integer window = days(rule, 90);
        Datetime since = Datetime.now().addDays(-window);
        Map<Id, Finding> byPart = new Map<Id, Finding>();
        for (compliancequest__SQX_Complaint__c c : [
                SELECT Id, Name, compliancequest__SQX_Part__c, compliancequest__Status__c
                FROM compliancequest__SQX_Complaint__c
                WHERE compliancequest__SQX_Part__c != null AND CreatedDate >= :since LIMIT 5000]) {
            if (!alive(c.compliancequest__Status__c)) { continue; }
            Finding f = byPart.get(c.compliancequest__SQX_Part__c);
            if (f == null) {
                f = new Finding(); f.code = 'CLUSTER'; f.partId = c.compliancequest__SQX_Part__c; f.key = 'CLUSTER|' + f.partId;
                byPart.put(f.partId, f);
            }
            f.complaints.add(c.Id); f.numbers.put(c.Id, c.Name);
        }
        for (Finding f : byPart.values()) {
            f.value = f.complaints.size();
            f.summary = 'Complaints on this part are clustering';
            f.label = plural(f.complaints.size(), 'complaint') + ' on this part in ' + window + ' days';
            if (rule.Threshold_Mode__c == 'Baseline') { baseline(f, rule, window); }
        }
        return byPart.values();
    }

    /** Standard deviation model: average and sample standard deviation of monthly complaint counts over the lookback. */
    private static void baseline(Finding f, Signal_Rule__c rule, Integer window) {
        Integer months = rule.Lookback_Months__c == null ? 12 : rule.Lookback_Months__c.intValue();
        if (months < 2) { return; }
        Date thisMonth = Date.today().toStartOfMonth();
        Date start = thisMonth.addMonths(-months);
        Datetime fromTs = Datetime.newInstance(start, Time.newInstance(0, 0, 0, 0));
        Datetime toTs = Datetime.newInstance(thisMonth, Time.newInstance(0, 0, 0, 0));
        Map<Integer, Integer> perMonth = new Map<Integer, Integer>();
        for (compliancequest__SQX_Complaint__c c : [
                SELECT CreatedDate, compliancequest__Status__c FROM compliancequest__SQX_Complaint__c
                WHERE compliancequest__SQX_Part__c = :f.partId AND CreatedDate >= :fromTs AND CreatedDate < :toTs LIMIT 5000]) {
            if (!alive(c.compliancequest__Status__c)) { continue; }
            Integer k = c.CreatedDate.year() * 12 + c.CreatedDate.month();
            perMonth.put(k, (perMonth.containsKey(k) ? perMonth.get(k) : 0) + 1);
        }
        List<Decimal> counts = new List<Decimal>(); Decimal total = 0;
        for (Integer i = 0; i < months; i++) {
            Date d = start.addMonths(i);
            Integer k = d.year() * 12 + d.month();
            Decimal n = perMonth.containsKey(k) ? perMonth.get(k) : 0;
            counts.add(n); total += n;
        }
        Decimal avg = total / months; Decimal squares = 0;
        for (Decimal n : counts) { squares += (n - avg) * (n - avg); }
        f.baseline = avg;
        f.sd = Decimal.valueOf(Math.sqrt((squares / (months - 1)).doubleValue()));
        f.rate = f.value * 30 / window;     // this window's complaints as a monthly figure, to compare with the monthly baseline
    }

    // ---- Shared Component Lot: finished lots with problems that were built from the same component lot
    private static List<Finding> sharedComponentLot(Signal_Rule__c rule) {
        List<Finding> out = new List<Finding>();
        Datetime since = Datetime.now().addDays(-days(rule, 180));
        Map<Id, String> lotByBatch = new Map<Id, String>();
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name, Batch__c FROM compliancequest__SQX_Lot_Info__c WHERE Batch__c != null LIMIT 5000]) {
            lotByBatch.put(l.Batch__c, l.Name);
        }
        if (lotByBatch.isEmpty()) { return out; }
        Set<String> lots = new Set<String>(lotByBatch.values());
        Map<String, Finding> problems = new Map<String, Finding>();     // finished lot -> the records on it
        for (compliancequest__SQX_Complaint__c c : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c, compliancequest__Status__c
                FROM compliancequest__SQX_Complaint__c WHERE compliancequest__Lot_Number__c IN :lots AND CreatedDate >= :since LIMIT 5000]) {
            if (!alive(c.compliancequest__Status__c)) { continue; }
            Finding f = forLot(problems, c.compliancequest__Lot_Number__c, c.compliancequest__SQX_Part__c);
            f.complaints.add(c.Id); f.numbers.put(c.Id, c.Name);
        }
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, Name, compliancequest__Lot_Number__c, compliancequest__SQX_Part__c, compliancequest__Status__c
                FROM compliancequest__SQX_Nonconformance__c WHERE compliancequest__Lot_Number__c IN :lots AND CreatedDate >= :since LIMIT 5000]) {
            if (!alive(n.compliancequest__Status__c)) { continue; }
            Finding f = forLot(problems, n.compliancequest__Lot_Number__c, null);
            f.ncs.add(n.Id); f.numbers.put(n.Id, n.Name);
        }
        Map<String, Set<String>> lotsByComponent = new Map<String, Set<String>>();
        Map<String, String> componentPart = new Map<String, String>();
        for (cqext__CQEBR_Batch_Sub_Step_Measurement__c m : [
                SELECT cqext__Lot_Number__c, cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c,
                       cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c
                FROM cqext__CQEBR_Batch_Sub_Step_Measurement__c
                WHERE cqext__Lot_Number__c != null
                  AND cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c IN :lotByBatch.keySet() LIMIT 10000]) {
            String finished = lotByBatch.get(m.cqext__CQEBR_Batch_Sub_Step__r.cqext__CQEBR_Batch_Step__r.cqext__CQEBR_Batch__c);
            if (finished == null || !problems.containsKey(finished)) { continue; }
            String comp = m.cqext__Lot_Number__c;
            if (!lotsByComponent.containsKey(comp)) { lotsByComponent.put(comp, new Set<String>()); }
            lotsByComponent.get(comp).add(finished);
            if (m.cqext__CQEBR_Operator_Product__r != null) { componentPart.put(comp, m.cqext__CQEBR_Operator_Product__r.compliancequest__Part_Number__c); }
        }
        for (String comp : lotsByComponent.keySet()) {
            List<String> finished = new List<String>(lotsByComponent.get(comp));
            if (finished.size() < 2) { continue; }
            finished.sort();
            Finding f = new Finding();
            f.code = 'SHARED_COMPONENT_LOT'; f.key = 'SHARED_COMPONENT_LOT|' + comp; f.lot = comp; f.value = finished.size();
            for (String lot : finished) {
                Finding p = problems.get(lot);
                if (f.partId == null) { f.partId = p.partId; }
                f.complaints.addAll(p.complaints); f.ncs.addAll(p.ncs); f.numbers.putAll(p.numbers);
            }
            String part = componentPart.get(comp);
            f.summary = 'Lots ' + String.join(finished, ', ') + ' have problems and were built from the same component lot';
            f.label = finished.size() + ' finished lots with problems used component lot ' + comp + (part == null ? '' : ' (' + part + ')');
            out.add(f);
        }
        return out;
    }

    // ---- strength and score
    private static void grade(Finding f, Signal_Rule__c r) {
        if (r.Threshold_Mode__c == 'Baseline' && f.sd != null && f.sd > 0) {
            Decimal l1 = f.baseline + f.sd; Decimal l2 = l1 + f.sd; Decimal l3 = l2 + f.sd; Decimal x = f.rate;
            f.raise = l2; f.escalate = l3;
            if (x < f.baseline) { return; }
            if (x >= l3) { f.strength = 'Escalate'; f.score = 1; }
            else if (x >= l2) { f.strength = 'Assess'; f.score = 0.60 * x / l3; f.next = l3; }
            else if (x >= l1) { f.strength = 'Watch'; f.score = 0.20 * x / l2; f.next = l2; }
            else { f.strength = 'Watch'; f.score = 0.05 * x / l1; f.next = l1; }
            f.label += ' · ' + x.setScale(1) + ' a month against a normal ' + f.baseline.setScale(1);
            return;
        }
        Decimal raise = r.Raise_Threshold__c == null ? 1 : r.Raise_Threshold__c;
        Decimal esc = r.Escalate_Threshold__c == null ? raise : r.Escalate_Threshold__c;
        f.raise = raise; f.escalate = esc;
        if (f.value >= esc) { f.strength = 'Escalate'; f.score = 1; }
        else if (f.value >= raise) { f.strength = 'Assess'; f.score = 0.60; f.next = esc; }
        else if (f.value * 2 >= raise) { f.strength = 'Watch'; f.score = 0.20; f.next = raise; }
    }

    // ---- create or update the signals, let old ones fade, link the records behind each
    private static String save(List<Finding> found, Map<String, Signal_Rule__c> rules) {
        Map<String, Signal__c> existing = new Map<String, Signal__c>();
        for (Signal__c s : [SELECT Id, Group_Key__c, Value__c, Strength__c, Status__c, Trend__c FROM Signal__c WHERE Status__c != 'Closed' LIMIT 5000]) {
            existing.put(s.Group_Key__c, s);
        }
        List<Finding> graded = new List<Finding>();
        Map<Id, Integer> strongByPart = new Map<Id, Integer>();
        for (Finding f : found) {
            grade(f, rules.get(f.code));
            if (f.strength == null) { continue; }
            graded.add(f);
            if (f.strength != 'Watch' && f.partId != null) {
                strongByPart.put(f.partId, (strongByPart.containsKey(f.partId) ? strongByPart.get(f.partId) : 0) + 1);
            }
        }
        Datetime now = Datetime.now();
        List<Signal__c> ups = new List<Signal__c>();
        Integer created = 0;
        for (Finding f : graded) {
            // two or more signals at Assess on the same part count as Escalate
            if (f.strength == 'Assess' && f.partId != null && strongByPart.get(f.partId) >= 2) { f.strength = 'Escalate'; }
            Signal__c old = existing.get(f.key);
            Signal__c s = new Signal__c(
                Group_Key__c = f.key, Rule__c = rules.get(f.code).Id, Summary__c = f.summary.left(255), Part__c = f.partId,
                Lot_Number__c = f.lot, Value__c = f.value, Value_Label__c = f.label.left(255), Raise_Threshold__c = f.raise,
                Escalate_Threshold__c = f.escalate, Score__c = f.score == null ? null : f.score.setScale(2), Baseline__c = f.baseline,
                Next_Threshold__c = f.next, Strength__c = f.strength, Last_Updated__c = now);
            if (old == null) {
                s.First_Seen__c = now; s.Status__c = 'New'; s.Trend__c = 'Rising'; created++;
            } else {
                Decimal was = old.Value__c == null ? 0 : old.Value__c;
                s.Trend__c = f.value > was ? 'Rising' : f.value < was ? 'Fading' : 'Steady';
                if (old.Status__c == 'Dismissed' && f.value > was) { s.Status__c = 'New'; }   // the data got worse: reopen
            }
            ups.add(s);
        }
        upsert ups Signal__c.Group_Key__c;

        Set<String> seen = new Set<String>();
        for (Finding f : graded) { seen.add(f.key); }
        List<Signal__c> fading = new List<Signal__c>();
        for (Signal__c s : existing.values()) {
            if (seen.contains(s.Group_Key__c) || s.Status__c == 'Dismissed') { continue; }
            if (s.Strength__c == 'Watch' && s.Trend__c == 'Fading') { s.Status__c = 'Closed'; }
            else { s.Strength__c = 'Watch'; s.Trend__c = 'Fading'; }
            s.Last_Updated__c = now;
            fading.add(s);
        }
        update fading;

        Map<String, Id> idByKey = new Map<String, Id>();
        for (Signal__c s : ups) { idByKey.put(s.Group_Key__c, s.Id); }
        Map<Id, Set<Id>> linked = new Map<Id, Set<Id>>();
        for (Signal_Event__c e : [SELECT Signal__c, Complaint__c, Nonconformance__c, Field_Action_Review__c
                                  FROM Signal_Event__c WHERE Signal__c IN :idByKey.values() LIMIT 10000]) {
            if (!linked.containsKey(e.Signal__c)) { linked.put(e.Signal__c, new Set<Id>()); }
            Set<Id> ids = linked.get(e.Signal__c);
            if (e.Complaint__c != null) { ids.add(e.Complaint__c); }
            if (e.Nonconformance__c != null) { ids.add(e.Nonconformance__c); }
            if (e.Field_Action_Review__c != null) { ids.add(e.Field_Action_Review__c); }
        }
        List<Signal_Event__c> events = new List<Signal_Event__c>();
        for (Finding f : graded) {
            Id sid = idByKey.get(f.key);
            Set<Id> have = linked.containsKey(sid) ? linked.get(sid) : new Set<Id>();
            for (Id c : f.complaints) { if (!have.contains(c)) { events.add(new Signal_Event__c(Signal__c = sid, Complaint__c = c, Record_Number__c = f.numbers.get(c))); } }
            for (Id n : f.ncs) { if (!have.contains(n)) { events.add(new Signal_Event__c(Signal__c = sid, Nonconformance__c = n, Record_Number__c = f.numbers.get(n))); } }
            for (Id r : f.reviews) { if (!have.contains(r)) { events.add(new Signal_Event__c(Signal__c = sid, Field_Action_Review__c = r, Record_Number__c = f.numbers.get(r))); } }
        }
        insert events;
        return ups.size() + ' signals (' + created + ' new), ' + fading.size() + ' fading or closed, ' + events.size() + ' records linked';
    }
}

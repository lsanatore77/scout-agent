/**
 * CqInvestigationChanges: the What Changed step of the CQ.AI Investigation workspace.
 *
 * getChanges() gathers every change CQ holds around the start of the problem, for the NC's part:
 *   - change orders on the part (Effective Date, else Target Completion Date, else Submitted Date);
 *   - controlled documents on the part (Effective Date, else Date Issued);
 *   - part revisions (the latest one is always shown, so "no revision since June" is visible);
 *   - supplier deviations on the part and on its bill of materials components, in effect across the window;
 *   - the affected lots (the NC's lot and its impacted lots) with their manufacturing date;
 *   - the NC's equipment and its last calibration;
 *   - changes added by hand on the investigation (Investigation_Change__c).
 * The start date is the NC's Occurrence Date, else its Aware Date, else the day it was created; the window runs
 * the given number of days before it. Each change gets a rating by rule (CQ.AI wording comes later):
 * Could Explain It (in the 14 days before the start; for a supplier deviation, started in them), Worth a Look
 * (earlier in the window, a deviation in effect since before it, or equipment), The Affected Lot, or Unlikely (unchanged).
 *
 * addChange() saves a change found by hand; addHypothesis() turns a change into an Open hypothesis (H1, H2 ...).
 */
public with sharing class CqInvestigationChanges {
    public static final Integer CLOSE_DAYS = 14;
    public static final String COULD = 'Could Explain It';
    public static final String WORTH = 'Worth a Look';
    public static final String UNLIKELY = 'Unlikely';
    public static final String AFFECTED = 'The Affected Lot';

    public class Item {
        @AuraEnabled public String key; @AuraEnabled public String kind; @AuraEnabled public Id recordId;
        @AuraEnabled public String name; @AuraEnabled public String whatChanged; @AuraEnabled public String foundIn;
        @AuraEnabled public Date day; @AuraEnabled public Date untilDay; @AuraEnabled public Boolean inEffect = false;
        @AuraEnabled public String rating; @AuraEnabled public Boolean onTimeline = false;
        @AuraEnabled public String category; @AuraEnabled public Boolean byHand = false; @AuraEnabled public Integer hypothesis;
    }
    public class Hyp {
        @AuraEnabled public Id id; @AuraEnabled public Integer num; @AuraEnabled public String title;
        @AuraEnabled public String category; @AuraEnabled public String status; @AuraEnabled public String source;
    }
    public class View {
        @AuraEnabled public Date startDate; @AuraEnabled public String startFrom; @AuraEnabled public Integer days;
        @AuraEnabled public Date windowStart; @AuraEnabled public String partNumber;
        @AuraEnabled public List<Item> items = new List<Item>();
        @AuraEnabled public List<Hyp> hypotheses = new List<Hyp>();
        @AuraEnabled public List<String> categories = new List<String>();
        @AuraEnabled public List<String> changeCategories = new List<String>();
    }

    @AuraEnabled
    public static View getChanges(Id recordId, Integer days) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        View v = new View();
        v.days = days == null || days < 1 ? 30 : Math.min(days, 365);
        for (Schema.PicklistEntry p : Investigation_Hypothesis__c.Category__c.getDescribe().getPicklistValues()) { if (p.isActive()) { v.categories.add(p.getValue()); } }
        for (Schema.PicklistEntry p : Investigation_Change__c.Category__c.getDescribe().getPicklistValues()) { if (p.isActive()) { v.changeCategories.add(p.getValue()); } }

        compliancequest__SQX_Investigation__c inv = [SELECT compliancequest__SQX_Nonconformance__c FROM compliancequest__SQX_Investigation__c WHERE Id = :invId WITH USER_MODE];
        Id ncId = inv.compliancequest__SQX_Nonconformance__c;
        Id partId; Id equipmentId; Set<String> lots = new Set<String>();
        if (ncId != null) {
            compliancequest__SQX_Nonconformance__c nc = [
                SELECT compliancequest__Occurrence_Date__c, compliancequest__Aware_Date__c, CreatedDate, compliancequest__SQX_Part__c,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c, compliancequest__SQX_Equipment__c, compliancequest__Lot_Number__c
                FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId WITH USER_MODE];
            if (nc.compliancequest__Occurrence_Date__c != null) { v.startDate = toDate(nc.compliancequest__Occurrence_Date__c); v.startFrom = 'Occurrence Date'; }
            else if (nc.compliancequest__Aware_Date__c != null) { v.startDate = toDate(nc.compliancequest__Aware_Date__c); v.startFrom = 'Aware Date'; }
            else { v.startDate = nc.CreatedDate.date(); v.startFrom = 'Created Date'; }
            partId = nc.compliancequest__SQX_Part__c;
            v.partNumber = nc.compliancequest__SQX_Part__r == null ? null : nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            equipmentId = nc.compliancequest__SQX_Equipment__c;
            if (String.isNotBlank(nc.compliancequest__Lot_Number__c)) { lots.add(nc.compliancequest__Lot_Number__c); }
            for (compliancequest__SQX_NC_Impacted_Product__c ip : [SELECT compliancequest__Lot_Number__c FROM compliancequest__SQX_NC_Impacted_Product__c
                    WHERE compliancequest__SQX_Nonconformance__c = :ncId AND compliancequest__Lot_Number__c != null WITH USER_MODE]) {
                lots.add(ip.compliancequest__Lot_Number__c);
            }
        } else {
            v.startDate = Date.today(); v.startFrom = 'Today';
        }
        v.windowStart = v.startDate.addDays(-v.days);
        String partName = v.partNumber == null ? 'the part' : v.partNumber;

        if (partId != null) {
            // change orders on the part
            for (compliancequest__SQX_Change_Order__c c : [
                    SELECT Id, Name, compliancequest__Title__c, compliancequest__Effective_Date__c, compliancequest__Target_Completion_Date__c, compliancequest__Submitted_Date__c
                    FROM compliancequest__SQX_Change_Order__c WHERE compliancequest__SQX_Product__c = :partId WITH USER_MODE]) {
                Date d = firstDate(new List<Object>{ c.compliancequest__Effective_Date__c, c.compliancequest__Target_Completion_Date__c, c.compliancequest__Submitted_Date__c });
                Item it = dated(v, 'change', c.Id, c.Name, c.compliancequest__Title__c, 'Change order on ' + partName, d);
                if (it != null) { it.category = 'Method'; v.items.add(it); }
            }
            // controlled documents on the part
            for (compliancequest__SQX_Controlled_Document__c c : [
                    SELECT Id, Name, compliancequest__Title__c, compliancequest__Description__c, compliancequest__Effective_Date__c, compliancequest__Date_Issued__c
                    FROM compliancequest__SQX_Controlled_Document__c WHERE compliancequest__SQX_Part__c = :partId WITH USER_MODE]) {
                Date d = firstDate(new List<Object>{ c.compliancequest__Effective_Date__c, c.compliancequest__Date_Issued__c });
                String what = c.compliancequest__Title__c;
                String desc2 = c.compliancequest__Description__c == null ? null : c.compliancequest__Description__c.removeStartIgnoreCase('SAMPLE DATA. ');
                if (String.isNotBlank(desc2)) { what = what + ': ' + desc2.left(1).toLowerCase() + desc2.substring(1); }
                Item it = dated(v, 'document', c.Id, docName(c.Name), what, 'Controlled document on ' + partName, d);
                if (it != null) { it.category = 'Method'; v.items.add(it); }
            }
            // the latest part revision, always shown
            List<cqext__CQPLM_Part_Revision__c> revs = [
                SELECT Id, Name, cqext__Effective_Date__c FROM cqext__CQPLM_Part_Revision__c
                WHERE cqext__CQPLM_Part__c = :partId WITH USER_MODE ORDER BY cqext__Effective_Date__c DESC NULLS LAST LIMIT 1];
            if (!revs.isEmpty()) {
                cqext__CQPLM_Part_Revision__c r = revs[0];
                Date d = toDate(r.cqext__Effective_Date__c);
                Item it = base('revision', r.Id, revName(r.Name, partName), null, 'Part revision', d);
                Boolean recent = d != null && d >= v.windowStart && d <= v.startDate;
                it.whatChanged = recent ? 'New part revision' : (d == null ? 'No revision date recorded' : 'No part revision since ' + monthName(d));
                it.rating = recent ? (d >= v.startDate.addDays(-CLOSE_DAYS) ? COULD : WORTH) : UNLIKELY;
                it.onTimeline = recent;
                it.category = 'Materials';
                v.items.add(it);
            }
            // supplier deviations on the part and its bill of materials components (walked down up to 5 levels), in effect during the window
            Map<Id, String> parts = new Map<Id, String>{ partId => partName };
            Set<Id> level = new Set<Id>{ partId };
            for (Integer depth = 0; depth < 5 && !level.isEmpty(); depth++) {
                Set<Id> next = new Set<Id>();
                for (cqext__CQPLM_Assembly_line_Item__c li : [
                        SELECT cqext__CQPLM_Part__c, cqext__CQPLM_Part__r.Name, cqext__CQPLM_Part__r.compliancequest__Part_Number__c
                        FROM cqext__CQPLM_Assembly_line_Item__c
                        WHERE cqext__CQPLM_Assembly__r.cqext__CQPLM_Part_Revision__r.cqext__CQPLM_Part__c IN :level AND cqext__CQPLM_Part__c != null WITH USER_MODE]) {
                    if (parts.containsKey(li.cqext__CQPLM_Part__c)) { continue; }
                    parts.put(li.cqext__CQPLM_Part__c, li.cqext__CQPLM_Part__r.Name + ' (' + li.cqext__CQPLM_Part__r.compliancequest__Part_Number__c + ')');
                    next.add(li.cqext__CQPLM_Part__c);
                }
                level = next;
            }
            Set<Id> partIds = parts.keySet();
            for (compliancequest__SQX_Supplier_Deviation__c s : [
                    SELECT Id, Name, compliancequest__SQX_Part__c, compliancequest__Effective_Date__c, compliancequest__Expiration_Date__c
                    FROM compliancequest__SQX_Supplier_Deviation__c WHERE compliancequest__SQX_Part__c IN :partIds WITH USER_MODE]) {
                Date from1 = toDate(s.compliancequest__Effective_Date__c);
                Date to1 = toDate(s.compliancequest__Expiration_Date__c);
                if (from1 == null || from1 > v.startDate) { continue; }
                if (to1 != null && to1 < v.windowStart) { continue; }
                Boolean component = s.compliancequest__SQX_Part__c != partId;
                Item it = base('deviation', s.Id, s.Name, 'Supplier deviation on ' + parts.get(s.compliancequest__SQX_Part__c),
                    component ? 'Supplier deviation on a component' : 'Supplier deviation on ' + partName, from1);
                it.untilDay = to1; it.inEffect = true; it.rating = from1 >= v.startDate.addDays(-CLOSE_DAYS) ? COULD : WORTH; it.category = 'Materials';
                v.items.add(it);
            }
        }
        // the affected lots
        if (!lots.isEmpty()) {
            for (compliancequest__SQX_Lot_Info__c l : [
                    SELECT Id, Name, compliancequest__Manufacturing_Date__c FROM compliancequest__SQX_Lot_Info__c WHERE Name IN :lots WITH USER_MODE]) {
                Date d = toDate(l.compliancequest__Manufacturing_Date__c);
                Item it = base('lot', l.Id, 'Lot ' + l.Name, 'The affected lot' + (d == null ? '' : ', built ' + monthDay(d)), 'Lot on ' + partName, d);
                it.rating = AFFECTED;
                it.onTimeline = d != null && d >= v.windowStart && d <= v.startDate;
                v.items.add(it);
            }
        }
        // the NC's equipment and its last calibration
        if (equipmentId != null) {
            compliancequest__SQX_Equipment__c e = [SELECT Id, Name, compliancequest__Equipment_Description__c FROM compliancequest__SQX_Equipment__c WHERE Id = :equipmentId WITH USER_MODE];
            List<compliancequest__SQX_Calibration__c> cals = [
                SELECT Id, Name, compliancequest__Calibration_Date__c, compliancequest__Next_Calibration_Date__c
                FROM compliancequest__SQX_Calibration__c WHERE compliancequest__SQX_Equipment__c = :equipmentId
                WITH USER_MODE ORDER BY compliancequest__Calibration_Date__c DESC NULLS LAST LIMIT 1];
            if (cals.isEmpty()) {
                Item it = base('calibration', e.Id, e.Name + ' Calibration', 'No calibration on record for ' + e.Name, 'Equipment on the NC', null);
                it.rating = WORTH; it.category = 'Machine';
                v.items.add(it);
            } else {
                compliancequest__SQX_Calibration__c c = cals[0];
                Date last = toDate(c.compliancequest__Calibration_Date__c);
                Date next = toDate(c.compliancequest__Next_Calibration_Date__c);
                Boolean overdue = next != null && next < v.startDate;
                String what = 'Last calibrated ' + (last == null ? 'on an unknown date' : monthDay(last)) + ' (' + c.Name + ')'
                    + (next == null ? '' : (overdue ? '; it was due ' + monthDay(next) + ' and is overdue' : '; next due ' + monthDay(next)));
                Item it = base('calibration', e.Id, e.Name + ' Calibration', what, 'Equipment on the NC', last);
                it.rating = overdue ? COULD : WORTH; it.category = 'Machine';
                it.onTimeline = last != null && last >= v.windowStart && last <= v.startDate;
                v.items.add(it);
            }
        }
        // changes added by hand
        for (Investigation_Change__c c : [
                SELECT Id, Name, What_Changed__c, Change_Date__c, Category__c, Where_Found__c, Reference__c
                FROM Investigation_Change__c WHERE Investigation__c = :invId WITH USER_MODE ORDER BY Change_Date__c]) {
            Item it = base('manual', c.Id, c.Name, c.What_Changed__c, String.isBlank(c.Where_Found__c) ? 'Added by hand' : c.Where_Found__c, c.Change_Date__c);
            it.byHand = true;
            it.category = c.Category__c == 'Other' ? null : c.Category__c;
            it.rating = rate(v, c.Change_Date__c);
            it.onTimeline = c.Change_Date__c != null && c.Change_Date__c >= v.windowStart && c.Change_Date__c <= v.startDate;
            v.items.add(it);
        }
        // hypotheses, and which changes they came from
        Map<String, Integer> fromSource = new Map<String, Integer>();
        for (Investigation_Hypothesis__c h : [
                SELECT Id, Number__c, Title__c, Category__c, Status__c, Source_Name__c, Source_Record_Id__c, Investigation_Change__c
                FROM Investigation_Hypothesis__c WHERE Investigation__c = :invId WITH USER_MODE ORDER BY Number__c]) {
            Hyp x = new Hyp();
            x.id = h.Id; x.num = h.Number__c == null ? null : h.Number__c.intValue(); x.title = h.Title__c;
            x.category = h.Category__c; x.status = h.Status__c; x.source = h.Source_Name__c;
            v.hypotheses.add(x);
            String src = h.Investigation_Change__c != null ? String.valueOf(h.Investigation_Change__c) : h.Source_Record_Id__c;
            if (src != null && !fromSource.containsKey(src.left(15))) { fromSource.put(src.left(15), x.num); }
        }
        for (Item it : v.items) {
            if (it.recordId != null && fromSource.containsKey(String.valueOf(it.recordId).left(15))) { it.hypothesis = fromSource.get(String.valueOf(it.recordId).left(15)); }
        }
        v.items.sort(new ByRating());
        return v;
    }

    /** A dated change: kept when it falls in the window (up to the start date), rated by how close it is. */
    static Item dated(View v, String kind, Id id, String name, String what, String foundIn, Date d) {
        if (d == null || d < v.windowStart || d > v.startDate) { return null; }
        Item it = base(kind, id, name, what, foundIn, d);
        it.rating = rate(v, d);
        it.onTimeline = true;
        return it;
    }
    static String rate(View v, Date d) {
        if (d == null) { return WORTH; }
        if (d > v.startDate) { return UNLIKELY; }
        if (d >= v.startDate.addDays(-CLOSE_DAYS)) { return COULD; }
        return d >= v.windowStart ? WORTH : UNLIKELY;
    }
    static Item base(String kind, Id id, String name, String what, String foundIn, Date d) {
        Item it = new Item();
        it.key = kind + ':' + (id == null ? name : String.valueOf(id));
        it.kind = kind; it.recordId = id; it.name = name; it.whatChanged = what; it.foundIn = foundIn; it.day = d;
        return it;
    }

    public class ByRating implements Comparator<Item> {
        Map<String, Integer> order = new Map<String, Integer>{ COULD => 0, AFFECTED => 1, WORTH => 2, UNLIKELY => 3 };
        public Integer compare(Item a, Item b) {
            Integer ra = order.containsKey(a.rating) ? order.get(a.rating) : 9;
            Integer rb = order.containsKey(b.rating) ? order.get(b.rating) : 9;
            if (ra != rb) { return ra - rb; }
            if (a.day == b.day) { return 0; }
            if (a.day == null) { return 1; }
            if (b.day == null) { return -1; }
            return a.day < b.day ? -1 : 1;
        }
    }

    /** Saves a change found by hand. Payload: whatChanged, changeDate (yyyy-mm-dd), category, whereFound, reference. */
    @AuraEnabled
    public static Id addChange(Id recordId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(payload);
        String what = str(m.get('whatChanged'));
        String day = str(m.get('changeDate'));
        String cat = str(m.get('category'));
        if (String.isBlank(what)) { throw new AuraHandledException('Say what changed.'); }
        if (String.isBlank(day)) { throw new AuraHandledException('Enter when it changed.'); }
        if (String.isBlank(cat)) { throw new AuraHandledException('Choose a category.'); }
        Investigation_Change__c c = new Investigation_Change__c(Investigation__c = invId, What_Changed__c = what.trim().left(255),
            Change_Date__c = Date.valueOf(day), Category__c = cat, Where_Found__c = str(m.get('whereFound')), Reference__c = str(m.get('reference')));
        try { insert as user c; } catch (DmlException e) { throw new AuraHandledException('The change was not saved: ' + e.getDmlMessage(0)); }
        return c.Id;
    }

    /** Makes an Open hypothesis from a change. Payload: title, category, sourceId, sourceName. Returns its number. */
    @AuraEnabled
    public static Integer addHypothesis(Id recordId, String payload) {
        Id invId = CqInvestigationWorkspace.investigationFor(recordId);
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(payload);
        String title = str(m.get('title'));
        String cat = str(m.get('category'));
        if (String.isBlank(title)) { throw new AuraHandledException('Say what the possible cause is.'); }
        if (String.isBlank(cat)) { throw new AuraHandledException('Choose a category.'); }
        String sourceId = str(m.get('sourceId'));
        Investigation_Hypothesis__c h = new Investigation_Hypothesis__c(Investigation__c = invId, Title__c = title.trim().left(255),
            Category__c = cat, Status__c = 'Open', Source_Name__c = str(m.get('sourceName')));
        if (String.isNotBlank(sourceId)) {
            Id sid = (Id) sourceId;
            if (sid.getSObjectType() == Investigation_Change__c.SObjectType) { h.Investigation_Change__c = sid; } else { h.Source_Record_Id__c = sid; }
        }
        AggregateResult[] top = [SELECT MAX(Number__c) n FROM Investigation_Hypothesis__c WHERE Investigation__c = :invId WITH USER_MODE];
        Decimal n = (Decimal) top[0].get('n');
        h.Number__c = (n == null ? 0 : n) + 1;
        try { insert as user h; } catch (DmlException e) { throw new AuraHandledException('The hypothesis was not saved: ' + e.getDmlMessage(0)); }
        return h.Number__c.intValue();
    }

    static Date toDate(Object o) {
        if (o == null) { return null; }
        // CQ keeps many of these dates as date-times at midnight GMT, so read them in GMT
        if (o instanceof Datetime) { return ((Datetime) o).dateGmt(); }
        return (Date) o;
    }
    static Date firstDate(List<Object> xs) {
        for (Object o : xs) { if (o != null) { return toDate(o); } }
        return null;
    }
    static String revName(String name, String partName) {
        // "CardioFlow ... RX[A]" reads better as "PTCA-1000 Rev A"
        if (name != null && name.endsWith(']') && name.contains('[')) { return partName + ' Rev ' + name.substringAfterLast('[').removeEnd(']'); }
        return name;
    }
    static String docName(String name) {
        // "WI-2210[D]" reads better as "WI-2210 Rev D"
        if (name != null && name.endsWith(']') && name.contains('[')) { return name.substringBeforeLast('[') + ' Rev ' + name.substringAfterLast('[').removeEnd(']'); }
        return name;
    }
    static final List<String> MONTHS = new List<String>{ 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' };
    static final List<String> MONTHS_LONG = new List<String>{ 'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December' };
    static String monthDay(Date d) { return MONTHS[d.month() - 1] + ' ' + d.day(); }
    static String monthName(Date d) { return MONTHS_LONG[d.month() - 1]; }
    static String str(Object o) { return o == null ? null : String.valueOf(o); }
}

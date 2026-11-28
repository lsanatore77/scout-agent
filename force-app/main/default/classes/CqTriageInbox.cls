/**
 * CqTriageInbox: the Triage Inbox (list view style, decided with Lou 25 Nov 2026; mockup "Triage Inbox Mockup").
 *
 * Two views. Waiting for Triage: the NCs in Triage owned by a triage queue the person belongs to, oldest first, with
 * flags (a possible duplicate on the same lot, a repeat on the same part). My NCs: the open NCs the person owns past
 * Draft, by stage, with where each stands (in triage, or the nearest due date).
 *
 * Take Ownership takes one NC at a time and the person stays on the inbox. Only queue members who can own NCs (CQ's
 * Can Own NC permission) can take one. If someone took it first, the answer says who. There is no release back to the
 * queue: an NC is reassigned, by its owner, to another queue member who can own NCs.
 *
 * Salesforce administrators see every NC queue (Lou: admins can override, as always).
 *
 * Queue membership is direct membership of the queue (a user in the queue's member list); members added through a
 * public group or role are not followed yet.
 */
public with sharing class CqTriageInbox {
    public static final String NC = 'compliancequest__SQX_Nonconformance__c';
    public static final String CAN_OWN = 'CQ_Can_Own_NC_Custom_Permission';
    public static final Set<String> DONE = new Set<String>{ 'Closed', 'Void', 'Complete' };
    public static final Set<String> NOT_MINE_STAGES = new Set<String>{ 'Draft', 'Closed' };
    /** My NCs keeps a Complete NC: CQ completes an NC when it moves to Verification, and its owner still closes it. */
    public static final Set<String> MINE_DONE = new Set<String>{ 'Closed', 'Void' };
    public static final Integer OLD_DAYS = 7;          // waiting this long shows in amber
    public static final Integer REPEAT_DAYS = 90;      // other NCs on the same part this recently make a repeat
    public static final Integer SOON_DAYS = 7;         // a due date this close counts as due soon

    /** Tests set this to stand in for CQ's Can Own NC permission. */
    @TestVisible static Boolean canOwnOverride;
    /** Tests set this to stand in for queue membership. */
    @TestVisible static Set<Id> queuesOverride;
    /** Tests set this to move today forward: CQ refuses due dates in the past, so an overdue NC cannot be made directly. */
    @TestVisible static Date todayOverride;
    public static Date today() { return todayOverride != null ? todayOverride : Date.today(); }

    public class Row {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title;
        @AuraEnabled public String part; @AuraEnabled public String type;
        @AuraEnabled public String stage; @AuraEnabled public String stageLabel;
        @AuraEnabled public String queue;
        @AuraEnabled public Integer waitDays;             // days since it was created (it went to Triage then)
        @AuraEnabled public String waiting;               // Today, 1 day, 9 days
        @AuraEnabled public Boolean old = false;
        @AuraEnabled public String status;                // My NCs: where it stands
        @AuraEnabled public Boolean statusWarn = false;
        @AuraEnabled public Integer dueDays;              // My NCs: days to the nearest open due date; negative = overdue
        @AuraEnabled public List<String> flags = new List<String>();
        @AuraEnabled public String primary;               // what the button says: Continue Triage, Disposition, Investigation, Implementation, Verification
        @AuraEnabled public String openPart;              // Disposition / Investigate: which side the NC page opens on (its c__part)
    }
    public class Inbox {
        @AuraEnabled public Boolean triager = false;      // in a triage queue (or an admin) and can own NCs
        @AuraEnabled public Boolean inQueue = false;
        @AuraEnabled public Boolean canOwn = false;
        @AuraEnabled public Boolean admin = false;
        @AuraEnabled public List<String> queues = new List<String>();
        @AuraEnabled public List<Row> waiting = new List<Row>();
        @AuraEnabled public List<Row> mine = new List<Row>();
    }
    public class Taken {
        @AuraEnabled public Boolean ok = false;
        @AuraEnabled public String message;
        @AuraEnabled public Id id; @AuraEnabled public String name;
    }
    public class Person {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public Integer open = 0;
    }

    // ------------------------------------------------------------ the inbox

    @AuraEnabled
    public static Inbox load() {
        Inbox x = new Inbox();
        x.admin = isAdmin();
        x.canOwn = canOwn(UserInfo.getUserId());
        Map<Id, String> qs = myQueues();
        x.inQueue = !qs.isEmpty();
        x.queues = qs.values();
        x.queues.sort();
        x.triager = x.inQueue && x.canOwn;
        if (x.inQueue) { x.waiting = waitingRows(qs); }
        x.mine = mineRows();
        return x;
    }

    /** The NCs in Triage owned by these queues, oldest first, with their flags. */
    public static List<Row> waitingRows(Map<Id, String> queues) {
        List<Row> out = new List<Row>();
        if (queues == null || queues.isEmpty()) { return out; }
        Set<Id> qids = queues.keySet();
        List<compliancequest__SQX_Nonconformance__c> ncs = [
            SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Type__c, compliancequest__Record_Stage__c,
                   compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.Name, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                   compliancequest__Lot_Number__c, OwnerId, CreatedDate
            FROM compliancequest__SQX_Nonconformance__c
            WHERE compliancequest__Record_Stage__c = 'Triage' AND OwnerId IN :qids AND compliancequest__Status__c NOT IN :DONE
            ORDER BY CreatedDate ASC LIMIT 200];
        Map<Id, List<String>> flags = flagsFor(ncs);
        for (compliancequest__SQX_Nonconformance__c n : ncs) {
            Row r = base(n);
            r.queue = queues.get(n.OwnerId);
            r.flags = flags.containsKey(n.Id) ? flags.get(n.Id) : new List<String>();
            r.primary = 'Take Ownership';
            out.add(r);
        }
        return out;
    }

    /** The open NCs the running user owns past Draft, by stage, with where each stands. */
    public static List<Row> mineRows() {
        List<Row> out = new List<Row>();
        Id me = UserInfo.getUserId();
        for (compliancequest__SQX_Nonconformance__c n : [
                SELECT Id, Name, compliancequest__NC_Title__c, compliancequest__Type__c, compliancequest__Record_Stage__c,
                       compliancequest__SQX_Part__c, compliancequest__SQX_Part__r.Name, compliancequest__SQX_Part__r.compliancequest__Part_Number__c,
                       CreatedDate, compliancequest__Due_Date__c,
                       compliancequest__Due_Date_Investigation__c, compliancequest__Completion_Date_Investigation__c,
                       compliancequest__Due_Date_Disposition__c, compliancequest__Completion_Date_Disposition__c,
                       compliancequest__Due_Date_Containment__c, compliancequest__Completion_Date_Containment__c
                FROM compliancequest__SQX_Nonconformance__c
                WHERE OwnerId = :me AND compliancequest__Status__c NOT IN :MINE_DONE AND compliancequest__Record_Stage__c NOT IN :NOT_MINE_STAGES
                ORDER BY CreatedDate ASC LIMIT 200]) {
            Row r = base(n);
            standing(r, n);
            next(r, n);
            out.add(r);
        }
        // by stage in the order an NC moves through them, then the most pressing first
        List<RowSort> s = new List<RowSort>();
        for (Row r : out) { s.add(new RowSort(r)); }
        s.sort();
        out.clear();
        for (RowSort x : s) { out.add(x.r); }
        return out;
    }

    private class RowSort implements Comparable {
        Row r;
        RowSort(Row r) { this.r = r; }
        public Integer compareTo(Object o) {
            Row b = ((RowSort) o).r;
            Integer sa = stageOrder(r.stage), sb = stageOrder(b.stage);
            if (sa != sb) { return sa - sb; }
            Integer da = r.dueDays == null ? 100000 : r.dueDays, db = b.dueDays == null ? 100000 : b.dueDays;
            if (da != db) { return da - db; }
            return (b.waitDays == null ? 0 : b.waitDays) - (r.waitDays == null ? 0 : r.waitDays);
        }
    }
    /**
     * The button names the next step (Lou, 28 Nov): Continue Triage, Continue Disposition or Continue Investigation (in
     * Disposition / Investigate, whichever is still open; when both are, the one due first, the disposition on a tie),
     * Continue Implementation, Continue Verification. In Disposition / Investigate it opens the NC page on that side.
     */
    @TestVisible
    private static void next(Row r, compliancequest__SQX_Nonconformance__c n) {
        String st = n.compliancequest__Record_Stage__c;
        if (st == 'Triage') { r.primary = 'Continue Triage'; return; }
        if (st == 'Implement') { r.primary = 'Continue Implementation'; return; }
        if (st == 'Verification') { r.primary = 'Continue Verification'; return; }
        if (st == 'Disposition_Investigate') {
            Boolean dispOpen = n.compliancequest__Completion_Date_Disposition__c == null;
            Boolean invOpen = n.compliancequest__Completion_Date_Investigation__c == null;
            Boolean inv = invOpen && (!dispOpen || dueFirst(n.compliancequest__Due_Date_Investigation__c, n.compliancequest__Due_Date_Disposition__c));
            r.openPart = inv ? 'investigation' : 'disposition';
            r.primary = inv ? 'Continue Investigation' : 'Continue Disposition';
            return;
        }
        r.primary = 'Open';
    }
    private static Boolean dueFirst(Date a, Date b) { return a != null && (b == null || a < b); }

    public static Integer stageOrder(String s) {
        Integer i = new List<String>{ 'Triage', 'Disposition_Investigate', 'Implement', 'Verification' }.indexOf(s);
        return i < 0 ? 9 : i;
    }
    public static String stageLabel(String s) {
        if (s == 'Disposition_Investigate') { return 'Disposition / Investigate'; }
        return s == null ? '' : s.replace('_', ' ');
    }

    private static Row base(compliancequest__SQX_Nonconformance__c n) {
        Row r = new Row();
        r.id = n.Id; r.name = n.Name; r.title = n.compliancequest__NC_Title__c; r.type = n.compliancequest__Type__c;
        r.stage = n.compliancequest__Record_Stage__c; r.stageLabel = stageLabel(r.stage);
        if (n.compliancequest__SQX_Part__r != null) {
            String pn = n.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            r.part = String.isNotBlank(pn) ? pn : n.compliancequest__SQX_Part__r.Name;
        }
        r.waitDays = n.CreatedDate == null ? 0 : n.CreatedDate.date().daysBetween(today());
        r.waiting = r.waitDays <= 0 ? 'Today' : r.waitDays == 1 ? '1 day' : r.waitDays + ' days';
        r.old = r.waitDays >= OLD_DAYS;
        return r;
    }

    /** Where an owned NC stands: in triage for how long, or its nearest open due date (overdue in amber). */
    private static void standing(Row r, compliancequest__SQX_Nonconformance__c n) {
        if (r.stage == 'Triage') {
            r.status = r.waitDays <= 0 ? 'In triage since today' : 'In triage ' + r.waiting;
            r.statusWarn = r.old;
            return;
        }
        if (r.stage == 'Verification') { r.status = 'Waiting to be closed'; return; }
        String what; Date due;
        List<Object[]> dues = new List<Object[]>{
            new Object[]{ 'Containment', n.compliancequest__Due_Date_Containment__c, n.compliancequest__Completion_Date_Containment__c },
            new Object[]{ 'Disposition', n.compliancequest__Due_Date_Disposition__c, n.compliancequest__Completion_Date_Disposition__c },
            new Object[]{ 'Investigation', n.compliancequest__Due_Date_Investigation__c, n.compliancequest__Completion_Date_Investigation__c }
        };
        for (Object[] d : dues) {
            Date dd = (Date) d[1];
            if (dd == null || d[2] != null) { continue; }
            if (due == null || dd < due) { due = dd; what = (String) d[0]; }
        }
        if (due == null && n.compliancequest__Due_Date__c != null) { due = n.compliancequest__Due_Date__c; what = 'NC'; }
        if (due == null) { r.status = stageLabel(r.stage); return; }
        r.dueDays = today().daysBetween(due);
        if (r.dueDays < 0) {
            Integer late = -r.dueDays;
            r.status = what + ' overdue ' + late + (late == 1 ? ' day' : ' days');
            r.statusWarn = true;
        } else if (r.dueDays == 0) {
            r.status = what + ' due today';
            r.statusWarn = true;
        } else {
            r.status = what + ' due ' + Datetime.newInstance(due, Time.newInstance(12, 0, 0, 0)).format('MMM d');
        }
    }

    /** Possible duplicate: another open NC on the same lot. Repeat: other NCs on the same part in the last 90 days. */
    private static Map<Id, List<String>> flagsFor(List<compliancequest__SQX_Nonconformance__c> ncs) {
        Map<Id, List<String>> out = new Map<Id, List<String>>();
        Set<String> lots = new Set<String>(); Set<Id> parts = new Set<Id>(); Set<Id> ids = new Set<Id>();
        for (compliancequest__SQX_Nonconformance__c n : ncs) {
            ids.add(n.Id);
            if (String.isNotBlank(n.compliancequest__Lot_Number__c)) { lots.add(n.compliancequest__Lot_Number__c); }
            if (n.compliancequest__SQX_Part__c != null) { parts.add(n.compliancequest__SQX_Part__c); }
        }
        Map<String, List<compliancequest__SQX_Nonconformance__c>> byLot = new Map<String, List<compliancequest__SQX_Nonconformance__c>>();
        if (!lots.isEmpty()) {
            for (compliancequest__SQX_Nonconformance__c o : [
                    SELECT Id, Name, compliancequest__Lot_Number__c, CreatedDate FROM compliancequest__SQX_Nonconformance__c
                    WHERE compliancequest__Lot_Number__c IN :lots AND compliancequest__Status__c NOT IN :DONE
                    ORDER BY CreatedDate ASC LIMIT 500]) {
                String k = o.compliancequest__Lot_Number__c.toUpperCase();
                if (!byLot.containsKey(k)) { byLot.put(k, new List<compliancequest__SQX_Nonconformance__c>()); }
                byLot.get(k).add(o);
            }
        }
        Map<Id, Integer> byPart = new Map<Id, Integer>();
        Map<Id, List<Id>> partNcs = new Map<Id, List<Id>>();
        if (!parts.isEmpty()) {
            Datetime since = Datetime.now().addDays(-REPEAT_DAYS);
            for (compliancequest__SQX_Nonconformance__c o : [
                    SELECT Id, compliancequest__SQX_Part__c FROM compliancequest__SQX_Nonconformance__c
                    WHERE compliancequest__SQX_Part__c IN :parts AND CreatedDate >= :since LIMIT 2000]) {
                if (!partNcs.containsKey(o.compliancequest__SQX_Part__c)) { partNcs.put(o.compliancequest__SQX_Part__c, new List<Id>()); }
                partNcs.get(o.compliancequest__SQX_Part__c).add(o.Id);
            }
        }
        for (compliancequest__SQX_Nonconformance__c n : ncs) {
            List<String> f = new List<String>();
            if (String.isNotBlank(n.compliancequest__Lot_Number__c)) {
                List<compliancequest__SQX_Nonconformance__c> same = byLot.get(n.compliancequest__Lot_Number__c.toUpperCase());
                if (same != null) {
                    for (compliancequest__SQX_Nonconformance__c o : same) {
                        if (o.Id != n.Id && o.CreatedDate <= n.CreatedDate) { f.add('Possible duplicate of ' + o.Name); break; }
                    }
                }
            }
            if (n.compliancequest__SQX_Part__c != null && partNcs.containsKey(n.compliancequest__SQX_Part__c)) {
                Integer others = partNcs.get(n.compliancequest__SQX_Part__c).size() - (partNcs.get(n.compliancequest__SQX_Part__c).contains(n.Id) ? 1 : 0);
                if (others > 0) { f.add('Repeat on this part'); }
            }
            out.put(n.Id, f);
        }
        return out;
    }

    // ------------------------------------------------------------ take ownership

    /** Takes one NC from a queue the person belongs to. Stays on the inbox: the answer says what happened. */
    @AuraEnabled
    public static Taken takeOwnership(Id ncId) {
        Taken t = new Taken();
        if (ncId == null) { throw new AuraHandledException('Choose an NC to take.'); }
        Id me = UserInfo.getUserId();
        if (!canOwn(me)) { throw new AuraHandledException('You need CQ\'s Can Own NC permission to take NCs. Ask your administrator.'); }
        Map<Id, String> qs = myQueues();
        compliancequest__SQX_Nonconformance__c n = new Sys().lockNc(ncId);
        t.id = n.Id; t.name = n.Name;
        if (n.OwnerId == me) { t.ok = true; t.message = n.Name + ' is already yours.'; return t; }
        if (String.valueOf(n.OwnerId).startsWith('005')) {
            t.message = 'Already taken by ' + n.Owner.Name + '.';
            return t;
        }
        if (!qs.containsKey(n.OwnerId)) { throw new AuraHandledException(n.Name + ' is not in one of your triage queues.'); }
        if (n.compliancequest__Record_Stage__c != 'Triage') { throw new AuraHandledException(n.Name + ' is no longer waiting for triage.'); }
        try {
            new Sys().setOwner(ncId, me);
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not let you take ' + n.Name + ': ' + e.getDmlMessage(0));
        }
        t.ok = true;
        t.message = n.Name + ' is yours.';
        return t;
    }

    // ------------------------------------------------------------ reassign

    /** Who the owner can hand the NC to: members of their triage queues who can own NCs, with how many open NCs they own. */
    @AuraEnabled
    public static List<Person> reassignTo(Id ncId) {
        compliancequest__SQX_Nonconformance__c n = [SELECT Id, OwnerId FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (n.OwnerId != UserInfo.getUserId() && !isAdmin()) { throw new AuraHandledException('Only the owner can reassign this NC.'); }
        return candidates(n.OwnerId);
    }

    public static List<Person> candidates(Id except) {
        Set<Id> qids = myQueues().keySet();
        Set<Id> users = new Set<Id>();
        if (!qids.isEmpty()) {
            for (GroupMember g : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId IN :qids]) {
                if (String.valueOf(g.UserOrGroupId).startsWith('005')) { users.add(g.UserOrGroupId); }
            }
        }
        users.remove(except);
        Set<Id> owners = canOwnAll(users);
        Map<Id, Integer> open = new Map<Id, Integer>();
        if (!owners.isEmpty()) {
            for (AggregateResult a : [SELECT OwnerId o, COUNT(Id) n FROM compliancequest__SQX_Nonconformance__c
                                      WHERE OwnerId IN :owners AND compliancequest__Status__c NOT IN :DONE
                                      AND compliancequest__Record_Stage__c NOT IN :NOT_MINE_STAGES GROUP BY OwnerId]) {
                open.put((Id) a.get('o'), (Integer) a.get('n'));
            }
        }
        List<Person> out = new List<Person>();
        // dynamic: this org's static SOQL does not see User.IsActive (as in CqFarCommittee)
        for (SObject u : Database.query('SELECT Id, Name FROM User WHERE Id IN :owners AND IsActive = true ORDER BY Name')) {
            Person p = new Person(); p.id = u.Id; p.name = (String) u.get('Name'); p.open = open.containsKey(u.Id) ? open.get(u.Id) : 0;
            out.add(p);
        }
        return out;
    }

    /** Hands the NC to another queue member who can own NCs; the note goes on the NC's feed. Returns a warning, or null. */
    @AuraEnabled
    public static String reassign(Id ncId, Id userId, String note) {
        compliancequest__SQX_Nonconformance__c n = [SELECT Id, Name, OwnerId FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId];
        if (n.OwnerId != UserInfo.getUserId() && !isAdmin()) { throw new AuraHandledException('Only the owner can reassign this NC.'); }
        Boolean ok = false; String name;
        for (Person p : candidates(n.OwnerId)) { if (p.id == userId) { ok = true; name = p.name; } }
        if (!ok) { throw new AuraHandledException('Choose a member of your triage queue who can own NCs.'); }
        try {
            new Sys().setOwner(ncId, userId);
        } catch (DmlException e) {
            throw new AuraHandledException('CQ did not let you reassign ' + n.Name + ': ' + e.getDmlMessage(0));
        }
        String body = 'Reassigned to ' + name + ' by ' + UserInfo.getName() + '.' + (String.isBlank(note) ? '' : '\n' + note.trim().left(4000));
        try {
            insert new FeedItem(ParentId = ncId, Body = body);
        } catch (Exception e) {
            return 'Reassigned to ' + name + ', but the note could not be added to the NC\'s feed.';
        }
        return null;
    }

    // ------------------------------------------------------------ who

    public static Boolean isAdmin() {
        Id p = UserInfo.getProfileId();
        List<SObject> rows = Database.query('SELECT PermissionsModifyAllData FROM Profile WHERE Id = :p');
        return !rows.isEmpty() && rows[0].get('PermissionsModifyAllData') == true;
    }

    /** The NC queues the running user is a direct member of; every NC queue for an administrator. Id => queue name. */
    public static Map<Id, String> myQueues() {
        Map<Id, String> all = new Map<Id, String>();
        for (QueueSobject q : [SELECT QueueId, Queue.Name FROM QueueSobject WHERE SobjectType = :NC]) { all.put(q.QueueId, q.Queue.Name); }
        if (queuesOverride != null) {
            Map<Id, String> m = new Map<Id, String>();
            for (Id q : queuesOverride) { m.put(q, all.containsKey(q) ? all.get(q) : 'Queue'); }
            return m;
        }
        if (isAdmin()) { return all; }
        Map<Id, String> mine = new Map<Id, String>();
        if (all.isEmpty()) { return mine; }
        for (GroupMember g : [SELECT GroupId FROM GroupMember WHERE GroupId IN :all.keySet() AND UserOrGroupId = :UserInfo.getUserId()]) {
            mine.put(g.GroupId, all.get(g.GroupId));
        }
        return mine;
    }

    public static Boolean canOwn(Id userId) {
        if (canOwnOverride != null && userId == UserInfo.getUserId()) { return canOwnOverride; }
        return canOwnAll(new Set<Id>{ userId }).contains(userId);
    }

    /** The users who hold CQ's Can Own NC permission, through any permission set or group. */
    public static Set<Id> canOwnAll(Set<Id> users) {
        Set<Id> out = new Set<Id>();
        if (users == null || users.isEmpty()) { return out; }
        String cpName = CAN_OWN;
        List<SObject> cp = Database.query('SELECT Id FROM CustomPermission WHERE DeveloperName = :cpName AND NamespacePrefix = \'compliancequest\' LIMIT 1');
        if (cp.isEmpty()) { return out; }
        Id cpId = cp[0].Id;
        for (SObject a : Database.query('SELECT AssigneeId FROM PermissionSetAssignment WHERE AssigneeId IN :users'
                + ' AND PermissionSetId IN (SELECT ParentId FROM SetupEntityAccess WHERE SetupEntityId = :cpId)')) {
            out.add((Id) a.get('AssigneeId'));
        }
        if (canOwnOverride != null && users.contains(UserInfo.getUserId())) {
            if (canOwnOverride) { out.add(UserInfo.getUserId()); } else { out.remove(UserInfo.getUserId()); }
        }
        return out;
    }

    /**
     * The owner change itself, after the checks above: a queue member may not have edit access to a queue's NC (the NC's
     * sharing is Public Read Only), and handing an NC to the next person is the system's job once the rules are met.
     */
    without sharing class Sys {
        compliancequest__SQX_Nonconformance__c lockNc(Id ncId) {
            return [SELECT Id, Name, OwnerId, Owner.Name, compliancequest__Record_Stage__c
                    FROM compliancequest__SQX_Nonconformance__c WHERE Id = :ncId FOR UPDATE];
        }
        void setOwner(Id ncId, Id userId) {
            update new compliancequest__SQX_Nonconformance__c(Id = ncId, OwnerId = userId);
        }
    }
}

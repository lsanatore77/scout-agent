/**
 * CqFieldActionTasks: the recall work on a Field Action, kept as standard Salesforce Tasks (WhatId = the Field Action),
 * so it shows in each owner's My Tasks with reminders. Used by the Recovery and Effectiveness step.
 *  - Recall Task Type says what a task is; Field Action Customer and Lot Number say who and which lot it is about.
 *  - Units on Track return and Confirm destruction tasks add up to the lot's Returned and Destroyed (Confirm correction
 *    to Corrected). A completed Collect response marks the customer Acknowledged; an overdue one marks No reply.
 *  - CQ.AI suggests the tasks a field action still needs, from the strategy and the lot shipments: a notice and a
 *    response per customer, and a return (or correction) per lot shipped to them. The coordinator reviews and creates them.
 */
public with sharing class CqFieldActionTasks {
    public static final String NOTICE = 'Send recall notice';
    public static final String RESPONSE = 'Collect response';
    public static final String RETURN_IT = 'Track return';
    public static final String DESTROY = 'Confirm destruction';
    public static final String CORRECT = 'Confirm correction';
    public static final String OTHER = 'Other';
    public static final String DONE = 'Completed';
    public static final String OPEN = 'Not Started';

    public class TaskRow {
        @AuraEnabled public Id id; @AuraEnabled public String subject; @AuraEnabled public String type; @AuraEnabled public String owner;
        @AuraEnabled public Date due; @AuraEnabled public Boolean done = false; @AuraEnabled public Boolean overdue = false;
        @AuraEnabled public Boolean dueWeek = false; @AuraEnabled public Decimal units; @AuraEnabled public Boolean hasUnits = false;
        @AuraEnabled public String lot; @AuraEnabled public Id customerId;
    }
    public class Suggestion {
        @AuraEnabled public String key; @AuraEnabled public String type; @AuraEnabled public String subject; @AuraEnabled public Id customerId;
        @AuraEnabled public String customer; @AuraEnabled public String lot; @AuraEnabled public Date due;
    }
    public class Person { @AuraEnabled public Id id; @AuraEnabled public String name; }
    public class Board {
        @AuraEnabled public List<TaskRow> tasks = new List<TaskRow>();
        @AuraEnabled public Integer open = 0; @AuraEnabled public Integer completed = 0; @AuraEnabled public Integer overdue = 0; @AuraEnabled public Integer dueWeek = 0;
        @AuraEnabled public List<Suggestion> suggestions = new List<Suggestion>();
        @AuraEnabled public String suggestLine;
        @AuraEnabled public List<Person> people = new List<Person>();
        @AuraEnabled public Id me;
        @AuraEnabled public Map<String, List<String>> lotsByCustomer = new Map<String, List<String>>();
        @AuraEnabled public Map<String, Decimal> shippedByLine = new Map<String, Decimal>();   // customerId|lot -> units shipped
    }

    private static List<Task> tasksOf(Id recordId) {
        return [SELECT Id, Subject, Status, IsClosed, ActivityDate, OwnerId, Owner.Name, Recall_Task_Type__c, Lot_Number__c, Units__c,
                       Field_Action_Customer__c
                FROM Task WHERE WhatId = :recordId ORDER BY ActivityDate NULLS LAST, CreatedDate LIMIT 2000];
    }

    /**
     * Brings the lots' Returned, Destroyed and Corrected, and the customers' status, into line with the tasks.
     * Only lots with units recorded on their tasks, and customers with a response task, are touched, so figures typed
     * before tasks existed stay until a task carries units.
     */
    public static void sync(Id recordId) {
        List<Task> ts = tasksOf(recordId);
        if (ts.isEmpty()) { return; }
        Map<String, Decimal> back = new Map<String, Decimal>(), gone = new Map<String, Decimal>(), fixed = new Map<String, Decimal>();
        Map<Id, Integer> rankOf = new Map<Id, Integer>();
        for (Task t : ts) {
            String lot = t.Lot_Number__c;
            Decimal u = t.Units__c;   // a task with no units yet says nothing about the lot
            if (lot != null && u != null && t.Recall_Task_Type__c == RETURN_IT) { back.put(lot, (back.containsKey(lot) ? back.get(lot) : 0) + u); }
            if (lot != null && u != null && t.Recall_Task_Type__c == DESTROY) { gone.put(lot, (gone.containsKey(lot) ? gone.get(lot) : 0) + u); }
            if (lot != null && u != null && t.Recall_Task_Type__c == CORRECT) { fixed.put(lot, (fixed.containsKey(lot) ? fixed.get(lot) : 0) + u); }
            if (t.Field_Action_Customer__c != null && t.Recall_Task_Type__c == RESPONSE) {
                // Acknowledged beats No reply beats Sent, when a customer has more than one response task
                Integer rank = t.IsClosed ? 3 : (t.ActivityDate != null && t.ActivityDate < Date.today()) ? 2 : 1;
                Integer had = rankOf.get(t.Field_Action_Customer__c);
                if (had == null || rank > had) { rankOf.put(t.Field_Action_Customer__c, rank); }
            }
        }
        List<Field_Action_Lot__c> lotUps = new List<Field_Action_Lot__c>();
        for (Field_Action_Lot__c l : [SELECT Id, Lot_Number__c, Units_Returned__c, Units_Destroyed__c, Units_Corrected__c FROM Field_Action_Lot__c
                                      WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true]) {
            Field_Action_Lot__c up = new Field_Action_Lot__c(Id = l.Id); Boolean change = false;
            if (back.containsKey(l.Lot_Number__c) && back.get(l.Lot_Number__c) != l.Units_Returned__c) { up.Units_Returned__c = back.get(l.Lot_Number__c); change = true; }
            if (gone.containsKey(l.Lot_Number__c) && gone.get(l.Lot_Number__c) != l.Units_Destroyed__c) { up.Units_Destroyed__c = gone.get(l.Lot_Number__c); change = true; }
            if (fixed.containsKey(l.Lot_Number__c) && fixed.get(l.Lot_Number__c) != l.Units_Corrected__c) { up.Units_Corrected__c = fixed.get(l.Lot_Number__c); change = true; }
            if (change) { lotUps.add(up); }
        }
        if (!lotUps.isEmpty()) { update lotUps; }
        if (rankOf.isEmpty()) { return; }
        List<String> states = new List<String>{ '', 'Sent', 'No reply', 'Acknowledged' };
        List<Field_Action_Customer__c> custUps = new List<Field_Action_Customer__c>();
        for (Field_Action_Customer__c c : [SELECT Id, Status__c FROM Field_Action_Customer__c WHERE Id IN :rankOf.keySet()]) {
            String s = states[rankOf.get(c.Id)];
            if (s != c.Status__c) { custUps.add(new Field_Action_Customer__c(Id = c.Id, Status__c = s, Responded_On__c = s == 'Acknowledged' ? Date.today() : null)); }
        }
        if (!custUps.isEmpty()) { update custUps; }
    }

    /** The task board for the Recovery step: tasks, counts, CQ.AI's suggestions and who tasks can go to. */
    public static Board board(Id recordId, Field_Action__c fa, Boolean closed) {
        Board b = new Board();
        b.me = UserInfo.getUserId();
        Date today = Date.today();
        Set<String> have = new Set<String>();
        for (Task t : tasksOf(recordId)) {
            TaskRow x = new TaskRow();
            x.id = t.Id; x.subject = t.Subject; x.type = t.Recall_Task_Type__c; x.owner = t.Owner?.Name; x.due = t.ActivityDate;
            x.done = t.IsClosed; x.units = t.Units__c; x.lot = t.Lot_Number__c; x.customerId = t.Field_Action_Customer__c;
            x.hasUnits = x.type == RETURN_IT || x.type == DESTROY || x.type == CORRECT;
            x.overdue = !x.done && x.due != null && x.due < today;
            x.dueWeek = !x.done && x.due != null && x.due >= today && x.due < today.addDays(7);
            if (x.done) { b.completed++; } else { b.open++; }
            if (x.overdue) { b.overdue++; }
            if (x.dueWeek) { b.dueWeek++; }
            b.tasks.add(x);
            have.add(x.type + '|' + x.customerId + '|' + (x.lot == null ? '' : x.lot));
        }

        // what each customer received, from the lot shipments of the lots in scope
        Set<String> lots = new Set<String>();
        for (Field_Action_Lot__c l : [SELECT Lot_Number__c FROM Field_Action_Lot__c WHERE Field_Action__c = :recordId AND Approved_In_Scope__c = true]) {
            lots.add(l.Lot_Number__c);
        }
        Map<Id, Id> custByAccount = new Map<Id, Id>();
        List<Field_Action_Customer__c> custs = [SELECT Id, Customer__c, Customer_Name__c, Lots__c FROM Field_Action_Customer__c
                                               WHERE Field_Action__c = :recordId ORDER BY Customer_Name__c];
        for (Field_Action_Customer__c c : custs) {
            if (c.Customer__c != null) { custByAccount.put(c.Customer__c, c.Id); }
            List<String> ls = new List<String>();
            if (String.isNotBlank(c.Lots__c)) { for (String s : c.Lots__c.split(',\\s*')) { if (String.isNotBlank(s)) { ls.add(s.trim()); } } }
            b.lotsByCustomer.put(c.Id, ls);
        }
        if (!lots.isEmpty() && !custByAccount.isEmpty()) {
            for (AggregateResult r : [SELECT Customer__c acc, Lot_Number__c lot, SUM(Units__c) units FROM Lot_Shipment__c
                                      WHERE Lot_Number__c IN :lots AND Customer__c IN :custByAccount.keySet() GROUP BY Customer__c, Lot_Number__c]) {
                Id cid = custByAccount.get((Id) r.get('acc'));
                b.shippedByLine.put(cid + '|' + (String) r.get('lot'), (Decimal) r.get('units'));
            }
        }

        // CQ.AI: the tasks still missing for this kind of action
        if (!closed && fa.Strategy_Status__c == 'Confirmed') {
            Date checkBy = fa.Check_By__c == null ? today.addDays(30) : fa.Check_By__c;
            Date noticeBy = today.addDays(2);
            Date responseBy = today.addDays(14) < checkBy ? today.addDays(14) : checkBy;
            Date returnBy = checkBy.addDays(-7) > today ? checkBy.addDays(-7) : checkBy;
            Boolean isNotice = fa.Action_Type__c == CqFieldActionStrategy.NOTICE;
            Boolean isCorrection = fa.Action_Type__c == CqFieldActionStrategy.CORRECTION;
            for (Field_Action_Customer__c c : custs) {
                addSuggestion(b, have, NOTICE, c, null, 'Send recall notice to ' + c.Customer_Name__c, noticeBy);
                if (fa.Check_Level__c != 'Level E') { addSuggestion(b, have, RESPONSE, c, null, 'Collect response form from ' + c.Customer_Name__c, responseBy); }
                if (isNotice) { continue; }
                for (String lot : b.lotsByCustomer.get(c.Id)) {
                    Decimal n = b.shippedByLine.get(c.Id + '|' + lot);
                    String units = n == null ? '' : ' of ' + n.intValue() + ' units';
                    addSuggestion(b, have, isCorrection ? CORRECT : RETURN_IT, c, lot,
                        (isCorrection ? 'Confirm correction' : 'Track return') + units + ' of lot ' + lot, returnBy);
                }
            }
            if (!b.suggestions.isEmpty()) {
                Map<String, Integer> byType = new Map<String, Integer>();
                for (Suggestion s : b.suggestions) { byType.put(s.type, (byType.containsKey(s.type) ? byType.get(s.type) : 0) + 1); }
                List<String> parts = new List<String>();
                for (String k : new List<String>{ NOTICE, RESPONSE, RETURN_IT, CORRECT }) {
                    if (!byType.containsKey(k)) { continue; }
                    Integer n = byType.get(k);
                    parts.add(n + ' ' + (k == NOTICE ? 'recall notice' : k == RESPONSE ? 'response' : k == RETURN_IT ? 'return' : 'correction') + (n == 1 ? '' : 's'));
                }
                Integer total = b.suggestions.size();
                b.suggestLine = total + ' task' + (total == 1 ? '' : 's') + ' for ' + (fa.Check_Level__c == null ? 'this' : 'a ' + fa.Check_Level__c) + ' '
                    + (fa.Action_Type__c == null ? 'field action' : fa.Action_Type__c.toLowerCase()) + ': ' + String.join(parts, ', ') + '.';
            }
        }
        if (!closed) {
            // dynamic, as a static User query does not compile in this org
            for (SObject u : Database.query('SELECT Id, Name FROM User WHERE IsActive = true AND UserType = \'Standard\' ORDER BY Name LIMIT 300')) {
                Person p = new Person(); p.id = u.Id; p.name = (String) u.get('Name'); b.people.add(p);
            }
        }
        return b;
    }
    private static void addSuggestion(Board b, Set<String> have, String type, Field_Action_Customer__c c, String lot, String subject, Date due) {
        String key = type + '|' + c.Id + '|' + (lot == null ? '' : lot);
        if (have.contains(key)) { return; }
        Suggestion s = new Suggestion();
        s.key = key; s.type = type; s.subject = subject; s.customerId = c.Id; s.customer = c.Customer_Name__c; s.lot = lot; s.due = due;
        b.suggestions.add(s);
    }

    private static Field_Action__c openFa(Id recordId) {
        Field_Action__c fa = [SELECT Id, Status__c, Strategy_Status__c, Recovery_Status__c FROM Field_Action__c WHERE Id = :recordId];
        if (fa.Status__c == 'Closed') { throw new AuraHandledException('This field action is closed.'); }
        if (fa.Strategy_Status__c != 'Confirmed') { throw new AuraHandledException('Confirm the strategy first.'); }
        return fa;
    }
    private static void reopen(Field_Action__c fa) {
        if (fa.Recovery_Status__c != 'In Progress') { update new Field_Action__c(Id = fa.Id, Recovery_Status__c = 'In Progress'); }
    }

    /** Creates CQ.AI's suggested tasks the coordinator kept, owned by the coordinator. */
    @AuraEnabled
    public static CqFieldActionRecovery.View createSuggested(Id recordId, List<String> keys) {
        Field_Action__c fa = openFa(recordId);
        Board bd = board(recordId, [SELECT Id, Strategy_Status__c, Check_By__c, Check_Level__c, Action_Type__c FROM Field_Action__c WHERE Id = :recordId], false);
        Set<String> want = new Set<String>(keys == null ? new List<String>() : keys);
        List<Task> adds = new List<Task>();
        for (Suggestion s : bd.suggestions) {
            if (!want.contains(s.key)) { continue; }
            adds.add(new Task(WhatId = recordId, OwnerId = UserInfo.getUserId(), Subject = s.subject.left(255), ActivityDate = s.due,
                Status = OPEN, Priority = 'Normal', Recall_Task_Type__c = s.type, Field_Action_Customer__c = s.customerId, Lot_Number__c = s.lot));
        }
        if (adds.isEmpty()) { throw new AuraHandledException('Choose at least one task.'); }
        insert adds;
        reopen(fa);
        return CqFieldActionRecovery.getView(recordId);
    }

    /**
     * Adds one task. values: customerId (or newCustomer, a name to add as a customer by hand), lot, type, subject,
     * ownerId, due (yyyy-mm-dd), units.
     */
    @AuraEnabled
    public static CqFieldActionRecovery.View addTask(Id recordId, Map<String, String> values) {
        Field_Action__c fa = openFa(recordId);
        String subject = values.get('subject'), type = values.get('type');
        if (String.isBlank(subject)) { throw new AuraHandledException('Enter what the task is.'); }
        Id customerId = String.isBlank(values.get('customerId')) ? null : (Id) values.get('customerId');
        if (customerId == null && String.isNotBlank(values.get('newCustomer'))) {
            Field_Action_Customer__c c = new Field_Action_Customer__c(Field_Action__c = recordId, Customer_Name__c = values.get('newCustomer').trim().left(255),
                Lots__c = String.isBlank(values.get('lot')) ? null : values.get('lot'), Status__c = 'Sent', Follow_Ups__c = 0, Source__c = 'Added by hand');
            insert c;
            customerId = c.Id;
        }
        insert new Task(WhatId = recordId, Subject = subject.trim().left(255), Status = OPEN, Priority = 'Normal',
            OwnerId = String.isBlank(values.get('ownerId')) ? UserInfo.getUserId() : (Id) values.get('ownerId'),
            ActivityDate = String.isBlank(values.get('due')) ? null : Date.valueOf(values.get('due')),
            Recall_Task_Type__c = String.isBlank(type) ? OTHER : type, Field_Action_Customer__c = customerId,
            Lot_Number__c = String.isBlank(values.get('lot')) ? null : values.get('lot'),
            Units__c = String.isBlank(values.get('units')) ? null : Decimal.valueOf(values.get('units')));
        reopen(fa);
        return CqFieldActionRecovery.getView(recordId);
    }

    /** Completes or reopens a task, or records its units. change: done, open, units. */
    @AuraEnabled
    public static CqFieldActionRecovery.View setTask(Id recordId, Id taskId, String change, Decimal units) {
        Field_Action__c fa = openFa(recordId);
        Task t = [SELECT Id, WhatId FROM Task WHERE Id = :taskId];
        if (t.WhatId != recordId) { throw new AuraHandledException('That task belongs to another record.'); }
        if (change == 'done') { update new Task(Id = taskId, Status = DONE); }
        else if (change == 'open') { update new Task(Id = taskId, Status = OPEN); }
        else if (change == 'units') {
            if (units != null && units < 0) { throw new AuraHandledException('Units cannot be negative.'); }
            update new Task(Id = taskId, Units__c = units);
        } else { throw new AuraHandledException('Unknown change: ' + change); }
        reopen(fa);
        return CqFieldActionRecovery.getView(recordId);
    }
}

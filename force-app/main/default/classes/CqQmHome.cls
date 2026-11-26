/**
 * CqQmHome: the Quality Management home (decided with Lou 25 Nov 2026; mockup "Triage Inbox Mockup", board Home).
 *
 * The Nonconformance card has one line for each role the person has: Triage (a triage queue member who can own NCs:
 * how many wait, how many are theirs) and My NCs (the NCs they own past triage: how many, how many overdue). Someone
 * with neither sees the NCs they reported. Each line opens its view of the Triage Inbox.
 *
 * Needs You lists records, not workflow tasks: the person's NCs that are overdue, then due soon, then (for a triager)
 * the NCs that have waited longest for triage. Waiting for Your Approval comes from CqApprovals.
 */
public with sharing class CqQmHome {
    public static final Integer NEEDS_MAX = 8;
    public static final Integer LONG_WAIT_DAYS = 3;

    public class Stat {
        @AuraEnabled public Integer n; @AuraEnabled public String label; @AuraEnabled public Boolean warn = false;
        Stat(Integer n, String label, Boolean warn) { this.n = n; this.label = label; this.warn = warn == true; }
    }
    public class Line {
        @AuraEnabled public String key; @AuraEnabled public String role; @AuraEnabled public String view;
        @AuraEnabled public List<Stat> stats = new List<Stat>();
    }
    public class Need {
        @AuraEnabled public Id id; @AuraEnabled public String name; @AuraEnabled public String title;
        @AuraEnabled public String why; @AuraEnabled public Boolean warn = false;
        Integer rank; Integer weight;
    }
    public class Home {
        @AuraEnabled public List<Line> nc = new List<Line>();
        @AuraEnabled public List<Need> needs = new List<Need>();
        @AuraEnabled public String roleLine;
        @AuraEnabled public Boolean triager = false;
    }

    @AuraEnabled
    public static Home load() {
        Home h = new Home();
        Map<Id, String> qs = CqTriageInbox.myQueues();
        Boolean canOwn = CqTriageInbox.canOwn(UserInfo.getUserId());
        h.triager = !qs.isEmpty() && canOwn;
        List<CqTriageInbox.Row> waiting = h.triager ? CqTriageInbox.waitingRows(qs) : new List<CqTriageInbox.Row>();
        List<CqTriageInbox.Row> mine = CqTriageInbox.mineRows();

        Integer mineTriage = 0, minePast = 0, overdue = 0;
        for (CqTriageInbox.Row r : mine) {
            if (r.stage == 'Triage') { mineTriage++; } else { minePast++; }
            if (r.dueDays != null && r.dueDays < 0) { overdue++; }
        }
        if (h.triager) {
            Line l = new Line(); l.key = 'triage'; l.role = 'Triage'; l.view = 'waiting';
            l.stats.add(new Stat(waiting.size(), 'waiting', false));
            l.stats.add(new Stat(mineTriage, 'yours', false));
            h.nc.add(l);
        }
        if (minePast > 0 || (!h.triager && mineTriage > 0)) {
            Line l = new Line(); l.key = 'mine'; l.role = 'My NCs'; l.view = 'mine';
            l.stats.add(new Stat(h.triager ? minePast : mine.size(), h.triager ? 'past triage' : 'open', false));
            if (overdue > 0) { l.stats.add(new Stat(overdue, 'overdue', true)); }
            h.nc.add(l);
        }
        if (h.nc.isEmpty()) {
            Line l = new Line(); l.key = 'reported'; l.role = 'Reported by You'; l.view = 'reported';
            Id me = UserInfo.getUserId();
            Integer open = [SELECT COUNT() FROM compliancequest__SQX_Nonconformance__c
                            WHERE CreatedById = :me AND compliancequest__Status__c NOT IN :CqTriageInbox.DONE];
            l.stats.add(new Stat(open, 'open', false));
            h.nc.add(l);
        }
        h.roleLine = h.triager
            ? 'You triage nonconformances in ' + String.join(sorted(qs.values()), ', ') + '.'
            : 'Report a problem any time from Report a Nonconformance.';

        // Needs You: overdue first (most overdue), then due soon (soonest), then the longest waits for triage
        List<Need> needs = new List<Need>();
        for (CqTriageInbox.Row r : mine) {
            if (r.dueDays == null) {
                if (r.stage == 'Triage' && r.old) { needs.add(need(r, r.status, true, 2, -r.waitDays)); }
                continue;
            }
            if (r.dueDays < 0) { needs.add(need(r, r.status, true, 0, r.dueDays)); }
            else if (r.dueDays <= CqTriageInbox.SOON_DAYS) { needs.add(need(r, r.status, r.dueDays == 0, 1, r.dueDays)); }
        }
        for (CqTriageInbox.Row r : waiting) {
            if (r.waitDays >= LONG_WAIT_DAYS) { needs.add(need(r, 'Waiting for triage ' + r.waiting, r.old, 2, -r.waitDays)); }
        }
        List<NeedSort> s = new List<NeedSort>();
        for (Need n : needs) { s.add(new NeedSort(n)); }
        s.sort();
        for (NeedSort x : s) { if (h.needs.size() < NEEDS_MAX) { h.needs.add(x.n); } }
        return h;
    }

    private static Need need(CqTriageInbox.Row r, String why, Boolean warn, Integer rank, Integer weight) {
        Need n = new Need();
        n.id = r.id; n.name = r.name; n.title = r.title; n.why = why; n.warn = warn == true; n.rank = rank; n.weight = weight;
        return n;
    }
    private class NeedSort implements Comparable {
        Need n;
        NeedSort(Need n) { this.n = n; }
        public Integer compareTo(Object o) {
            Need b = ((NeedSort) o).n;
            if (n.rank != b.rank) { return n.rank - b.rank; }
            return n.weight - b.weight;
        }
    }
    private static List<String> sorted(List<String> l) { List<String> c = new List<String>(l); c.sort(); return c; }
}

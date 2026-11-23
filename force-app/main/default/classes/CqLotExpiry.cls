/**
 * Daily: lots that expired since the last run are held as Expired (CqLotStatus). The expiry date is the lot's own,
 * else its batch record's. A lot already held as strictly or more strictly is left alone.
 * Schedule: System.schedule('Lot Expiry', '0 15 1 * * ?', new CqLotExpiry());
 */
public with sharing class CqLotExpiry implements Schedulable {
    static final List<String> STRICTER = new List<String>{ 'Expired', 'Recall Pending', 'Recalled', 'Rejected' };

    public void execute(SchedulableContext ctx) { run(); }

    public static Integer run() {
        Date today = Date.today();
        Set<String> lots = new Set<String>();
        for (compliancequest__SQX_Lot_Info__c l : [SELECT Name FROM compliancequest__SQX_Lot_Info__c
                                                   WHERE Release_Status__c NOT IN :STRICTER
                                                     AND (compliancequest__Expiration_Date__c < :today
                                                          OR (compliancequest__Expiration_Date__c = null AND Batch__r.cqext__Expiration_Date__c < :today))
                                                   LIMIT 2000]) {
            lots.add(l.Name);
        }
        CqLotStatus.sourceChanged(lots);
        return lots.size();
    }
}

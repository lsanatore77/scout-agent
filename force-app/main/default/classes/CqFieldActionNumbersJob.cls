/**
 * Nightly: works out the numbers on every open Field Action, and on those closed in the last two days so their final
 * numbers are kept. Schedule it once with CqFieldActionNumbersJob.schedule().
 */
public without sharing class CqFieldActionNumbersJob implements Database.Batchable<SObject>, Schedulable {

    public static final String NAME = 'Field Action Numbers (nightly)';

    public Database.QueryLocator start(Database.BatchableContext bc) {
        return Database.getQueryLocator([SELECT Id FROM Field_Action__c
                                         WHERE Status__c != 'Closed' OR Closed_On__c = LAST_N_DAYS:2 OR Numbers_Updated_On__c = null]);
    }

    public void execute(Database.BatchableContext bc, List<Field_Action__c> scope) {
        Set<Id> ids = new Set<Id>();
        for (Field_Action__c fa : scope) { ids.add(fa.Id); }
        CqFieldActionNumbers.refresh(ids);
    }

    public void finish(Database.BatchableContext bc) {}

    public void execute(SchedulableContext sc) { Database.executeBatch(new CqFieldActionNumbersJob(), 50); }

    /** Runs at 2:17 every night, in the scheduling user's time zone. */
    public static Id schedule() { return System.schedule(NAME, '0 17 2 * * ?', new CqFieldActionNumbersJob()); }
}

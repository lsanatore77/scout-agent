/**
 * CqWsSettings: how the CQ.AI workspaces look, from CQ.AI Workspace Settings (a hierarchy custom setting, so the org,
 * a profile or one user can each have their own). The workspace frame (c-cq-ws-shell) reads it once per page.
 *  - Steps Position: Left (default, also when blank) or Top.
 *  - Theme: blank for the standard look, or the name of a cqStyles theme (e.g. Harbor).
 */
public with sharing class CqWsSettings {
    public class Look {
        @AuraEnabled public String steps = 'left';
        @AuraEnabled public String theme = '';
    }

    @TestVisible private static CQ_AI_Workspace_Settings__c fake;

    @AuraEnabled(cacheable=true)
    public static Look get() {
        CQ_AI_Workspace_Settings__c s = fake != null ? fake : CQ_AI_Workspace_Settings__c.getInstance();
        Look l = new Look();
        if (s == null) { return l; }
        if (String.isNotBlank(s.Steps_Position__c) && s.Steps_Position__c.trim().equalsIgnoreCase('top')) { l.steps = 'top'; }
        // only letters, digits and dashes reach the page, as part of a class name
        if (String.isNotBlank(s.Theme__c)) { l.theme = s.Theme__c.trim().toLowerCase().replaceAll('[^a-z0-9-]', ''); }
        return l;
    }
}

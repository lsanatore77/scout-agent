/** The workspace look: left steps and the standard theme unless CQ.AI Workspace Settings says otherwise. */
@IsTest
private class CqWsSettingsTest {
    @IsTest
    static void blankMeansLeftAndStandard() {
        CqWsSettings.fake = new CQ_AI_Workspace_Settings__c();
        CqWsSettings.Look l = CqWsSettings.get();
        System.assertEquals('left', l.steps);
        System.assertEquals('', l.theme);
    }

    @IsTest
    static void topAndAThemeAreRead() {
        CqWsSettings.fake = new CQ_AI_Workspace_Settings__c(Steps_Position__c = ' TOP ', Theme__c = 'Harbor');
        CqWsSettings.Look l = CqWsSettings.get();
        System.assertEquals('top', l.steps);
        System.assertEquals('harbor', l.theme);
    }

    @IsTest
    static void onlyASafeClassNameReachesThePage() {
        CqWsSettings.fake = new CQ_AI_Workspace_Settings__c(Steps_Position__c = 'Sideways', Theme__c = 'Har bor"><x');
        CqWsSettings.Look l = CqWsSettings.get();
        System.assertEquals('left', l.steps, 'anything but Top is Left');
        System.assertEquals('harborx', l.theme);
    }

    @IsTest
    static void theOrgDefaultIsUsed() {
        insert new CQ_AI_Workspace_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Steps_Position__c = 'Top');
        System.assertEquals('top', CqWsSettings.get().steps);
    }
}

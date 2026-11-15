@IsTest
private class AskCqAgentsTest {

    @IsTest
    static void unknownAgent() {
        System.assertEquals(null, AskCqAgents.idFor('No_Such_Agent_Here'));
        System.assertEquals(null, AskCqAgents.idFor(''));
    }
}

@IsTest
private class CqFieldActionAgentContextTest {

    @IsTest
    static void noRecord() {
        CqFieldActionAgentContext.Request req = new CqFieldActionAgentContext.Request();
        List<CqFieldActionAgentContext.Response> out = CqFieldActionAgentContext.run(new List<CqFieldActionAgentContext.Request>{ req });
        System.assert(out[0].facts.contains('No record was given'), out[0].facts);
    }

    @IsTest
    static void otherObject() {
        String facts = CqFieldActionAgentContext.factsFor(UserInfo.getUserId());
        System.assert(facts.contains('only reads those two'), facts);
    }
}

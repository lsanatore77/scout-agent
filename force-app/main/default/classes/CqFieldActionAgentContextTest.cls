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

    @IsTest
    static void signalsStrongestFirst() {
        List<CqFieldActionReview.Sig> sigs = new List<CqFieldActionReview.Sig>();
        sigs.add(sig('A', 'Assess', false, 90));
        sigs.add(sig('B', 'Escalate', false, 7.4));
        sigs.add(sig('C', 'Escalate', false, 66.7));
        sigs.add(sig('D', 'Escalate', true, 2));
        List<CqFieldActionReview.Sig> out = CqFieldActionAgentContext.strongestFirst(sigs);
        System.assertEquals('D,C,B,A', out[0].name + ',' + out[1].name + ',' + out[2].name + ',' + out[3].name);
    }

    static CqFieldActionReview.Sig sig(String name, String strength, Boolean thisLot, Decimal times) {
        CqFieldActionReview.Sig s = new CqFieldActionReview.Sig();
        s.name = name; s.strength = strength; s.thisLot = thisLot; s.times = times;
        return s;
    }
}

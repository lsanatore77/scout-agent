/** Lot Stock and Lot Shipment: the figures read for the Scope step, and the triggers that keep open field actions' lots in step. */
@IsTest
private class CqLotStockShipmentsTest {

    static Field_Action_Lot__c faLot(Id faId, String lot) {
        Field_Action_Lot__c l = new Field_Action_Lot__c(Field_Action__c = faId, Lot_Number__c = lot);
        insert l;
        return l;
    }

    @IsTest
    static void stockRollsUpToTheFieldActionLot() {
        Field_Action__c fa = new Field_Action__c();
        insert fa;
        Field_Action_Lot__c l = faLot(fa.Id, 'ZT-LOT-1');

        Test.startTest();
        Lot_Stock__c a = new Lot_Stock__c(Lot_Number__c = 'ZT-LOT-1', Units_On_Hand__c = 40, Source__c = 'ERP', As_Of__c = Datetime.now().addDays(-2));
        Lot_Stock__c b = new Lot_Stock__c(Lot_Number__c = 'ZT-LOT-1', Units_On_Hand__c = 0, Source__c = 'Manual', As_Of__c = Datetime.now());
        insert new List<Lot_Stock__c>{ a, b };
        Test.stopTest();

        l = [SELECT Units_On_Hand__c, Location__c FROM Field_Action_Lot__c WHERE Id = :l.Id];
        System.assertEquals(40, l.Units_On_Hand__c, 'the trigger sets units on hand from the stock records');
        System.assertEquals('No location 40', l.Location__c);

        Map<String, CqLotStock.Stock> st = CqLotStock.forScope(new List<String>{ 'ZT-LOT-1', 'ZT-NONE', null });
        CqLotStock.Stock s = st.get('ZT-LOT-1');
        System.assertEquals(40, s.total);
        System.assertEquals(true, s.hasRecord);
        System.assertEquals(1, s.places.size(), 'only locations with units are listed');
        System.assertEquals('Mixed', s.source, 'two sources read as Mixed');
        System.assertEquals(a.As_Of__c, s.asOf, 'the oldest figure dates the stock');
        System.assertEquals(false, st.containsKey('ZT-NONE'));
        System.assertEquals(0, CqLotStock.forLots(new Set<String>()).size());
        System.assertEquals(0, CqLotStock.forScope(null).size());

        delete new List<Lot_Stock__c>{ a, b };
        l = [SELECT Units_On_Hand__c, Location__c FROM Field_Action_Lot__c WHERE Id = :l.Id];
        System.assertEquals(null, l.Units_On_Hand__c, 'no stock records left, no figure');
        CqLotStock.refresh(new Set<String>{ null });
    }

    @IsTest
    static void stockWithNoUnitsReadsNoneInStock() {
        insert new Lot_Stock__c(Lot_Number__c = 'ZT-LOT-0', Units_On_Hand__c = null);
        CqLotStock.Stock s = CqLotStock.forLots(new Set<String>{ 'ZT-LOT-0' }).get('ZT-LOT-0');
        System.assertEquals(0, s.total);
        System.assertEquals('None in stock', s.summary);
    }

    @IsTest
    static void shipmentsRollUpAndListCustomers() {
        Account cust = new Account(Name = 'ZT Customer');
        insert cust;
        Field_Action__c fa = new Field_Action__c();
        insert fa;
        Field_Action_Lot__c l = faLot(fa.Id, 'ZT-LOT-1');

        Test.startTest();
        Lot_Shipment__c s1 = new Lot_Shipment__c(Lot_Number__c = 'ZT-LOT-1', Units__c = 10, Customer__c = cust.Id);
        Lot_Shipment__c s2 = new Lot_Shipment__c(Lot_Number__c = 'ZT-LOT-1', Units__c = 5, Customer__c = cust.Id);
        Lot_Shipment__c s3 = new Lot_Shipment__c(Lot_Number__c = 'ZT-LOT-2', Units__c = 7, Customer__c = cust.Id);
        insert new List<Lot_Shipment__c>{ s1, s2, s3 };
        Test.stopTest();

        l = [SELECT Units_Shipped__c FROM Field_Action_Lot__c WHERE Id = :l.Id];
        System.assertEquals(15, l.Units_Shipped__c, 'the trigger totals the shipments for the lot');

        Map<String, Decimal> t = CqLotShipments.totals(new Set<String>{ 'ZT-LOT-1', 'ZT-LOT-2' });
        System.assertEquals(15, t.get('ZT-LOT-1'));
        System.assertEquals(7, t.get('ZT-LOT-2'));
        System.assertEquals(0, CqLotShipments.totals(null).size());

        List<CqLotShipments.Consignee> cs = CqLotShipments.customers(new Set<String>{ 'ZT-LOT-1', 'ZT-LOT-2' });
        System.assertEquals(1, cs.size(), 'one row per customer');
        System.assertEquals(22, cs[0].units);
        System.assertEquals(2, cs[0].lots.size());
        System.assertEquals('ZT Customer', cs[0].name);
        System.assertEquals(0, CqLotShipments.customers(new Set<String>()).size());

        // a lot that came into scope after its shipments is filled when the field action is read
        Field_Action_Lot__c late = faLot(fa.Id, 'ZT-LOT-2');
        CqLotShipments.fillShipped(fa.Id);
        late = [SELECT Units_Shipped__c FROM Field_Action_Lot__c WHERE Id = :late.Id];
        System.assertEquals(7, late.Units_Shipped__c);
        CqLotShipments.fillShipped(fa.Id);   // nothing blank now

        // shipped with no stock record: the Scope step still shows units shipped
        CqLotStock.Stock only = CqLotStock.forScope(new List<String>{ 'ZT-LOT-2' }).get('ZT-LOT-2');
        System.assertEquals(7, only.shipped);
        System.assertEquals(null, only.total);

        s2.Units__c = 6;
        update s2;
        l = [SELECT Units_Shipped__c FROM Field_Action_Lot__c WHERE Id = :l.Id];
        System.assertEquals(16, l.Units_Shipped__c, 'an edited shipment is re-totalled');
        CqLotShipments.shipped(new Set<String>{ null });
    }

    @IsTest
    static void lotNumberFillsFromTheLotRecord() {
        compliancequest__SQX_Lot_Info__c lot = new compliancequest__SQX_Lot_Info__c(Name = 'ZT-INFO-1', compliancequest__Part_Number__c = 'ZT-PART');
        insert lot;
        Lot_Stock__c st = new Lot_Stock__c(Lot__c = lot.Id, Units_On_Hand__c = 3);
        Lot_Shipment__c sh = new Lot_Shipment__c(Lot__c = lot.Id, Units__c = 2);
        insert st;
        insert sh;
        System.assertEquals('ZT-INFO-1', [SELECT Lot_Number__c FROM Lot_Stock__c WHERE Id = :st.Id].Lot_Number__c);
        System.assertEquals('ZT-INFO-1', [SELECT Lot_Number__c FROM Lot_Shipment__c WHERE Id = :sh.Id].Lot_Number__c);
    }
}

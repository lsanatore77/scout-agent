/**
 * AssociatedItemsReportAction
 * -----------------------------
 * Invocable Apex action for Agentforce. Unlike
 * GenerateAssociatedItemsReportAction (which renders a PDF and attaches it
 * to a record), this action returns the Associated Items data directly as
 * a typed response so Agentforce can render it inline in the conversation
 * using a Custom Lightning Type backed by the associatedItemsReport LWC.
 *
 * Reuses the same query logic as GenerateAssociatedItemsReportAction:
 * Part -> Part Revision -> Assembly -> Assembly Line Item, plus the
 * Nonconformance / CAPA / Change Order / Inspection records related to the
 * primary Part and every component Part in its assembly.
 *
 * When Target Record Id is supplied, this action resolves ALL related
 * records itself (Nonconformances, CAPAs, Change Orders, Inspections) from
 * the Complaint's Part and its assembly components. The ID lists on the
 * request are only used as a fallback when no Target Record Id is given, so
 * the agent no longer depends on the planner carrying ID lists over from
 * the "Associated Items Competition" flow.
 *
 * Optional Start Date / End Date inputs limit the related records
 * (Nonconformances, CAPAs, Change Orders, Inspections) to those created in
 * that range (inclusive). Either end may be left blank.
 *
 * When the Complaint has a Lot Number, Nonconformances and Inspections whose
 * own Lot Number matches it are added to the part-based results, and each
 * is tagged with how it was matched (Part, Lot, or Part and Lot). CAPAs and
 * Change Orders have no Lot Number field, so they stay part-based.
 *
 * The actual report payload (AssociatedItemsReportData and its nested
 * types) lives in separate top-level classes, not nested here -- Custom
 * Lightning Types require the bound Apex class to be top-level, global,
 * and @JsonAccess-serializable, which is a different contract than the
 * @InvocableVariable-based action schema below.
 */
global without sharing class AssociatedItemsReportAction {

    // ---------- Invocable entry point ----------

    global class Request {
        @InvocableVariable(label='Report Title' required=false)
        global String reportTitle;

        @InvocableVariable(label='Target Record Id' description='The Complaint record currently open in the conversation (e.g. the current record Id). When this is set and Primary Part Id is not, the Primary Part and its Nonconformances, CAPAs, Change Orders and Inspections are looked up automatically from this Complaint.' required=false)
        global Id targetRecordId;

        @InvocableVariable(label='Primary Part Id' description='The Complaint/record\'s primary Part. Used to look up the Part\'s own details plus its Assembly and Assembly Line Items. Leave blank and set Target Record Id instead to have this resolved automatically.' required=false)
        global Id primaryPartId;

        @InvocableVariable(label='Start Date' description='Optional. Only include related records created on or after this date. Leave blank for no start limit.' required=false)
        global Date startDate;

        @InvocableVariable(label='End Date' description='Optional. Only include related records created on or before this date. Leave blank for no end limit.' required=false)
        global Date endDate;

        @InvocableVariable(label='Nonconformance Ids' required=false)
        global List<Id> nonconformanceIds;

        @InvocableVariable(label='CAPA Ids' required=false)
        global List<Id> capaIds;

        @InvocableVariable(label='Change Order Ids' required=false)
        global List<Id> changeOrderIds;

        @InvocableVariable(label='Inspection Ids' required=false)
        global List<Id> inspectionIds;
    }

    /**
     * Wraps AssociatedItemsReportData as the single, sole output of the
     * invocable action. Salesforce requires an @InvocableMethod's return
     * type to carry at least one @InvocableVariable field -- a bare data
     * class with none fails to compile. This wrapper satisfies that while
     * still giving the action exactly one output (named "report").
     */
    global class ActionResponse {
        @InvocableVariable(label='Report')
        global AssociatedItemsReportData report;
    }

    // ---------- Action ----------

    @InvocableMethod(label='Get Associated Items Report' description='Returns the Primary Part, Assembly, Assembly Line Items, and related NCs/CAPAs/Change Orders/Inspections (optionally filtered by created date range and matched by Lot Number) for display in Agentforce')
    global static List<ActionResponse> getAssociatedItemsReport(List<Request> requests) {
        List<ActionResponse> results = new List<ActionResponse>();

        for (Request req : requests) {
            AssociatedItemsReportData res = new AssociatedItemsReportData();
            try {
                res.reportTitle = String.isNotBlank(req.reportTitle)
                    ? req.reportTitle
                    : 'Associated Items Summary Report';
                res.generatedAt = DateTime.now().format('MMMM d, yyyy h:mm a');

                // Optional Created Date range. A reversed range is swapped
                // rather than rejected so the agent never has to surface an
                // error for it.
                Date startD = req.startDate;
                Date endD = req.endDate;
                if (startD != null && endD != null && startD > endD) {
                    Date swap = startD;
                    startD = endD;
                    endD = swap;
                }
                res.dateRangeLabel = buildDateRangeLabel(startD, endD);
                Datetime startBound = rangeStart(startD);
                Datetime endBound = rangeEnd(endD);

                // Target Record Id is authoritative when present: always
                // resolve the Primary Part (and Lot Number) from the
                // Complaint itself rather than trusting a Primary Part Id
                // the planner may have separately guessed or carried over
                // from earlier in the conversation. Only fall back to an
                // explicitly supplied Primary Part Id when no Target Record
                // Id was given.
                ComplaintContext ctx = req.targetRecordId != null
                    ? resolveComplaintContext(req.targetRecordId)
                    : new ComplaintContext();
                Id resolvedPartId = req.targetRecordId != null
                    ? ctx.partId
                    : req.primaryPartId;
                String lotNumber = ctx.lotNumber;
                res.lotNumber = lotNumber;

                // populatePartAndAssembly walks Part -> Revision -> Assembly
                // -> Assembly Line Item and hands back every Part Id it
                // touched: the primary Part plus each component Part
                // referenced by an Assembly Line Item. Related quality
                // records are filed against whichever Part they actually
                // affect -- often a component several levels down -- so
                // they are resolved against this whole set, not just the
                // primary Part.
                Set<Id> relatedPartIds = populatePartAndAssembly(resolvedPartId, res);

                Boolean autoResolve = req.targetRecordId != null
                    && (resolvedPartId != null || String.isNotBlank(lotNumber));

                Set<Id> partNcIds = new Set<Id>();
                Set<Id> lotNcIds = new Set<Id>();
                Set<Id> partInspectionIds = new Set<Id>();
                Set<Id> lotInspectionIds = new Set<Id>();
                List<Id> resolvedNcIds;
                List<Id> resolvedCapaIds;
                List<Id> resolvedChangeOrderIds;
                List<Id> resolvedInspectionIds;

                if (autoResolve) {
                    partNcIds = resolveNonconformanceIds(relatedPartIds);
                    lotNcIds = resolveNonconformanceIdsByLot(lotNumber);
                    partInspectionIds = resolveInspectionIds(relatedPartIds);
                    lotInspectionIds = resolveInspectionIdsByLot(lotNumber);

                    resolvedNcIds = mergeIds(partNcIds, lotNcIds);
                    resolvedInspectionIds = mergeIds(partInspectionIds, lotInspectionIds);
                    // CAPAs and Change Orders have no Lot Number field, so
                    // they remain part-based.
                    resolvedCapaIds = resolveCapaIds(relatedPartIds);
                    resolvedChangeOrderIds = resolveChangeOrderIds(relatedPartIds);
                } else {
                    resolvedNcIds = req.nonconformanceIds;
                    resolvedCapaIds = req.capaIds;
                    resolvedChangeOrderIds = req.changeOrderIds;
                    resolvedInspectionIds = req.inspectionIds;
                }

                populateRelatedRecords(
                    resolvedNcIds,
                    resolvedCapaIds,
                    resolvedChangeOrderIds,
                    resolvedInspectionIds,
                    partNcIds,
                    lotNcIds,
                    partInspectionIds,
                    lotInspectionIds,
                    startBound,
                    endBound,
                    res
                );

                if (autoResolve) {
                    applyLineItemLotMatch(res, lotNumber, startBound, endBound);
                    populateInvestigations(req.targetRecordId, relatedPartIds, lotNumber, startBound, endBound, res);
                }

                res.hasPrimaryPart = res.primaryPart != null;
                res.success = true;
            } catch (Exception ex) {
                res.success = false;
                res.errorMessage = ex.getMessage();
            }
            ActionResponse wrapper = new ActionResponse();
            wrapper.report = res;
            results.add(wrapper);
        }
        return results;
    }

    /**
     * Walks Part -> Part Revision -> Assembly -> Assembly Line Item, same
     * traversal as GenerateAssociatedItemsReportAction, and maps the SObject
     * results onto the lightweight wrapper types the LWC consumes.
     */
    private static Set<Id> populatePartAndAssembly(Id partId, AssociatedItemsReportData res) {
        Set<Id> relatedPartIds = new Set<Id>();
        if (partId == null) {
            return relatedPartIds;
        }
        relatedPartIds.add(partId);

        List<compliancequest__SQX_Part__c> parts = [
            SELECT Id, Name, compliancequest__Part_Number__c, compliancequest__Part_Type__c,
                   compliancequest__Part_Family__r.Name, Has_NC__c
            FROM compliancequest__SQX_Part__c
            WHERE Id = :partId
            LIMIT 1
        ];
        if (parts.isEmpty()) {
            return relatedPartIds;
        }

        compliancequest__SQX_Part__c part = parts[0];
        AssociatedItemsPartInfo pInfo = new AssociatedItemsPartInfo();
        pInfo.id = part.Id;
        pInfo.name = part.Name;
        pInfo.partNumber = part.compliancequest__Part_Number__c;
        pInfo.partType = part.compliancequest__Part_Type__c;
        pInfo.partFamily = part.compliancequest__Part_Family__r != null ? part.compliancequest__Part_Family__r.Name : null;
        pInfo.hasNC = part.Has_NC__c;
        res.primaryPart = pInfo;

        List<cqext__CQPLM_Part_Revision__c> revisions = [
            SELECT Id
            FROM cqext__CQPLM_Part_Revision__c
            WHERE cqext__CQPLM_Part__c = :partId
        ];
        if (revisions.isEmpty()) {
            return relatedPartIds;
        }

        Set<Id> revisionIds = new Set<Id>();
        for (cqext__CQPLM_Part_Revision__c rev : revisions) {
            revisionIds.add(rev.Id);
        }

        List<cqext__CQPLM_Assembly__c> assemblies = [
            SELECT Id, Name
            FROM cqext__CQPLM_Assembly__c
            WHERE cqext__CQPLM_Part_Revision__c IN :revisionIds
        ];
        for (cqext__CQPLM_Assembly__c asm : assemblies) {
            AssociatedItemsAssemblyInfo aInfo = new AssociatedItemsAssemblyInfo();
            aInfo.id = asm.Id;
            aInfo.name = asm.Name;
            res.assemblies.add(aInfo);
        }
        if (assemblies.isEmpty()) {
            return relatedPartIds;
        }

        Set<Id> assemblyIds = new Set<Id>();
        for (cqext__CQPLM_Assembly__c asm : assemblies) {
            assemblyIds.add(asm.Id);
        }

        List<cqext__CQPLM_Assembly_line_Item__c> lineItems = [
            SELECT Id, Name, cqext__CQPLM_Assembly__r.Name,
                   cqext__CQPLM_Part__c, cqext__CQPLM_Part__r.Name, cqext__CQPLM_Part__r.compliancequest__Part_Number__c
            FROM cqext__CQPLM_Assembly_line_Item__c
            WHERE cqext__CQPLM_Assembly__c IN :assemblyIds
        ];
        for (cqext__CQPLM_Assembly_line_Item__c li : lineItems) {
            AssociatedItemsLineItemInfo liInfo = new AssociatedItemsLineItemInfo();
            liInfo.id = li.Id;
            liInfo.assemblyName = li.cqext__CQPLM_Assembly__r != null ? li.cqext__CQPLM_Assembly__r.Name : null;
            liInfo.partId = li.cqext__CQPLM_Part__c;
            liInfo.partName = li.cqext__CQPLM_Part__r != null ? li.cqext__CQPLM_Part__r.Name : null;
            liInfo.partNumber = li.cqext__CQPLM_Part__r != null ? li.cqext__CQPLM_Part__r.compliancequest__Part_Number__c : null;
            res.assemblyLineItems.add(liInfo);

            if (li.cqext__CQPLM_Part__c != null) {
                relatedPartIds.add(li.cqext__CQPLM_Part__c);
            }
        }

        return relatedPartIds;
    }

    /** Primary Part and Lot Number read from the Complaint. */
    private class ComplaintContext {
        Id partId;
        String lotNumber;
    }

    /**
     * Mirrors the flow's "Get This Record" -> "Get Primary Part" steps:
     * looks up the Complaint and returns its primary Part lookup field plus
     * the Lot Number entered on it.
     */
    private static ComplaintContext resolveComplaintContext(Id targetRecordId) {
        ComplaintContext ctx = new ComplaintContext();
        List<compliancequest__SQX_Complaint__c> complaints = [
            SELECT compliancequest__SQX_Part__c, compliancequest__Lot_Number__c
            FROM compliancequest__SQX_Complaint__c
            WHERE Id = :targetRecordId
            LIMIT 1
        ];
        if (!complaints.isEmpty()) {
            ctx.partId = complaints[0].compliancequest__SQX_Part__c;
            ctx.lotNumber = complaints[0].compliancequest__Lot_Number__c;
        }
        return ctx;
    }

    /**
     * Nonconformances whose own Part lookup matches the primary Part OR any
     * component Part pulled in from the assembly's Line Items. An NC is
     * usually filed against the specific component that failed, not the
     * top-level assembly/primary Part.
     */
    private static Set<Id> resolveNonconformanceIds(Set<Id> partIds) {
        Set<Id> ids = new Set<Id>();
        if (partIds == null || partIds.isEmpty()) {
            return ids;
        }
        for (compliancequest__SQX_Nonconformance__c nc : [
            SELECT Id
            FROM compliancequest__SQX_Nonconformance__c
            WHERE compliancequest__SQX_Part__c IN :partIds
        ]) {
            ids.add(nc.Id);
        }
        return ids;
    }

    /**
     * CAPAs filed against the primary Part or any assembly component Part.
     */
    private static List<Id> resolveCapaIds(Set<Id> partIds) {
        List<Id> ids = new List<Id>();
        if (partIds == null || partIds.isEmpty()) {
            return ids;
        }
        for (compliancequest__SQX_CAPA__c capa : [
            SELECT Id
            FROM compliancequest__SQX_CAPA__c
            WHERE compliancequest__SQX_Part__c IN :partIds
        ]) {
            ids.add(capa.Id);
        }
        return ids;
    }

    /**
     * Change Orders whose Product lookup is the primary Part or any
     * assembly component Part.
     */
    private static List<Id> resolveChangeOrderIds(Set<Id> partIds) {
        List<Id> ids = new List<Id>();
        if (partIds == null || partIds.isEmpty()) {
            return ids;
        }
        for (compliancequest__SQX_Change_Order__c co : [
            SELECT Id
            FROM compliancequest__SQX_Change_Order__c
            WHERE compliancequest__SQX_Product__c IN :partIds
        ]) {
            ids.add(co.Id);
        }
        return ids;
    }

    /**
     * Inspections filed against the primary Part or any assembly
     * component Part.
     */
    private static Set<Id> resolveInspectionIds(Set<Id> partIds) {
        Set<Id> ids = new Set<Id>();
        if (partIds == null || partIds.isEmpty()) {
            return ids;
        }
        for (compliancequest__SQX_Inspection__c insp : [
            SELECT Id
            FROM compliancequest__SQX_Inspection__c
            WHERE compliancequest__SQX_Part__c IN :partIds
        ]) {
            ids.add(insp.Id);
        }
        return ids;
    }

    /**
     * Nonconformances whose own Lot Number equals the Complaint's Lot Number.
     */
    private static Set<Id> resolveNonconformanceIdsByLot(String lotNumber) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(lotNumber)) {
            return ids;
        }
        for (compliancequest__SQX_Nonconformance__c nc : [
            SELECT Id
            FROM compliancequest__SQX_Nonconformance__c
            WHERE compliancequest__Lot_Number__c = :lotNumber
        ]) {
            ids.add(nc.Id);
        }
        return ids;
    }

    /**
     * Inspections whose own Lot Number equals the Complaint's Lot Number.
     */
    private static Set<Id> resolveInspectionIdsByLot(String lotNumber) {
        Set<Id> ids = new Set<Id>();
        if (String.isBlank(lotNumber)) {
            return ids;
        }
        for (compliancequest__SQX_Inspection__c insp : [
            SELECT Id
            FROM compliancequest__SQX_Inspection__c
            WHERE compliancequest__Lot_Number__c = :lotNumber
        ]) {
            ids.add(insp.Id);
        }
        return ids;
    }

    private static List<Id> mergeIds(Set<Id> a, Set<Id> b) {
        Set<Id> merged = new Set<Id>(a);
        merged.addAll(b);
        return new List<Id>(merged);
    }

    // ---------- Lot match on Assembly Line Items ----------

    /**
     * Tags each Assembly Line Item with how many Nonconformances and
     * Inspections carrying the Complaint's Lot Number are filed against its
     * component Part. The Bill of Materials itself has no lot data, so this
     * shows which components have quality records on the lot; it does not
     * prove a component came from that lot. Left blank when the Complaint has
     * no Lot Number. Respects the Created Date range.
     */
    private static void applyLineItemLotMatch(
        AssociatedItemsReportData res,
        String lotNumber,
        Datetime startBound,
        Datetime endBound
    ) {
        if (String.isBlank(lotNumber) || res.assemblyLineItems.isEmpty()) {
            return;
        }
        Set<Id> componentPartIds = new Set<Id>();
        for (AssociatedItemsLineItemInfo li : res.assemblyLineItems) {
            if (li.partId != null) {
                componentPartIds.add(li.partId);
            }
        }

        Map<Id, Integer> ncByPart = new Map<Id, Integer>();
        Map<Id, Integer> inspectionByPart = new Map<Id, Integer>();
        if (!componentPartIds.isEmpty()) {
            for (AggregateResult ar : [
                SELECT compliancequest__SQX_Part__c partId, COUNT(Id) total
                FROM compliancequest__SQX_Nonconformance__c
                WHERE compliancequest__Lot_Number__c = :lotNumber
                AND compliancequest__SQX_Part__c IN :componentPartIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
                GROUP BY compliancequest__SQX_Part__c
            ]) {
                ncByPart.put((Id) ar.get('partId'), (Integer) ar.get('total'));
            }
            for (AggregateResult ar : [
                SELECT compliancequest__SQX_Part__c partId, COUNT(Id) total
                FROM compliancequest__SQX_Inspection__c
                WHERE compliancequest__Lot_Number__c = :lotNumber
                AND compliancequest__SQX_Part__c IN :componentPartIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
                GROUP BY compliancequest__SQX_Part__c
            ]) {
                inspectionByPart.put((Id) ar.get('partId'), (Integer) ar.get('total'));
            }
        }

        for (AssociatedItemsLineItemInfo li : res.assemblyLineItems) {
            Integer ncs = ncByPart.containsKey(li.partId) ? ncByPart.get(li.partId) : 0;
            Integer inspections = inspectionByPart.containsKey(li.partId) ? inspectionByPart.get(li.partId) : 0;
            li.lotNcCount = ncs;
            li.lotInspectionCount = inspections;
            li.lotMatch = lotMatchLabel(ncs, inspections);
        }
    }

    /** 'None' or text such as 'Lot · 1 NC, 2 inspections'. */
    @TestVisible
    private static String lotMatchLabel(Integer ncs, Integer inspections) {
        List<String> pieces = new List<String>();
        if (ncs != null && ncs > 0) {
            pieces.add(ncs + (ncs == 1 ? ' NC' : ' NCs'));
        }
        if (inspections != null && inspections > 0) {
            pieces.add(inspections + (inspections == 1 ? ' inspection' : ' inspections'));
        }
        return pieces.isEmpty() ? 'None' : 'Lot · ' + String.join(pieces, ', ');
    }

    // ---------- Related Investigations ----------

    /**
     * Investigations filed against the primary Part or any component Part, or
     * carrying the Complaint's Lot Number, tagged Part, Lot, or Part and Lot.
     * Investigations started from this Complaint are left out. Respects the
     * Created Date range. Capped at 50 so a part with a long history stays
     * readable.
     */
    private static void populateInvestigations(
        Id complaintId,
        Set<Id> partIds,
        String lotNumber,
        Datetime startBound,
        Datetime endBound,
        AssociatedItemsReportData res
    ) {
        Set<Id> partMatches = new Set<Id>();
        Set<Id> lotMatches = new Set<Id>();
        if (partIds != null && !partIds.isEmpty()) {
            for (compliancequest__SQX_Investigation__c inv : [
                SELECT Id
                FROM compliancequest__SQX_Investigation__c
                WHERE compliancequest__SQX_Part__c IN :partIds
            ]) {
                partMatches.add(inv.Id);
            }
        }
        if (String.isNotBlank(lotNumber)) {
            for (compliancequest__SQX_Investigation__c inv : [
                SELECT Id
                FROM compliancequest__SQX_Investigation__c
                WHERE compliancequest__Lot_Number__c = :lotNumber
            ]) {
                lotMatches.add(inv.Id);
            }
        }
        List<Id> candidateIds = mergeIds(partMatches, lotMatches);
        if (candidateIds.isEmpty()) {
            return;
        }

        for (compliancequest__SQX_Investigation__c inv : [
            SELECT Id, Name, compliancequest__Status__c, compliancequest__Source_Name__c,
                   compliancequest__Source_Id__c, compliancequest__SQX_Complaint__c, CreatedDate,
                   compliancequest__SQX_Part__r.compliancequest__Part_Number__c
            FROM compliancequest__SQX_Investigation__c
            WHERE Id IN :candidateIds
            AND CreatedDate >= :startBound
            AND CreatedDate < :endBound
            ORDER BY CreatedDate DESC
            LIMIT 50
        ]) {
            if (isOwnInvestigation(complaintId, inv.compliancequest__SQX_Complaint__c, inv.compliancequest__Source_Id__c)) {
                continue;
            }
            AssociatedItemsInvestigationInfo info = new AssociatedItemsInvestigationInfo();
            info.id = inv.Id;
            info.name = inv.Name;
            info.partNumber = inv.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
            info.sourceName = inv.compliancequest__Source_Name__c;
            info.status = inv.compliancequest__Status__c;
            info.matchedBy = matchedBy(partMatches.contains(inv.Id), lotMatches.contains(inv.Id));
            info.createdDate = inv.CreatedDate.format('MMM d, yyyy');
            res.investigations.add(info);
        }
    }

    /** True when the Investigation was started from this Complaint. */
    @TestVisible
    private static Boolean isOwnInvestigation(Id complaintId, Id investigationComplaintId, String sourceId) {
        if (complaintId == null) {
            return false;
        }
        if (investigationComplaintId != null && investigationComplaintId == complaintId) {
            return true;
        }
        // Source Id is stored as text, sometimes in 15-character form.
        return String.isNotBlank(sourceId)
            && sourceId.left(15) == String.valueOf(complaintId).left(15);
    }

    /** 'Part', 'Lot' or 'Part and Lot'; null when neither set holds the record. */
    @TestVisible
    private static String matchedBy(Boolean inPart, Boolean inLot) {
        if (inPart && inLot) {
            return 'Part and Lot';
        }
        if (inLot) {
            return 'Lot';
        }
        if (inPart) {
            return 'Part';
        }
        return null;
    }

    /** Start of the range (inclusive), or a far-past sentinel when no Start Date. */
    @TestVisible
    private static Datetime rangeStart(Date startDate) {
        return startDate == null
            ? Datetime.newInstance(1900, 1, 1)
            : Datetime.newInstance(startDate, Time.newInstance(0, 0, 0, 0));
    }

    /** Exclusive upper bound (midnight after End Date), or a far-future sentinel when no End Date. */
    @TestVisible
    private static Datetime rangeEnd(Date endDate) {
        return endDate == null
            ? Datetime.newInstance(4000, 1, 1)
            : Datetime.newInstance(endDate.addDays(1), Time.newInstance(0, 0, 0, 0));
    }

    private static String formatDate(Date d) {
        return Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('MMM d, yyyy');
    }

    @TestVisible
    private static String buildDateRangeLabel(Date startDate, Date endDate) {
        if (startDate != null && endDate != null) {
            return formatDate(startDate) + ' to ' + formatDate(endDate);
        }
        if (startDate != null) {
            return 'On or after ' + formatDate(startDate);
        }
        if (endDate != null) {
            return 'On or before ' + formatDate(endDate);
        }
        return null;
    }

    private static void populateRelatedRecords(
        List<Id> nonconformanceIds,
        List<Id> capaIds,
        List<Id> changeOrderIds,
        List<Id> inspectionIds,
        Set<Id> partNcIds,
        Set<Id> lotNcIds,
        Set<Id> partInspectionIds,
        Set<Id> lotInspectionIds,
        Datetime startBound,
        Datetime endBound,
        AssociatedItemsReportData res
    ) {
        if (nonconformanceIds != null && !nonconformanceIds.isEmpty()) {
            for (compliancequest__SQX_Nonconformance__c nc : [
                SELECT Id, Name, compliancequest__Status__c, compliancequest__Lot_Number__c, CreatedDate,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c
                FROM compliancequest__SQX_Nonconformance__c
                WHERE Id IN :nonconformanceIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
            ]) {
                AssociatedItemsRecordInfo ri = new AssociatedItemsRecordInfo();
                ri.id = nc.Id;
                ri.name = nc.Name;
                ri.status = nc.compliancequest__Status__c;
                ri.partNumber = nc.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
                ri.lotNumber = nc.compliancequest__Lot_Number__c;
                ri.matchedBy = matchedBy(partNcIds.contains(nc.Id), lotNcIds.contains(nc.Id));
                ri.createdDate = nc.CreatedDate.format('MMM d, yyyy');
                res.nonconformances.add(ri);
            }
        }

        if (capaIds != null && !capaIds.isEmpty()) {
            for (compliancequest__SQX_CAPA__c capa : [
                SELECT Id, Name, compliancequest__Status__c, CreatedDate,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c
                FROM compliancequest__SQX_CAPA__c
                WHERE Id IN :capaIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
            ]) {
                AssociatedItemsRecordInfo ri = new AssociatedItemsRecordInfo();
                ri.id = capa.Id;
                ri.name = capa.Name;
                ri.status = capa.compliancequest__Status__c;
                ri.partNumber = capa.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
                ri.createdDate = capa.CreatedDate.format('MMM d, yyyy');
                res.capas.add(ri);
            }
        }

        if (changeOrderIds != null && !changeOrderIds.isEmpty()) {
            for (compliancequest__SQX_Change_Order__c co : [
                SELECT Id, Name, compliancequest__Status__c, CreatedDate,
                       compliancequest__SQX_Product__r.compliancequest__Part_Number__c
                FROM compliancequest__SQX_Change_Order__c
                WHERE Id IN :changeOrderIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
            ]) {
                AssociatedItemsRecordInfo ri = new AssociatedItemsRecordInfo();
                ri.id = co.Id;
                ri.name = co.Name;
                ri.status = co.compliancequest__Status__c;
                ri.partNumber = co.compliancequest__SQX_Product__r.compliancequest__Part_Number__c;
                ri.createdDate = co.CreatedDate.format('MMM d, yyyy');
                res.changeOrders.add(ri);
            }
        }

        if (inspectionIds != null && !inspectionIds.isEmpty()) {
            for (compliancequest__SQX_Inspection__c insp : [
                SELECT Id, Name, compliancequest__Status__c, compliancequest__Lot_Number__c, CreatedDate,
                       compliancequest__SQX_Part__r.compliancequest__Part_Number__c
                FROM compliancequest__SQX_Inspection__c
                WHERE Id IN :inspectionIds
                AND CreatedDate >= :startBound
                AND CreatedDate < :endBound
            ]) {
                AssociatedItemsRecordInfo ri = new AssociatedItemsRecordInfo();
                ri.id = insp.Id;
                ri.name = insp.Name;
                ri.status = insp.compliancequest__Status__c;
                ri.partNumber = insp.compliancequest__SQX_Part__r.compliancequest__Part_Number__c;
                ri.lotNumber = insp.compliancequest__Lot_Number__c;
                ri.matchedBy = matchedBy(partInspectionIds.contains(insp.Id), lotInspectionIds.contains(insp.Id));
                ri.createdDate = insp.CreatedDate.format('MMM d, yyyy');
                res.inspections.add(ri);
            }
        }
    }
}

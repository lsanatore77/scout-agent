# Sample Data Log (dev org only)

Sample records made in cqse-golden--dev for demos and testing. Each new record's description starts with SAMPLE DATA where the object has one.

## 16 Nov 2026 · Event intake setup
- Event Questions EQ-001 to EQ-005: the four standard questions (Where Found, Product Affected, Injury, Safety Risk roles) and one extra, "Which test or inspection found it?" (no role). These are setup, not test data.
- Quick Log Categories: Broken Screw (10 in 30 days, same part), Cosmetic Scratch (15, same part), Label Smudge (10, all parts), Damaged Carton (12, all parts), approved by Lou Admin. Setup, from the 25 Oct design.

## 15 Nov 2026 · What Changed story for NC-000153 (hub bond leak, part PTCA-1000)
- NC-000153: Occurrence Date set to 31 Oct 2026 (it was empty; reported 2 Nov); Equipment set to BF-02.
- CHG-000005 (new change order on PTCA-1000): Move bonding fixture BF-02 to the second-shift line. Submitted 10 Oct, Target Completion 17 Oct, Effective 17 Oct (set with the past-date validation rule turned off).
- WI-2210[D] (new controlled document on PTCA-1000): Hub Bonding Work Instruction, cure time cut from 60 to 45 s. Approved 21 Oct, Issued 23 Oct, Effective 23 Oct (same). Both records stay Draft.
- Lot Info BRFULL-UPD-01 (new): PTCA-1000, manufactured 29 Oct.
- Part revision PTCA-1000 Rev A: Effective Date set to 2 Jun 2026.
- Equipment BF-02 (new, Machine, Active) with calibration CAL-000006 on 20 May 2026, next due 20 Nov 2026.
- Existing data used as is: supplier deviation SD-PTCA-05 on the hub component PTCA-3301, in effect 5 Sep 2026 to 5 Mar 2027.

Test records to clean up: CHG-000004 and WI-2210 drafts were rolled back in dry runs and do not exist; NC-000170 (TEST) and its investigation INV-96 are real.

Validation rules turned off by Lou on 15 Nov 2026 to set past effective dates: Change Order Ensure_EffecDate_CanNotBe_PastDate (compliancequest) and Controlled Document CQPLM_Ensure_EffecDate_CanNotBe_PastDate (cqext). Turn both back on afterwards.

## 15 Nov 2026 · Check History story for NC-000153
- NC-000172 (new, Closed 20 Jun 2026): Hub bond leak at pressure test on PTCA-1000, lot BRFULL-0512, occurred 12 May 2026. Description set through Description_RT (CQ copies the rich-text field into Description, so setting Description alone is cleared).
- INV-0000000099 (new, Completed) on NC-000172: Confirmed; root cause Machine, Fixture worn or damaged, "Worn locating pin on fixture BF-02", Verified.
- CAPA-000018 (new, Closed 18 Jun 2026): Replace BF-02 locating pin; the preventive maintenance plan was not changed. Linked from NC-000172.
- Numbers NC-000171 and CAPA-000017 were used up by dry runs and do not exist.
- EFR-000001 (new effectiveness review on CAPA-000018): Complete, Closed-Effective on 22 Jul 2026, rating 4, "No hub bond leaks on BF-02 lots for 30 days after the pin was replaced." Shows the case of a CAPA marked effective whose problem came back. EFR-000000 was used up by a dry run.
- NC-000174 (new, Draft, 15 Nov 2026): SAMPLE DATA. Hub bond leak at pressure test on PTCA-1000, lot BRFULL-1112, 2 defective, occurred today. For trying the triage repeat flag (it repeats NC-000172 after CAPA-000018 was marked effective). NC-000173 was used up by a dry run.

## 16 Nov 2026: FA-0001 tidied for the CEO demo video
- FA-0001 (a8uW40000009G3xIAE): Quantity Affected 240 -> 200 and Quantity Shipped 180 -> 155, to match the lot data (4 lots x 50 built; shipments 42 + 45 + 38 + 30 = 155; on hand 8 + 5 + 12 + 20 = 45).
- Title now names all four lots: "Balloon may fail to deflate - CardioFlow 3.0, lots L26-0901 to L26-0922" (was "lot L26-0908").
- Checked, left as is: the signal Status "New" is not shown on screen; scores of 1.0 are the Escalate cap by design; Trend "Steady" is what CqSignalJob computes when nothing changed since its last run (the job is not scheduled in dev).
- New complaint COM-0000000030 (a1AW4000002iTWbMAM): "Balloon did not fully deflate after inflation", PTCA-1000, lot L26-0908, reported 16 Nov 2026, Draft, account as COM-0000000013 (the external contact was left off: CQ's related insert failed on the contact's state with no country). Then ran CqSignalJob.run() once. Result: SIG-0001 (5 complaints and 2 NCs on L26-0908), SIG-0003 (12 complaints in 90 days) and SIG-0014 (10.0% of units built on L26-0908) read Rising; the rest Steady. Running the job again with no new data turns them back to Steady, so do not run it before recording the demo.
- FA-0001 Key Message: the trailing "Why: tse" (a typing slip) now reads "Why: the balloon may not fully deflate after inflation."
- PTCA-1000 complaints filled in for the demo (one save each: CQ's complaint trigger refuses several complaints in one transaction): COM-0000000001, 03, 04, 05, 06, 07, 10, 11, 12, 13, 20, 30. Each now has a title, reporter's words (Description As Reported), a short Description, occurrence and aware dates after the lot's ship date, Country US, and as Account the hospital that received that lot per Lot Shipment (Riverside General, St. Anne, Lakeview Heart, Northgate Regional, Cedar Valley; all named "[Test]"). Test text removed ("TEST", "Debug Testing", "Another", "Testing PHR", "B&R Full Test Complaint 01", and the pasted AI report in COM-07's Description). COM-10, 12 and 13 had their contact (Fred Ames and Sons) cleared so the hospital could be set. Lot, part and status unchanged, so the signals are unchanged. COM-05's occurrence moved to 14 Oct (it was before its lot shipped).
- FAR-0006 (a8vW4000001EkIXIA0, With Committee): test text replaced. Review draft moved to version 2 (step 4) with realistic checklist answers (left Yes, injury No, could harm Yes, more lots Yes, detect before use No, root cause Not known), a real health hazard summary and rationale, joining FA-0001 (Class II, matching FA-0001) instead of "new / Class I". Health Hazard Summary, Outcome Rationale and Review Summary fields set to match; Risk Score 95 -> 85 to match what the screen calculates today (severity is now 15/25 because NC-000162's triage risk is Medium).
- FAR-0003 rationale: "180 units are with customers" now "155 units of the affected lots have shipped to customers" (matches FA-0001).
- NC-000162 (a36W4000000tIFdIAM) made to fit lot L26-0908 (50 built, 45 shipped, 5 on hand): description now "final functional test on the 5 units still in finished goods found 3 slow to deflate; 45 had shipped; the 5 are on hold". Defective Quantity 12 -> 3 on the NC and on defect DEF-00004 (was 240); Lot Quantity 240 -> 5 on the NC and on impacted product 000000060 (order mattered: CQ checks defect quantity <= lot quantity). Disposition at a Glance now reads 5 left to dispose.
- Not changed (CQ blocks it): the completed dispositions on NC-000120 (lot BKUP-TEST-001), NC-000153 (BRFULL-UPD-01) and NC-000155 (BRFULL-UPD-03). CQ's rule "A disposition has been completed for the part and lot. So, no changes can be made to part or lot number." They still show under Dispositions on This Part.
- FAR-0006: Quantity Affected 12 -> 3 and Quantity Shipped -> 45 (match NC-000162 and lot L26-0908); stored Risk Score 85 -> 82 and Review Summary to match (Quantity affected now 2/10).
- Disposition history for PTCA-1000 (Dispositions on This Part on the Disposition screen): 10 new closed NCs, each with a completed disposition on a real lot, created by anonymous Apex one NC per run (CQ's triggers pass 100 queries with five in one run). Created Date backdated to the occurrence date (allowed in dev) so the monthly charts stay right; NC-000176 was the trial run and keeps today's Created Date (CQ locks it from deletion). NC Status and Stage set to Closed directly.
  - NC-000181 L25-1103 deflation, Scrap 2 (20 Nov 2025); NC-000182 L25-1201 kinked shaft, Scrap 3; NC-000183 L26-0105 marker band, Rework 3 and Scrap 1; NC-000176 L26-0202 balloon protector, Rework 2; NC-000184 L26-0302 deflation, Scrap 2; NC-000185 L26-0406 pouch seal width, Scrap 6; NC-000186 L26-0504 label misprint, Rework 10; NC-000187 L26-0601 hub burr, Use As Is 3 (with justification); NC-000188 L26-0706 coating spots, Scrap 2; NC-000189 L26-0803 deflation, Scrap 1 (19 Aug 2026).
  - Test dispositions moved down the list: completed date of NC-000120 (BKUP-TEST-001) set to 2 Jun 2025 and NC-000153's two (BRFULL-UPD-01) to 12 May 2025. NC-000155's (BRFULL-UPD-03, 15 Nov 2026) could not change: its NC is Complete ("Referenced NC record Status does not support the action performed"), so it still heads the list.
- Committee users renamed for the demo (names and titles only; usernames and logins unchanged): Test Manager B (005W400000TnlrWIAR, was Production Manager) -> Elena Ruiz, Medical Director; Test User (005W400000UbhkfIAB) -> Marcus Bell, Operations Manager; Learner 01 (005W400000TnlujIAB, was Quality Control Analyst) -> Priya Shah, Regulatory Affairs Manager.

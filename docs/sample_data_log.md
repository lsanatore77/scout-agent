# Sample Data Log (dev org only)

Sample records made in cqse-golden--dev for demos and testing. Each new record's description starts with SAMPLE DATA where the object has one.

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

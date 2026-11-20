# E-Signature: Next Steps (Committee Approval)

State on 2026-11-19:

- Field Action Review is registered with CQ e-signature: `CqFarEsigPolicies` (handler) + `Field_Action_Review_Record_Activity__c` (signature log) + CQ Extension Esig Policy Provider row `CqFarEsigPolicies` (added by Lou).
- CQ Admin > eSig Settings lists Field Action Review with actions Committee Approve (`approve`) and Committee Send Back (`reject`).
- Policy saved: Field Action Review · Committee Approve · signature required · comment required.
- **Finding:** CQ's Approve/Reject for these approvals opens our record page, and CQ does not enforce the policy server-side. Our workspace Approve approved FAR-0001 with no signature row. Our page must collect the signature.

## Found in the Live Test (2026-11-20)

- `retriveEsigSetting(reviewId, 'approve'|'reject')` returns enabled, required and comment as set in eSig Settings; purpose = the action label.
- Wrong password: `validateEsig` throws (Salesforce shows only "Script-thrown exception"). We show "Signature not accepted. Check your password and try again."
- Right password: `validateEsig` returns a validation token but writes **no** Record Activity row for an add-on record type, and `performActionOnObject` writes none either.
- So `CqEsigBridge.sign` writes the row itself once CQ has returned a token and `isTokenValid` confirms it: action, purpose, comment, signer, and a SHA-256 fingerprint of the token in Transaction_Id__c (the token itself is not kept). CreatedDate/CreatedBy are the signature time and signer.

## Done on 2026-11-20

- Live test on FAR-0001 / APR-00000068 passed: missing comment refused; a saved password chosen from Edge's list cleared; wrong password refused; real password signed (FRA-000001) and approved; FAR-0001 Decided.
- Password box is a text box drawn with dots (`-webkit-text-security: disc`) so the browser does not offer saved passwords; it stays a real password box where a browser cannot draw the dots. Note: a screen reader may read the typed characters of a text box; revisit if accessibility review asks.
- Messages about your seat show under its buttons.
- In Apex tests CQ's `validateEsig` accepted a wrong password (no exception), so tests cannot prove refusal; the live test on FAR-0001 is the proof. CqEsigBridgeTest checks only that refused = no row, accepted = exactly one row.
- Next: where signatures show (proposal on the design canvas, board "Where Signatures Show").

## To Build

1. **Server-side guard** in `CqFarCommittee.decide()`: ask CQ whether the action needs a signature (`compliancequest.SQX_Esig_Policy_Provider.retriveEsigSetting(reviewId, action)`); if required and no valid signature, refuse. Covers the seat buttons and the "As admin" links. (`retriveEsigSetting` needs a UI session: it fails from anonymous Apex.)
2. **Seat change**: when required, the seat shows purpose of signature, comment (required when the policy says so) and password; CQ verifies (`validateEsig(objId, action, username, password, comments)`, or the `generateValidationToken` / `performActionOnObject` token route), writes its Record Activity row, then we act. No policy: one click as today.
3. **Deter password autofill** on that field:
   - `autocomplete="new-password"`, unique name/id, no username field beside it, not inside a login-style form;
   - detect autofill (`:autofill` / `:-webkit-autofill` via an animation or input check) and clear it with "Please type your password to sign";
   - never pre-fill or keep the value: clear after every attempt, never store or log it;
   - **refuse a password that was not typed**: accept Sign only when the value came from key presses; if it was autofilled or pasted, clear it and ask the signer to type it. The aim is only to stop casual autofill, not a determined bad actor.
4. Committee card: show the assignee's current name (`cqext__CQAPR_Assignee_User__r.Name`), not the saved `cqext__Assignee_Name__c`.
5. Test: Lou is the only Field Action Emergency Approver, so an emergency approval on a test review lets Lou sign with his own password.

## Signatures and Audit Trail (built 2026-11-20)

- Two tables, our own (CQ's own modules keep one Record Activity per module holding both; CQ wrote nothing for our record type; whether CQ should record ours is parked).
- Signatures: Field_Action_Review_Record_Activity__c (FRA-...). One row per signed committee action. Locked: no edit or delete for anyone (CqFarSignatureLock). New: Verified By (Password (CQ); later Company Sign-In (Entra)) and Signed Content Fingerprint (SHA-256 of outcome, rationale, risk, hazard, summary, emergency at signing).
- Audit trail: Field_Action_Review_Audit__c (FAU-...). One row per create, field change (field, old, new), delete, and signature (points to the FRA row). Who as name + username text; Request Id groups one save. Lookup clears on delete; Record Id/Name keep the link. Locked (CqFarAuditLock). Written in system mode by CqFarAudit; people have read only.
- Not logged: system fields, formulas, Review_Draft__c (workspace autosave).
- A review with signatures cannot be deleted (it would take its signatures with it, master-detail).
- Not shown on screen yet: see the Where Signatures Show board; an audit trail view still to be designed.

## Agreed Direction: Accessible Signing (2026-11-20, nothing built yet)

- WCAG 2.2 SC 3.3.8: a typed-only password (autofill/paste refused, W3C failure F109) is fine only if there is another way to sign without a memory test, reachable from the signing page by the person themselves.
- On the seat, two ways to sign:
  - Sign with Password: typed only, autofill/paste refused (today).
  - Sign with Company Sign-In: Entra (passkey, phone approval, password managers allowed on Entra's page). Needs the Entra SSO project.
- The alternative is visible on the seat ("Other ways to sign" or a second button), keyboard and screen reader friendly, no admin and no reason needed.
- A personal signing preference opens the seat on the person's chosen method. An admin may preset it for people who asked for an accommodation, with their agreement. Never the only route: not everyone discloses, needs change, new hires and customer users are unknown.
- Each signature records the method (Verified By: Password (CQ) / Company Sign-In (Entra)).
- Password box goes back to a real password box (screen readers announce it as a password); Edge's saved list returns but picking from it is still refused.
- Conditions: the tenant's Entra keeps password managers/passkeys on; the freshness check lets people retry without losing their work.
- Until Entra is connected: internal demo only, not described to customers as accessible.
- Separate: general accessibility review of the workspace (colour-only meaning, keyboard access to the signal table rows, focus, 11px header contrast, announcing banner messages).
- Next: mockup of the two-method seat on the Signing board before building.

## Where Things Stand (2026-11-20, afternoon)

- Signing on the seat shows a solid cover with a spinner and "Checking your signature with CQ and approving..." over the comment, password and buttons until CQ answers (cqFieldActionReviewWs, deployed to dev).
- Field Action Review (New) on the shared workspace pieces is ahead of Old: e-signature, committee layout and the signing cover are only in New. Record page in dev: Old (everyone) and New (Lou only) tabs.
- Waiting on Lou: where signatures show (board "Where Signatures Show": A on the seat, B a table on the decided review, C a related list) and how the audit trail is viewed.
- Then: compare Old and New, make New the record page for everyone, retire cqFieldActionWorkspace; next workspace to convert onto the shared pieces (suggested: Field Action).

## Parked (2026-11-20, evening)

- **Signing speed.** The last seat's Sign and Approve took about 12 seconds in Lou's recording. Part is CQ (password
  check, approval engine); part is ours: closing the approval decides the review and the request reads the whole
  review view (signals, records, trend, committee) about four times. Measure first, then read it once and reuse it.
- **Audit trail note for older reviews** (offered): when a review has no CQ.AI Suggestions, say it was decided before
  suggestion tracking began (Nov 20, 2026).

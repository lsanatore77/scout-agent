# E-Signature: Next Steps (Committee Approval)

State on 2026-11-19:

- Field Action Review is registered with CQ e-signature: `CqFarEsigPolicies` (handler) + `Field_Action_Review_Record_Activity__c` (signature log) + CQ Extension Esig Policy Provider row `CqFarEsigPolicies` (added by Lou).
- CQ Admin > eSig Settings lists Field Action Review with actions Committee Approve (`approve`) and Committee Send Back (`reject`).
- Policy saved: Field Action Review · Committee Approve · signature required · comment required.
- **Finding:** CQ's Approve/Reject for these approvals opens our record page, and CQ does not enforce the policy server-side. Our workspace Approve approved FAR-0001 with no signature row. Our page must collect the signature.

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

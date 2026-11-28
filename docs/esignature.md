# Electronic Signatures: the Standard

Every electronic signature in our screens works the same way. Field Action Review (committee seats) and Field Action Closure (Recall Coordinator) both follow it. A new signature follows it too.

## What the signer sees

The shared seat component `c-cq-sign-seat`:

- The seat name, the person, their status, and a quote of what is being signed.
- **The meaning** of the signature, written out ("By signing, I confirm…").
- The **purpose of signature** from the CQ policy.
- A **comment** box, required when the CQ policy says so.
- A **password** box that must be typed: saved or pasted passwords are cleared and the signer is asked to type it.
- One button that signs and acts (for example "Sign and Close"), with a spinner while it runs.
- Other states: someone else's seat (read only), already signed (who, when, comment), and **unknown policy** (the action is blocked until CQ answers).
- When the CQ policy says no signature is needed, the seat is a single button with no password.

Admin links (for example "As admin") go in the seat's slot.

## How it works

| Part | Job |
|---|---|
| `c/cqEsign` (JS) | `askPolicies(recordId, actions, key)` asks CQ once per object and action and caches the answer for 8 hours in the browser session. `anyRequired`, `anyUnknown`. |
| `c-cq-sign-seat` (LWC) | The seat above. The page passes `submit`, a function that returns a Promise; the seat collects comment and password and hands them to it. |
| `CqEsign` (Apex) | `getPolicies` for the page. `sign(recordId, action, comment, password, isSigner)`: unknown policy → error; not required → returns false; not the signer → refused; then requires the password (and the comment when the policy says so) and signs. |
| `CqEsigGateway` → `CqEsigBridge` | The only code that calls CQ (`retriveEsigSetting`, `validateEsig`, `isTokenValid`). Tests swap the gateway for a fake. |
| `CqSignable` (interface) | One class per signed object writes its signature row: `signatureCount`, `record(recordId, action, comment, purpose, tokenHash)`. |
| `CqFarEsigPolicies` | Registers our objects and actions with CQ so they appear in CQ Admin > eSig Settings. One CQ Extension Esig Policy Provider row covers every object it lists. |

The server always checks again: a page cannot skip the signature by calling Apex directly, because the action's Apex method calls `CqEsign.sign` first.

## Adding a signature to a new object or action

1. **Signature log object**: `<Object>_Record_Activity__c`, a copy of `Field_Action_Record_Activity__c` (master-detail to the record, Activity Code picklist with the action values, Purpose, Comment, Transaction Id = SHA-256 of CQ's token, Verified By, Signed Content fingerprint). Give users Create and Read only.
2. **Lock it**: rows can never be edited or deleted (see `CqFarSignatureLock`), and the signed record cannot be deleted once it has a signature (see `CqFieldActionKeepSigned`).
3. **`CqSignable` class** for the object (see `CqFaSignable`, `CqFarSignable`), with a fingerprint of what was signed.
4. **`CqEsigBridge.SIGNABLE`**: add `'<Object>' => '<CqSignable class>'`.
5. **`CqFarEsigPolicies`**: add a provider for the object (its Record Activity object and Activity Code field) and a parent link in `setParentByChildRecordId`.
6. **Apex action**: one method that checks who may act, calls `CqEsign.sign(...)`, then does the action. Remove `@AuraEnabled` from any older method that acted without signing.
7. **Page**: `c-cq-sign-seat` with `policy-key`, `actions`, `meaning`, and `submit`.
8. **Audit trail**: `CqAuditTrail` shows a Signatures list and a "Signed: …" timeline entry for each row.
9. **Tests**: use a fake `CqEsign.gateway`; prove a blocked action is never signed, a signature writes exactly one row, and the delete guard holds. The real password check is proved by a live test, because CQ accepts any password inside Apex tests.
10. **CQ setup (Lou)**: in CQ Admin > eSig Settings, create the policy for the new action (required, comment, purpose).

## Demo Mode (Field Action Closure)

Setup > Custom Settings > **Field Action Settings** > Manage > the org default > **Demo Mode**.

- **Off (real use):** every Closure checklist item must be done before the Recall Coordinator can sign and close, including units recovered, customers confirmed and recall tasks completed.
- **On (demos):** units, customers and recall tasks show as **!** and do not stop closing. The scope, strategy, held stock, verdict and CAPA still do. The Signature card shows a **Demo Mode** tag, and a signature made in Demo Mode is saved with Verified By "Password (CQ) · Demo mode" and shows in the Audit Trail as "signed in Demo Mode".

## In use

| Object | Action | Signer | Log |
|---|---|---|---|
| Field Action Review | Committee Approve (`approve`), Committee Send Back (`reject`) | each committee seat | Field_Action_Review_Record_Activity__c (FRA-…) |
| Field Action | Close Field Action (`close`) | the Field Action owner (Recall Coordinator) | Field_Action_Record_Activity__c (FAA-…) |
| Nonconformance | Completing Disposition (`completedisposition`, CQ's own NC action) | the dispositioner, once for every lot and split (Disposition workspace, Dispose by Lot) | CQ's NC Record Activity (`compliancequest__SQX_NC_Record_Activity__c`), written by `CqNcSignable` with what was signed for |
| Nonconformance | Submitting Investigation (`submitinvestigation`, CQ's own NC action) | the investigator, on Complete Investigation or Submit for Approval (Investigation workspace, Conclusion) | the same NC Record Activity, with the conclusion, root causes and number of actions signed for |
| Action | Completing Action (`implementation_complete`), Skipping Action (`implementation_skip`), CQ's own action codes | the assignee of the correction (Correction workspace, on the CQ action) | CQ's Action Record Activity (`compliancequest__SQX_Action_Record_Activity__c`), written by `CqActionSignable` with what was signed for |

**Which actions ask for a signature (CQ before 16.9.0, as in dev):** only those with a row in CQ Admin > eSig Settings with Required on. With no row the seat shows the plain button and nothing is signed or logged, the same as CQ's own screens. Dev has rows for Close Field Action and Committee Approve only; Completing Disposition and Submitting Investigation need rows added by an admin to ask for a password. From CQ 16.9.0, every Approve, Reject, Recall, Reassign and Adjust Approval asks for a signature by default, with no row (Reject also needs a comment); the seat follows that automatically because it asks CQ on every action (Confluence: "eSig Design for Approval policies / Default/ non Default policies").

**No session, no signature check.** CQ's `retriveEsigSetting` needs a browser (UI) session. Called from the API or anonymous Apex it throws an `UnexpectedException` that cannot be caught, and the whole request rolls back. In the app there is always a session; a flow, batch or API caller cannot use CqEsign (found 27 Nov, completing an investigation from the API).

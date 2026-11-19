# Centralising styles into cqStyles

Audit page: https://claude.ai/artifact/3FHHFJVoKeUeVJ8pUwQg6A (19 Nov 2026)

## Standards agreed
1. Step rail title: "<star> CQ.AI <Name> Steps" everywhere, on one line. Rail is 244px (220px was not wide enough for Investigation).
2. Back and Next: bottom right on every step. Field Action Scope still has them at the top (to move in pass 2).
3. Table header: small quiet style (11px bold, muted, light surface). The one named exception to the 13px minimum.
4. Next Steps with four cards: two rows of two.
5. Suggested chip not chosen: outline only. Done in cqStyles (.cq-chip.ai).
6. Dispose by Lot: no planned count. Red text, no box, under the rows:
   - one row over: "Your Disposition Quantity is N."
   - split rows over: "Your Disposition Quantity is N, please make sure your splits are equal to the Disposition Quantity."
   - under: "You've entered P, there are R remaining items left to Disposition." Fewer is allowed today.
   - Later: disposition stays open until decided; entering fewer will need a justification.
7. Stray colours: map to nearest theme value, bring back only the ones with no close match.

## Pass 1, step rail
- cqStyles STEP RAIL section: deployed.
- Deployed and matched (19 Nov): all six workspaces (Disposition with item 6, PHR, Field Action, Field Action Review, Investigation, Triage).
- Triage also carries item 4: four Next Steps cards sit two by two (.cards:has).
- Still to look at on screen: PHR, Field Action, Field Action Review, Investigation, Triage.

## Passes to come
2 workspace frame (incl. item 2) · 3 table and pager (item 3) · 4 popup, cards (item 4), notes, links, rows · 5 stray colours

## Change of method (19 Nov)
Every edit means sending a screen's whole files to the org, so pattern-by-pattern passes would send each screen five times.
Instead: all the shared patterns are now in cqStyles (frame, table, pager, popup, small pieces, chip mark), and screens are
converted one at a time, each sent once and checked on screen. Converted so far: cqDispositionWorkspace (75 rules down to 41), cqInvestigationWorkspace (162 down to 94), cqFieldActionManager (111 down to 71; Scope buttons now in the footer; checked on screen), cqFieldActionWorkspace (170 down to 126), cqTriageAssistant (193 down to 134; keeps its own box and popup footer because it is also a popup), askCqWorkspace and askCqRecordsDemo (PHR; work area stays flush, so its footer keeps local side padding).
Order: Investigation, Field Action (with Back/Next moved), Field Action Review, Triage, PHR, then the smaller components.

## Conversion finished (19 Nov 2026)

Every component now takes the shared pieces from cqStyles. Custom rules: 1,666 at the audit, 1,245 now; cqStyles has 176.

Converted in the last pass: Find the Cause, Field Action Strategy / Recovery / Closure, Field Action Review card, Event Intake, Event Intake Chat, Event Review, Triage at a Glance, Triage Workspace, PHR Lead Select and Lead Lists.

Left as they are, because nothing in them maps to a shared piece without changing how the screen looks (for the per-screen review):
- cqIntakeConversation and askCqPopover: chat screens with their own bubbles, chips and buttons, and hard-coded purples.
- associatedItemsReport and phrQmsRecordsPanel: SLDS tables with a Previous / Next pager, not the numbered cq-pager.
- phrLeadPackage, phrChecklist, phrMissingData, cqPartPicker, cqLotPicker, cqAiWhy: small, screen-specific.

Open points for the per-screen review:
- Field Action Strategy and Recovery use a tighter table (.ht) than cq-tbl; decide whether a compact table becomes a shared variant.
- The Field Action tabs put the step title in a row with its status pill, so they override the intro's top gap locally.
- Find the Cause popups are now the shared 560px width (were 640px).
- Event Intake's footer moved inside the work area like the other workspaces.
- Repeated local pieces still without a standard: .rk, plain .card, .ch/.cn/.ct card heads, .tabs/.tab, .plainbtn/.smalllink, .ownbox/.plainbox.

## Identical-rule cleanup (19 Nov 2026, in progress)

Rules that were written word for word in several components are moving into cqStyles under cq- names. No visible change intended.

Done:
- Search picker (part and lot pickers): all styling is now .cq-pick* in cqStyles.
- Chat panel cards (checklist, missing data, worth reviewing, lead lists, lead select): .cq-panel, .cq-panel-intro / -error / -empty / -card, .cq-panel-pager / -pages.
- Shared helpers added: .cq-opts(.tight), .cq-fields, .cq-splitline, .cq-sechead, .cq-infobox, .cq-sub(.block), .cq-ai-head, .cq-ai-icon, .cq-ai-says, .cq-nowrap, .cq-mt16, and the errbox / okbox / sm0 / owner / growf adjustments.
- Using the helpers: Disposition, Investigation, Find the Cause, Field Action Closure.

Still to do (same helpers, their own local copies are still in place and still work):
- Triage Assistant, Field Action Workspace, Field Action Manager, Recovery, Strategy, Event Intake.
- Pieces shared by only two screens (Field Action Manager / Workspace cards and rows, Triage / Field Action Review decision card, Disposition / Investigation glance columns, the lvl risk colours, which are set from script).

Left out on purpose: .cq-field input.date at 170px is not shared, because Triage uses a different width.


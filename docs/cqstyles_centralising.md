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
- Deployed and matched: cqDispositionWorkspace (with item 6), askCqWorkspace, cqFieldActionManager.
- In repo, NOT yet deployed (html + css each): cqFieldActionWorkspace, cqInvestigationWorkspace, cqTriageAssistant.
  Until then those three keep their old rail in the org and look as before.

## Passes to come
2 workspace frame (incl. item 2) · 3 table and pager (item 3) · 4 popup, cards (item 4), notes, links, rows · 5 stray colours

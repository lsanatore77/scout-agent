# Event Review: design notes (not settled)

Working ideas from Lou, 16 Nov 2026. Nothing here is decided or built yet.

## How the reviewer works (Lou's current thinking)
- The event reviewer logs into Salesforce and opens an **Events app**, which has a **workspace just for event reviewers**.
- New events are owned by a **review queue**. Anyone in the reviewer group can see the queue.
- In the workspace the reviewer sees two lists on the same screen:
  1. **The queue**: every event waiting for review (urgent first, then oldest). Each one has **Take Ownership and Initiate**, which makes that reviewer the owner and starts the review. Once taken, the event leaves the queue so two people never review the same one.
  2. **My event reviews**: the events assigned to that reviewer, worked one by one.
- How the review itself is performed is still being worked out. The 25 Oct mockup and mock_events_v2 (Event Review: what it becomes, CQ.AI suggests, confirm) are the starting point.

## Decided (16 Nov 2026)
- **Quality Event stays its own object, not Case.** Case is the inspiration: we replicate what is needed (queues, team, escalation, a clock) inside Quality Event, so it ships as part of CQ, not as Salesforce standard Case.
- **Queues:** built to handle several review queues, but start with one.
- **Give it back:** a reviewer who took ownership and initiated can give the event back; it returns to the queue for anyone in the group to take.
- **E-signature:** the Reviewed e-signature belongs at this step, and comes in with the approvals work.

## Think of an event like a case (16 Nov 2026)
Lou: an event works like a Salesforce Case: queues, a case team working it together, and escalation when it waits too long.
What Case has that we would otherwise build: queues and assignment rules, case teams (roles on one record), escalation rules (reassign or notify when it sits too long), Omni-Channel routing, and entitlements with milestones (a clock, which fits the complaint clock from the aware date).

## The clock (Lou likes it, 16 Nov 2026; to design)
- Starts at the event's **aware date**, not when it was typed in or picked up.
- Targets per kind of event, set in setup (for example: urgent reviewed within 1 day, others within 5; a complaint's reporting deadline counted from the aware date).
- Shown on the queue and the reviewer's own list as time left, amber when close, red when overdue.
- **Decided:** when the clock runs out, the event escalates **automatically** (a scheduled job checks the clocks; no one has to press anything). What escalation does (notify whom, reassign to whom, how many levels) is still to design.

## Open questions
- Can a reviewer pass an event straight to a named person, or only back to the queue?
- Does Take Ownership and Initiate change the event's status (for example to In Review)?

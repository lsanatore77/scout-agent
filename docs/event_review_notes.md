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
- **Queues:** built to handle several review queues, but start with one.
- **Give it back:** a reviewer who took ownership and initiated can give the event back; it returns to the queue for anyone in the group to take.
- **E-signature:** the Reviewed e-signature belongs at this step, and comes in with the approvals work.

## Open questions
- Can a reviewer pass an event straight to a named person, or only back to the queue?
- Does Take Ownership and Initiate change the event's status (for example to In Review)?

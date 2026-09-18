# Design

## Context

See proposal.md - Why. Three constraints shape the approach.

The app learns the helper's state from one place today: `SMAppService.status`,
read synchronously on every refresh. That answers "may the helper write", not
"is the helper there", and the two answers part company exactly when a
registration goes stale.

A request to a system daemon is delivered by the system's on-demand launch. When
that launch fails, the failure happens before any code of the daemon runs, and
nothing reports it to the client: the connection is neither invalidated nor
answered. The client cannot be told, so the app has to ask.

The state value, the write state and the menu are values in `HazmatAppSupport`
with tests over them; the shell model is a thin scene-facing object. Whatever the
new state means has to be decidable from values, not from the window.

## Goals / Non-Goals

**Goals:**
- A helper that cannot be reached never reads as ready, and the state names the
  action that puts it right.
- A write that cannot be answered reports within a bound the app documents, and
  its words name the repair.
- The check never blocks the window and never repeats needlessly.

**Non-Goals:**
- Making a stale registration impossible. Only the system decides which bundle a
  job was registered from; the app can notice and repair, not prevent.
- Signing, packaging and notarization, which remove the underlying cause for a
  shipped build and are a separate change.
- Replacing `SMAppService.status`: approval is still what decides between not
  registered, awaiting approval and enabled.

## Decisions

**One presence call on the existing interface.** The interface gains
`checkIn(withReply:)`, which carries nothing and answers nothing but its own
arrival. A separate XPC channel, a versioned status call, or a plist the daemon
writes would each add a second thing to keep in step; the existing interface
already verifies the caller's identity for every connection, so the check
inherits that verification for free. The call carries no request, so the
capability's rule - a request carries finished bytes and the state they were
planned from - is untouched, and the boundary test that pins the interface's
shape is extended rather than relaxed.

**Reachability is a value beside the approval state.** `HelperReachability` has
three cases: answering, silent, and refused with a reason. The state mapping
(`HelperState.state(for:reachability:)`) is a pure function, so every combination
is a test. The refusal case is not a separate state: a helper that rejects this
app is, from the app's side, a helper that did not answer it, and the repair is
the same. The reason is kept in the value so the notice can quote it.

**The check is recorded, not computed per redraw.** `refresh()` runs on every
selection and every store change, and a check costs a round trip that can take
the full bound when the helper is gone. The shell keeps the last answer and the
time it arrived, checks on launch, checks again once an answer is older than a
documented interval while the helper is answering, and otherwise checks only on
an event that is evidence of change: a register, a repair, or a write that did
not succeed. The check itself runs in a detached task, one at a time, and the
answer is applied on the main actor only when it differs, and an answer that is
known is never replaced by the registration's word. Nothing is presented before
there is an answer to present: the first check runs on the calling thread while
the model is built, which costs the bound only when the helper is not there, and
nothing at all when it is.

**The write bound shrinks and its words carry the remedy.** The write waits at
most ten seconds instead of thirty. The write itself is an atomic file
replacement, so a healthy helper answers in milliseconds; a bound reached means
the helper was never launched. The failure reads as such and names the repair
instead of leaving the user with a spinner and a sentence about time.

**Installing and repairing are one sequence, and the removal is its last resort
rather than its first move.** The removal is not free, and it was the step that
went wrong first. Removing the record the system keeps for the helper leaves that
record *disabled*, and a registration that lands while it is disabled is refused
in a way no retry clears - so the repair that began by removing left the helper
further from running on every attempt. Registration itself is what refreshes the
record from the bundle it is registered against, which is enough to make a job the
system previously refused launch: measured on the development bundle, the record
that was refused and the record that launched are the same one, and only the
registration in between differed. The sequence therefore registers, asks, and
removes only when the answer is that nothing answered - which is the case that
needs a job the system still holds to be replaced. Everything after that step is shared: register until the system accepts it,
ask whether the helper answers, and, when it does not, run the sequence once more
with the removal. A helper that answers is never touched again.

**Repair is remove, register, check - twice if the first pass is refused.** The
registration is what the stale job belongs to, so registering on its own cannot
replace it; removing it first removes the job the system can no longer start, and
the registration that follows is what pairs the job with the record the system
keeps. Two properties of that sequence were measured rather than assumed. The
system finishes a removal after the call returns and refuses a registration that
lands inside that window with a refusal that the same call does not produce a
moment later, so the registration is asked again, bounded, and only retried for
refusals that asking again can change. And refusing to launch a helper whose
record is stale is *what makes the system replace that record* - so the job built
before the replacement names a record that no longer exists, and the pass after
the refusal is the one that can succeed. A repair therefore runs that sequence
again when the check did not come back as an answer, bounded at two passes, which
is what a user otherwise does by repairing twice. It needs no confirmation: it
touches no file. A refusal that survives the retries is reported with its cause
and with the two ways out - allow the helper in Login Items & Extensions, or
remove it and install it again.

## Risks / Trade-offs

- The system's approval prompt may return after a repair → the state reports
  awaiting approval and the sheet keeps the action that opens the settings pane.
- A helper that dies between checks reads as ready until the next event → the
  staleness bound bounds the window, and any failed write checks immediately.
- A repair runs system calls that take seconds, and the pass it does not need
  costs a removal and a registration → it runs off the main thread behind a
  notice, the state stays what the last answer made it, and a helper that answers
  is not repaired further.
- The bound on passes is a judgement, not a guarantee: a helper whose bundle
  never stops changing can still fail both → the outcome is reported as what the
  last check found, and the remedy stays in the window.
- Removing a registration leaves the system's record for the helper disabled, and
  a registration that lands while the record is disabled can be refused in a way
  no retry clears → an installation therefore never removes, and a refusal that
  survives the retries is reported with the way out rather than retried forever.
- An unregistered or unapproved helper is never checked, so a repair offered
  from those states registers rather than repairs → the state mapping takes the
  approval state first and the check only refines "enabled".
- The check adds a round trip on launch → it is bounded by the same small bound
  and runs off the main thread, so the window opens regardless. Until the first
  answer lands, a wedged helper reads as it did before this change, and a write
  started in that window is what reports the repair.
- A test cannot use the installed daemon, so the client takes how it reaches the
  helper as a value: the app passes the mach service, and a test passes a
  connection to a listener it holds. The alternative - testing only the state
  mapping - would leave the reply, the handlers and the bound unexercised.

# Proposal

## Why

Apply can sit behind a spinner for thirty seconds and then fail with "the helper
did not answer in time" while the window still reads "Writes ready". The state
comes from the approval alone, so a helper that the system can no longer start is
indistinguishable from one that works, and nothing in the app offers the one
action that puts it right. A registered helper stops being startable in a way
that is invisible to the app: the system records the bundle a job was registered
from, and replacing or moving the app bundle leaves that record pointing at an
identity nothing answers for. The daemon is then never launched, no reply is ever
sent, and the client waits out its whole timeout before reporting a failure that
names neither the cause nor a remedy.

## What Changes

- The privileged interface gains one call that answers whether the helper is
  there. It carries no request, so it keeps the boundary rule that a request
  carries finished bytes and the state they were planned from, and nothing else.
- The helper's state gains a fourth value: registered and approved, but not
  answering. The app derives the state from the approval *and* a presence check,
  so "Writes ready" means the helper answered.
- A repair action removes the registration, registers the helper again and
  checks presence once more, reporting what each step found. It is offered
  wherever the helper's state offers an action today.
- A write is reported as failed within a documented bound when the helper does
  not answer, and the report names the repair. A write that fails is followed by
  a presence check, so the state follows what was just learned.
- The presence check costs no window responsiveness: it runs off the main thread,
  one at a time, and is not repeated on every redraw.

## Capabilities

### New Capabilities
None.

### Modified Capabilities
- `privileged-write`: the helper's visible states gain "registered but not
  answering", "enabled" comes to mean the helper answered, and the check, the
  repair and the bounded wait become requirements of the privileged boundary.

## Impact

- The XPC interface between the app and the daemon gains a third method; both
  sides ship together, so no version negotiation is needed.
- The daemon answers the check after the same caller verification it already
  applies to writes.
- The app's helper state, the write state's blocked cause and remedy, the
  helper sheet, the status item's menu, the Hosts menu and the model gain the
  repair path.
- Nothing changes in the composition, the block format, the store, or what the
  privileged side may write.

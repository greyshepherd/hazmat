# Design

## Context

Constraints that shape the approach. See proposal.md for motivation.

- The composition layer already publishes a byte contract: a resolved set renders
  to a block with versioned markers, and that block can be located and spliced
  without parsing a single host entry. Nothing in the privileged path needs to
  understand hosts grammar.
- The pure core imports no UI or privileged framework and writes nothing. Its
  strip path is injective: a splice adds exactly one separator newline before the
  block, and strip removes the block together with it, so a read-modify-write
  round trips byte for byte.
- The splice is deliberately position-agnostic, so where the block lands is still
  an open input, and the previous change recorded that it must be measured before
  this one ships.
- `/etc/hosts` is a regular file owned by root, mode 0644, in a directory other
  tools also write. Reading needs no privilege; writing does.
- A daemon registered through `SMAppService` must live inside a code-signed app
  bundle: its property list goes in `Contents/Library/LaunchDaemons`, an
  administrator must approve it once in System Settings, and until that approval
  it cannot be bootstrapped or run. The bundle that will host it does not exist
  yet - the repository is a SwiftPM package with one library target, and SwiftPM
  cannot build an app bundle.
- Deployment floor for this change: macOS 15.
- The precedent to avoid: `cp` plus `chmod` escalation leaves an access-control
  list on the file that blocks every other writer.

## Goals / Non-Goals

**Goals:**

- Read the live file, place the block at a chosen position, and hold exactly the
  bytes to write, verified before anything is replaced.
- Report drift between the live block and the store, and make overwriting it a
  deliberate act.
- Make the write atomic, explicitly owned, free of any access-control list, and
  reversible with the strip path that already exists.
- Keep the privileged surface minimal: finished bytes in, a result out, one fixed
  target, no parsing, no shell, no path from the caller.
- Keep everything except the final write testable without root, and keep the real
  write a deliberate, human-approved step.
- Measure the resolver's duplicate handling and record the answer.

**Non-Goals:**

- Distribution concerns: signing identity, notarization, installers, and updates.
  The bundle assembled here is a development bundle used to verify this change.
- The menu bar item, profile editing, and the resolved view.
- A command-line product surface.
- Fragment authoring, and fragment discovery outside the configured directory.

## Decisions

**1. A development app bundle assembled by a script, not an Xcode project.**
SwiftPM builds the executables; a script lays out the bundle as
`Hazmat.app/Contents/{Info.plist, MacOS/HazmatApp, MacOS/HazmatDaemon,
Library/LaunchDaemons/<daemon label>.plist}` and ad-hoc signs it. Identifiers:
bundle `com.greyshepherd.hazmat`, daemon label and mach service
`com.greyshepherd.hazmat.daemon`.
_Alternatives_: an Xcode project (adds a project file and an Xcode dependency to
a repository whose tests run from the command line, and `shipping` will replace it
with real packaging); a project generator such as XcodeGen (a tool dependency for
the same output). Both rejected here as premature.

**2. A daemon registered through `SMAppService`, not a legacy helper.**
`SMAppService.daemon` gives a one-time per-daemon admin approval in System
Settings, keeps the property list inside the signed bundle, and needs no install
step into `/Library/PrivilegedHelperTools`.
_Alternatives_: `SMJobBless` (deprecated path, system-location install, its own
authorization dance); `AuthorizationExecuteWithPrivileges` (deprecated, and the
`cp`-style escalation this project exists to avoid). Consequence: the app must be
signed, and it must live in `/Applications` for the daemon to be bootstrapped at
boot rather than only while the app is present.

**3. The privileged interface is two methods: baseline plus bytes in, a result
out.** An `@objc` protocol served over `NSXPCConnection`, taking the digest of
the file the plan was based on and, for an install, the finished bytes, replying
with a status and a reason. No path parameter, no profile name, no fragment: the
daemon builds the target from a constant and writes exactly what it is handed.
Removal is a second method carrying the digest and no bytes: the file holds no
block afterwards, so the byte contract cannot admit it, and the block is stripped
on the privileged side where the bytes are read.
_Alternatives_: send the rendered block and let the daemon splice (moves
composition and position into the privileged process and grows its grammar
surface); accept a path (a root-write primitive with no justification); a
block-less write through the one method (weakens the input contract to "at most
one block").

**4. The daemon verifies the caller's signature.** The process behind the
connection is checked against a code requirement: identifier-only during
development, because ad-hoc signatures carry no team, and identifier plus team
anchor for a shipping build. `NSXPCConnection` publishes no audit token, so the
process is identified by what the connection reports.
_Trade-off_: recorded under Risks.

**5. The write is a temp file plus rename, with attributes set on the descriptor.**
Open a uniquely named file in `/etc` with `O_CREAT|O_EXCL|O_WRONLY`, write,
`fchmod(0644)`, `fchown(0, 0)`, `fsync`, close, `rename` over `/etc/hosts`, then
`fsync` the directory. Setting mode and owner on the descriptor is what defeats
the umask, which is how a hosts file ends up 0600. The temp file is unlinked on
every failure path.
No access-control list: the file is created fresh rather than copied, so none is
inherited unless `/etc` itself carries a default; the write verifies the result
carries no extended list and fails, leaving the original in place, if one appears.
_Alternatives_: write in place (a reader can observe a partial file, and a crash
can truncate the real one); `copyfile` or `cp` (carries the source's list - the
exact published failure of the incumbent); `exchangedata` (atomic, but leaves the
temp in place and complicates the failure paths).

**6. The request carries the state the plan was based on.** The client sends a
digest of the file it read; the daemon digests the current file and refuses on
mismatch. This turns the atomic write into a compare-and-swap, so a foreign edit
landing between read and write is reported instead of silently lost.
_Alternatives_: no guard (a lost update with no signal); file locking (no lock the
other writers respect, so it buys nothing).

**7. Bytes are validated before the file is touched.** Exactly one well-formed
block, a supported version, and a size bound of 1 MiB - the live file is a few
hundred bytes, and the bound exists so a client cannot make the daemon write an
arbitrarily large file into `/etc`. The same marker grammar is used on both sides.
_Alternative_: trust the client because it is our own app - rejected, since the
point of the boundary is that it does not have to.

**8. Drift is a block comparison, and the remedy is a re-render.** The client
reads the file, locates the block, and compares those bytes with what the store
renders now: equal is nothing to do, different is drift, absent is a first apply,
and a malformed or doubled marker set is refused. Foreign content elsewhere in
the file is not drift - it is other tools' entries, and it is preserved.
_Alternative_: treat any difference in the whole file as drift (the file is
shared, so this would report drift constantly and invite blind overwrites).

**9. Position is a per-apply choice implemented as a line-boundary insertion.**
Two positions: before the first entry line, and at the end of the file. The
client-side splice gains a position: `prefix + "\n" + block + suffix`, where the
prefix for the first is everything ahead of the first line that holds neither
whitespace nor a comment, and the whole file for the second. The choice governs
insertion; an existing block is replaced where it is, so a later apply cannot
move a block other tools have come to rely on. Because the separator rule is
unchanged, the existing strip rule (remove the block and one preceding newline)
still restores the original bytes exactly at either position, so the round-trip
property that `hosts-block` specifies survives. The default, and the measurement
that decides it, are decision 11.

**10. Pre-write verification is the strip identity.** Before the daemon is asked,
the client proves two things: the planned bytes hold exactly one well-formed block
of the supported version, and removing that block from the planned bytes equals
removing the block from the bytes that were read. The second check is what proves
nothing outside the block changes, and it is cheap because strip already exists.
_Alternative_: trust the splice because it is tested - a future position or format
change could break the property silently, and the check costs a scan of a few
hundred bytes.

**11. The measurement.** With the helper approved and the position parameterised,
compose a file in which one name resolves twice - one entry above where the block
would go, one inside it - for a name nothing else uses, apply it, resolve the name
through the system resolver, and record which address wins. First-wins means the
default position is above foreign entries; last-wins means the end of the file.
The original bytes are saved in memory before the measurement and restored and
re-read afterwards, and the resolver cache is flushed before each lookup. If the
resolver merges or round-robins the two entries, position stays a parameter and
the default is recorded as unmeasured rather than guessed.

_Measured, macOS 26.1, Apple silicon._ The store's `measure` profile resolves
`hazmat-measure.test` to `192.0.2.53`; one entry appended above the block's
position resolves it to `192.0.2.99`. Applied at the default position and
resolved with the cache cleared, the answer carried **both** addresses:
`dscacheutil` listed `192.0.2.99` then `192.0.2.53`, and `getaddrinfo` returned
both, in file order. The resolver merges the duplicate, so no address wins and no
position is made safer by measurement. The default is therefore unmeasured and
stays at the end of the file, which is where the splice put the block before the
choice existed. The block was removed afterwards and the file compared byte for
byte with the bytes saved before the measurement.

**12. Testability split.** `HazmatCore` gains the apply path - read a file, drift,
position, verification, outcome - parameterised by the file path and by a
privileged-writer abstraction, plus the byte validation both sides share. The
daemon's write routine takes its target as a parameter and is tested against a
temporary directory; only the XPC handler hard-wires `/etc/hosts`. No test
escalates or touches `/etc/hosts`; the single real write on this machine is a
task with an approval step, not a test.

## Risks / Trade-offs

- **Ad-hoc signing in development.** Registration refuses an unsigned or wrongly
  signed bundle, and a development requirement cannot anchor to a team, so the
  daemon trusts any client signed with the app's identifier. → Development-only
  arrangement, produced by the bundle script and recorded in the design;
  `shipping` anchors the requirement to team plus identifier. The exposure is
  limited to processes the machine's own user can sign.
- **Process identification without an audit token.** The daemon identifies the
  caller by the process the connection reports, because `NSXPCConnection`
  publishes no audit token. A process that exits and has its identifier reused
  during the check is the theoretical gap. → Bounded by the development
  requirement above, which is already trust-limited; a shipping requirement adds
  the team anchor, and the peer-requirement API can replace it when the
  deployment floor allows.
- **Approval is manual.** Registration cannot finish without an admin approving
  the daemon in System Settings, so end-to-end cannot be automated here, and a
  first run legitimately reports "awaiting approval". → The state is surfaced by
  the app and named in the outcome; the end-to-end task expects the approval step
  and is written as a supervised procedure.
- **The measurement can be inconclusive.** A resolver that merges or round-robins
  duplicates makes no position safe by measurement alone. → Realized: this
  machine's resolver returns both addresses, so the default is recorded as
  unmeasured in decision 11. Position stays a parameter, and de-duplication inside
  the block keeps Hazmat's own output unambiguous either way.
- **Replacing the file changes its inode.** Anything holding the old inode sees
  stale content, and hard links stop tracking. → Accepted: the alternative risks
  partial content, `/etc/hosts` is not normally hard-linked, and readers reopen it
  per lookup.
- **A crash between rename and directory flush** can lose the rename to power
  loss, even though atomicity holds. → Accepted; the flush is durability, not
  correctness.
- **A stale temp file** can survive a crash in `/etc`. → The name carries a random
  suffix and is unlinked on failure paths; a leftover file is inert.
- **The size bound and version check are the whole input contract.** A future
  block format must bump the version or writes are refused rather than misread. →
  Intended: refusal is the designed failure mode.
- **Drift has a blind spot.** A tool that rewrites the file while preserving our
  block byte for byte is invisible, because the block is the only region we own. →
  Accepted and consistent with the store being the source of truth.

## Rollback

- A block that should not have been applied is removed with the strip path, which
  restores the bytes that were outside it, so no backup file is required and the
  pre-write verification is what makes that safe.
- Unregistering the helper stops the write path entirely and leaves the live file
  as it is; the block can still be removed by hand.
- Because the store is the source of truth, recovery from a damaged block is a
  re-render rather than a reconstruction.

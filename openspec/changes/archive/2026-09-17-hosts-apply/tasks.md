# Tasks

## 1. Targets and the development bundle

- [x] 1.1 Add a daemon executable target and an app executable target to the package, both depending on the pure core, and verify `swift build` produces both binaries while `swift test` still passes unchanged
- [x] 1.2 Assemble the development bundle with a script: `Hazmat.app/Contents/{Info.plist, MacOS/HazmatApp, MacOS/HazmatDaemon, Library/LaunchDaemons/<daemon label>.plist}`, ad-hoc signed, and verify the script produces a bundle whose property list names `Label`, `BundleProgram` and the mach service, and whose two executables both pass `codesign --verify`
- [x] 1.3 Verify the daemon target imports no UI framework and no shell-out helper, by checking its import list

## 2. The client-side apply path

- [x] 2.1 Read the live file and classify its block state — absent, present, drifted, or refused for a malformed, doubled, or foreign-version marker set — and verify every state with a test over fixture bytes and an injected file path
- [x] 2.2 Report drift by comparing the located block with the block the store renders now, and refuse to overwrite it unless the caller asked, and verify the drift, deliberate-overwrite, and first-apply cases separately
- [x] 2.3 Add the position choice — before the first entry line, or at the end of the file — to the client-side splice as `prefix + separator + block + suffix`, and verify the strip round trip restores the original bytes exactly at both positions
- [x] 2.4 Verify the planned bytes before anything is written: exactly one well-formed block of the supported version, and strip(planned) equal to strip(live), and verify a failing check leaves the file untouched and names the reason
- [x] 2.5 Return an outcome that distinguishes nothing-to-do, applied, refused, and failed, naming the cause for the last two, and verify a no-op apply leaves the file's modification time unchanged
- [x] 2.6 Keep the path testable without privilege by injecting the file path and the privileged writer, and verify with a recording writer that no test triggers a real write

## 3. The privileged write

- [x] 3.1 Validate the bytes before touching the file — exactly one well-formed block, a supported version, and the 1 MiB bound — and verify each refusal case leaves the file unchanged
- [x] 3.2 Implement the atomic write: unique temp file in the target directory, mode set on the descriptor to 0644, owner set to system account, flush, rename, then flush the directory, and verify in a temporary directory that the result is a regular file with the documented mode and owner
- [x] 3.3 Verify a write leaves no access-control list, and that a file carrying one is refused rather than replaced
- [x] 3.4 Verify atomicity: an interrupted write leaves the previous contents in place, and a reader running during a write sees one complete version of the file
- [x] 3.5 Verify no temp file is left behind on any failure path
- [x] 3.6 Carry the baseline digest from the client and refuse the write when the file no longer matches it, and verify a concurrent edit is refused while the edit itself survives

## 4. The privileged boundary

- [x] 4.1 Define the XPC interface as baseline digest plus bytes in, status plus reason out, and verify the interface exposes no parameter that names a target path or a profile
- [x] 4.2 Wire the daemon handler to one fixed target path, and verify a request can only ever affect that path
- [x] 4.3 Verify the caller's code signature against a requirement — identifier only in development — and verify a client that does not satisfy it is refused with the file unchanged
- [x] 4.4 Verify no shell and no external program is executed anywhere on the write path

## 5. Registration and approval

- [x] 5.1 Register the daemon and expose its state as not-registered, awaiting-approval, or enabled, and verify the first two states against a bundle that has not been approved
- [x] 5.2 Surface registration errors with their cause — already registered, denied by the user, invalid signature — and verify each is reported rather than swallowed
- [x] 5.3 Support unregistering, and verify the state returns to not-registered and a write request then fails

## 6. The minimal app shell

- [x] 6.1 Build the shell: helper state, drift state for a selected profile, and the register, apply, and remove-block actions, and verify it launches from the development bundle
- [x] 6.2 Show the approval requirement while the helper is awaiting approval, and verify the wording follows the state the registration API reports
- [x] 6.3 Verify the shell carries no menu bar item, no profile editor, and no resolved view

## 7. The measurement

- [x] 7.1 Supervised: with the helper approved, save the live file's bytes, apply a composition in which one unused name resolves twice — once above the block's position and once inside it — then resolve that name through the system resolver with the cache flushed, and record which address wins
- [x] 7.2 Verify the file is byte-identical to the saved bytes after the measurement, and that the temporary name no longer resolves
- [x] 7.3 Record the measurement in design.md and set the default position from it, or record the default as unmeasured when the resolver merges or round-robins the two entries

## 8. Supervised end-to-end

- [x] 8.1 Supervised: apply a profile to the real hosts file, and verify every byte outside the block is identical to the pre-apply bytes, the mode, owner and absent access-control list match the spec, the block's entries resolve, and a second apply reports nothing to do
- [x] 8.2 Verify drift on the real file by editing inside the block, confirming the next apply reports drift and leaves the file alone, then confirming the deliberate overwrite repairs it
- [x] 8.3 Verify removing the block restores the file to its pre-apply bytes, and verify the file is byte-identical to the bytes captured before all supervised work
- [x] 8.4 Verify an unapproved helper cannot write: with the helper unregistered, confirm an apply is refused with that cause and the file is unchanged

## 9. Isolation guard

- [x] 9.1 Verify the automated suite neither reads nor writes the real hosts file, by comparing its bytes and modification time before and after a full `swift test` run
- [x] 9.2 Verify the suite runs to completion as a non-root user, with no approval prompt and no escalation

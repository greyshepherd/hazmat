# Tasks

## 1. The presence call

- [x] 1.1 Add `checkIn(withReply:)` to the privileged interface, carrying nothing and answering nothing but its arrival; verify the boundary test's method set and encodings cover three methods and still find no path or profile in any selector
- [x] 1.2 Answer the call in the daemon after the same caller verification as a write; verify with a test that the handler answers without touching the target file
- [x] 1.3 Add the client's check: classify an answer, a refusal and silence into a reachability value, and verify each classification with a test against a service the test holds

## 2. The state the app shows

- [x] 2.1 Add the not-answering helper state with its word, glyph, tone, summary, blocked cause and repair remedy; verify the mapping from approval and reachability, and that every state has its own words
- [x] 2.2 Block a pending write with that state and offer the repair; verify the blocked cause names the helper and the remedy is the repair
- [x] 2.3 Name the new state in the helper sheet, at the repair, and in the status item's menu with the repair action; verify each surface and that the three earlier states are unchanged

## 3. The write bound

- [x] 3.1 Bound the write and check waits and name the repair in the failure; verify the documented bound and the words
- [x] 3.2 Check presence after a write that did not succeed; verify the shell follows a refused or failed write with a check

## 4. The shell

- [x] 4.1 Keep the last answer, check before the first state is presented, re-check a stale answer and check after a register or a repair, one check at a time and off the main thread; verify the window stays responsive while nothing answers
- [x] 4.2 Add the install and the repair to the model's actions and wire them to the sheet, the menu and the status item; verify both run the same bounded sequence and report what the last check found
- [x] 4.3 Never present a state that no answer backs: derive the state from the registration refined by an answer, keep the last answer across a repair, and verify a repair never reads as ready while its check is still out
- [x] 4.4 Ask the registration again while the system refuses it because the removal has not finished, bounded, and only for refusals asking again can change; verify with a double that refuses once, and with one that refuses every time
- [x] 4.5 Run the sequence again when the check after a repair does not come back as an answer, bounded at two passes; verify a pass that answers stops the repair and a pass that does not is followed by one more
- [x] 4.6 Report a refusal that survives the retries with its cause and the two ways out, and run the whole sequence off the main thread behind a notice; verify the wording and that the live file is untouched
- [x] 4.7 Register before anything is removed, and remove only in the pass that follows a check which did not answer, since removing is what leaves the system's record for the helper disabled; verify a helper that answers is never removed, that the system already having it is not a failure, and that only the pass after a failed check removes

## 5. Verification

- [x] 5.1 Run the full test suite and verify it passes; one pre-existing failure remains, in the test that asserts the default store has not been created on this machine, which it has
- [x] 5.2 Build the development bundle, quit and relaunch the app, and verify a helper the system had stopped starting is installed again without a removal, that the state never reads ready before the helper answered, and that the daemon then serves and stays running

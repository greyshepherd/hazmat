# Tasks

## 1. The origin in the store

- [x] 1.1 Add the sidecar to `StoreLayout`: a `remote/` directory, `remoteURL(_:)` for a fragment name, and `remoteSources()` listing the sidecars that name a usable fragment, ignoring anything else the directory holds; verify new `StoreAuthoringTests` show an unreadable name filter, an unlistable file type, and a sidecar found by name, and that an empty store lists none.
- [x] 1.2 Add `RemoteSource` to `HazmatCore` (design D2): URL, interval in seconds, last attempt, last success, ETag, Last-Modified, last failure reason, and a format version, encoded and decoded with `Codable`; verify a round trip of every field — including a URL with a query and a failure with a reason — and that a truncated or version-unknown sidecar reads as a typed failure rather than a default value.
- [x] 1.3 Add the sidecar's authoring operations to `StoreWriter` (design D10): write a source, rename its file with the fragment, remove it with the fragment, and remove it when a delete names a source whose fragment is absent; verify `StoreAuthoringTests` cover a rename that moves both files, a delete that removes both, a delete of a sidecar-only name that reports a change, a delete of a name with neither that reports nothing to do, and a duplicate of a remote fragment that leaves the copy without an origin.
- [x] 1.4 Add the fetch bounds to `HazmatCore`: the applied block's size bound reused as the body bound, and the exchange time bound, each named in one place; verify a test asserts the body bound equals `PlannedBytes.sizeBound` and that the refusal text names the number.

## 2. What a fetch may store

- [x] 2.1 Add a `RemoteFetching` seam to `HazmatAppSupport` (design D3): a request carrying the URL and the validators, and an answer carrying a status, a body, the validators, and a reason; verify a stub fetcher in the test target satisfies it with no network call.
- [x] 2.2 Add the answer checks (design D5): refuse a non-HTTPS URL and a redirect that leaves HTTPS, a non-success status, a body over the bound, a body that is not valid UTF-8, and a body holding a `hazmat:` directive; verify `RemoteRefresherTests` exercise each refusal with its own reason and assert the fragment file was not created or changed.
- [x] 2.3 Add the write path: a fetch that returns text different from the fragment's is written through the store writer, an unchanged body and a not-modified answer write nothing, and a failed fetch or write records the attempt with its reason while the previous text stays readable; verify tests assert the file's bytes and modification time for each case, that no temporary file is left, and that the sidecar's last success and last failure are each recorded.
- [x] 2.4 Add the `URLSession` fetcher in `HazmatApp`: HTTPS-only, redirects bounded and refused when they leave HTTPS, the conditional headers, the time bound, and a body read that stops at the size bound; verify a scripted local exchange refuses a plain-HTTP URL and a redirect to one, and that the fetcher is reachable from no other target — `PackagePurityTests` still passes and the daemon target holds no URL reference.

## 3. When a refresh happens

- [x] 3.1 Add the due calculation to `HazmatAppSupport`: a source is due when its interval is non-zero and has elapsed since its last success or since it was created, never due when its interval is zero, and never due again inside the interval whatever the last attempt's outcome; verify table-driven tests over interval, last success, and last failure.
- [x] 3.2 Add the default and the floor (design D7): 24 hours by default, 15 minutes minimum, zero for manual only, with a configured value below the floor refused with a reason; verify tests cover the default, a value under the floor, and zero.
- [x] 3.3 Add the schedule to the shell: a due check at launch and on a repeating timer, one exchange at a time, off the main actor, with a due source that is already in flight skipped rather than queued twice; verify a test drives the due check with a stub fetcher through two intervals and counts one exchange per interval, and that the shell's window stays readable while an exchange is in flight.
- [x] 3.4 Add the on-demand refresh to the shell, reachable from the source's row and from the add-source sheet, running regardless of the interval; verify a test asks for a refresh on a source that is not due and counts the exchange.

## 4. A refresh is an edit

- [x] 4.1 Add the refresh's store-and-apply step to `EditorModel`, reusing the existing edit path: write the fragment, re-apply when the applied profile stacks it and the live block still matches the block that profile rendered before the refresh, report drift when it does not, and leave the live file alone when no applied profile stacks it; verify `EditorModelTests` cover each of those four outcomes with a stub fetcher and a double writer.
- [x] 4.2 Serialize refreshes with edits: a refresh takes the same one-writer gate an edit takes, and a refresh that cannot take it is left due rather than run concurrently; verify a test starts an edit and a refresh together and asserts one store write, one apply, and a refresh still due afterwards.
- [x] 4.3 Make a refresh's outcome reach the window the way an edit's does: the notice, the write state, the resolved view, and the row's refresh state all reflect the refresh; verify a shell test asserts the notice reports a failed refresh with its reason and a successful one as a change.

## 5. The window

- [x] 5.1 Carry each fragment's origin and refresh state through `EditorModel.read` into `EditorPresentation`, including sources whose fragment is not there yet (design D8), so a row exists for a source whose first fetch failed; verify tests assert a sidecar-only source appears in the reading with its reason and without a fragment.
- [x] 5.2 Add the sidebar rows: the union of fragments and sources, a remote mark naming the URL, the last successful refresh, the out-of-date state, and the last failure's reason; verify `EditorPresentationTests`/`MenuPresentationTests` cover a marked row, an out-of-date row, and a row reporting a failure.
- [x] 5.3 Add the add-source and edit-source sheets: name, URL, and interval, with a refused URL or interval reported in the sheet rather than after it closes; verify tests cover a valid source, a non-HTTPS URL, and an interval below the floor.
- [x] 5.4 Present a remote fragment's text read-only with its URL and the refresh action beside it (design D9); verify a test asserts the editor offers no save for a remote fragment and still offers one for an ordinary fragment.

## 6. The whole path

- [x] 6.1 Add an end-to-end test with a stub fetcher: create a source, fetch a body, stack the fragment in a profile that is applied, refresh with changed text, and assert the store holds the new text and the live file holds the newly rendered block; verify the test passes with no network and with the live file a temporary file.
- [x] 6.2 Add the failure path end to end: a refresh whose exchange fails, one whose body is refused, and one whose apply is refused each leave the store's and the live file's bytes as the specs say, and the window reports the reason; verify the test asserts both files' bytes and modification times.
- [x] 6.3 Add a store fixture with a source to `Tests/HazmatCoreTests/Fixtures` and a sidecar the fixtures record, including one whose fragment is missing; verify the existing composition and store tests still pass unchanged with the fixture present.
- [x] 6.4 Update `README.md`'s feature list with a fetched-from-a-URL fragment and how it is refreshed; verify the statement matches the spec's behavior and names the default interval.

## 7. Verify the whole

- [x] 7.1 Run `swift test` and confirm the suite passes with no network access and as an ordinary user, that `HazmatCoreTests` still asserts Foundation-only imports, and that no privileged target gains a URL or a fetch.
- [x] 7.2 Run `openspec validate remote-fragments --strict` and confirm the change's artifacts are complete, then re-read the delta specs against the implementation for any requirement with no covering test.

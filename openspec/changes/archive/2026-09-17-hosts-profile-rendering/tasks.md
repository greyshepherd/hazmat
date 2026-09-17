# Tasks

## 1. Package scaffold

- [x] 1.1 Create a Swift package with one library target for the pure core and one test target, and verify `swift build` and `swift test` both succeed from a clean checkout
- [x] 1.2 Verify the library target imports no UI, AppKit, or privileged framework, by checking its import list, and verify the test suite runs to completion as a non-root user

## 2. Fragment parsing

- [x] 2.1 Parse hosts-grammar entries as address, hostname, and optional aliases, and verify tests cover comment lines, blank lines, tab and space mixing, and multi-alias lines
- [x] 2.2 Recognise removal directives and treat them as removals rather than entries, and verify a fragment containing removals yields removal records and no entries for those lines
- [x] 2.3 Report every malformed line with its fragment identity and line number in one result, contributing no entries for malformed lines, and verify a test asserts that several bad lines in one fragment are all reported

## 3. Profile loading

- [x] 3.1 Load a profile as an ordered list of fragment references with comments permitted and order preserved, and verify a three-reference profile composes in file order
- [x] 3.2 Report a referenced fragment that does not exist as an error naming that fragment, and verify the test asserts the fragment name appears in the error

## 4. Composition and resolution

- [x] 4.1 Resolve entries keyed on name and address family with a later layer winning, and verify tests covering an override in both stack orders
- [x] 4.2 Union address families for the same name instead of treating them as conflicting, and verify a test asserts both the IPv4 and IPv6 addresses are retained
- [x] 4.3 Apply removals so a name supplied by a lower layer is absent from the resolved set, and verify removing a name no lower layer supplies succeeds without changing the set
- [x] 4.4 Key resolution on every name of an entry including aliases, and verify a test where an alias in one layer conflicts with a primary hostname in another layer
- [x] 4.5 Order resolved entries by winning layer and then by line order within that fragment, and verify a test asserts identical ordering across repeated composition

## 5. Resolution report

- [x] 5.1 Record the supplying fragment for every resolved entry, and verify a test asserts the source fragment of a known entry
- [x] 5.2 Record each displaced entry with its address, its source fragment, and the fragment that displaced it, and verify a test asserts the full report for an override
- [x] 5.3 Expose the report from a single composition call without recomputation, and verify a test reads the report after composing once

## 6. Block rendering

- [x] 6.1 Emit the versioned start and end markers, and verify rendered output contains both and that block boundaries can be located without line numbers
- [x] 6.2 Emit each name once per address family in resolved order using one documented line ending and a terminating newline, and verify a byte-level assertion against a fixture
- [x] 6.3 Produce byte-identical output for identical inputs, and verify a test compares bytes across repeated renders and shuffled fragment enumeration order

## 7. Splice and strip

- [x] 7.1 Splice a rendered block into surrounding content preserving every byte outside the markers and their relative order, and verify against a fixture resembling the shipped file including its "Do not change this entry" header
- [x] 7.2 Strip a block and restore the pre-splice bytes exactly, and verify a round-trip property test asserting strip-after-splice equals the original across fixtures with and without a trailing newline
- [x] 7.3 Make splicing idempotent, and verify a test asserting that splicing an already-present block leaves the bytes unchanged
- [x] 7.4 Refuse multiple, unterminated, or malformed marker sets and leave the input unchanged, and verify a test for each rejection case

## 8. Edge cases

- [x] 8.1 Render markers with no entries when the resolved set is empty, and verify a test asserts the empty block is present, contains no entries, and is removable by the same path
- [x] 8.2 Verify preservation across CRLF line endings, a file with no trailing newline, an empty file, and a marker-only file, and verify each case passes as a fixture test

## 9. Integration

- [x] 9.1 Verify the end-to-end path from three fragments and a profile to a spliced hosts file, and verify the result matches an expected-bytes fixture
- [x] 9.2 Verify the suite neither reads nor modifies `/etc/hosts`, by comparing the file's bytes and modification time before and after a full `swift test` run

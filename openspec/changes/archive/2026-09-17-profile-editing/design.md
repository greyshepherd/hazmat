# Design

## Context

The core composes, renders, splices, and derives the live file's state; the
daemon owns every write to `/etc/hosts`; the window lists profiles and applies
them; the menu bar switches them. The store is read through a protocol with a
directory-backed implementation, and nothing writes it.

Three existing constraints shape the approach:

- `HazmatCore` imports nothing outside Foundation, enforced by a test, so store
  authoring is plain text handling and no UI code leaks inward.
- The privileged side takes finished bytes only, and its interface is held at two
  methods by a test, so editing must reach the live file through the existing
  apply path or not at all.
- Store files are plain text that any editor or version control system can write,
  so the application must not treat them as its private state.

The menu bar's presentation logic already lives in app support as a pure value
with its own tests; the editor follows that pattern.

## Goals / Non-Goals

**Goals:**

- One authoring model over the store, testable without a UI and without touching
  the live file.
- An editor that reads the store when asked, so the window, the menu bar, and an
  external text editor cannot disagree about what the store holds.
- Keep "drift is never overwritten silently" exact: an edit reaches the live file
  only over bytes Hazmat itself wrote.
- Keep the window thin: decisions in app support, as the menu bar's already are.

**Non-Goals:**

- Packaging, signing, notarization, and the update channel.
- File watching, polling, and change notifications.
- Versioning, undo, and edit history.
- Importing another hosts manager's store, or turning the live file into
  fragments.
- A command-line surface.

## Decisions

**1. An overwrite names the block it replaces.**

The apply path currently takes `overwriteDrift: Bool`; `true` replaces whatever
block is present, and the caller's belief about that block is not expressed
anywhere. The editor needs exactly that belief: "the live block is still what
this profile rendered before my edit". Checking it in the caller and then calling
with `true` leaves the check unenforced at the write.

The parameter becomes one value carrying both the intent and the expectation:

```swift
public enum Replacement: Equatable, Sendable {
    /// Write only where the file holds no block.
    case onlyIfAbsent
    /// Replace this block, which the caller read and intends to replace.
    case block(Data)
}
```

An apply replaces the live block only when it is byte-identical to the named
block, and refuses when the file holds none or holds a different one. Every
caller already has the bytes: a switch names the rendering of the profile the
derivation matched, a deliberate overwrite names the drifted block it showed, an
edit names the profile's pre-edit rendering, and a first apply names nothing.

Alternatives considered: keeping the boolean and adding an optional expectation
beside it (two ways to express one thing, and the weak one survives); checking in
the caller (unenforced at the write); a separate write path for the editor (a
second writer with fewer checks).

This makes `ActiveProfileState.drifted` carry the live block, so the deliberate
overwrite names the bytes the derivation found rather than re-reading and
re-locating them elsewhere.

**2. Store authoring is a Foundation-only text layer beside the reader.**

Reads already go through the directory store in the core. Writes belong next to
it: create, rename, duplicate, delete, and replace the text of a profile or
fragment, with name validation before any file is touched.

The privileged writer is not reused. It sets system ownership, fixes the mode, and
refuses a file carrying an access-control list, which is right for `/etc/hosts`
and wrong for a file in the user's own store. The store writer is deliberately
smaller: write a temporary file in the target directory, then rename over the
target.

**3. Editing never involves the helper, and never the live file.**

The store lives in the user's application support directory, so every authoring
operation is unprivileged. A save that changes the applied profile reaches the
live file only by calling the existing apply path afterwards, and the outcome of
the two steps is reported separately: the store write is already durable when the
apply runs.

**4. A save re-applies only over Hazmat's own bytes.**

The editor holds the rendering it last showed for the profile being saved. After
the store write it applies with that rendering as the named block. If the live
block has changed since — by another tool or by a different profile being applied
— the apply refuses, the live file is left alone, and the window reports drift
with the overwrite offered as its own action. An edit made outside the
application has no in-session rendering to name, so it takes the ordinary drift
path.

**5. The editor reads the store on demand.**

Listing, resolving, and the drift check all read the store and the live file when
they are asked. There is no cached model and no file watcher. A watcher would
have to reconcile the store's plain-text files with the application's view of
them, which is the second source of truth the menu bar already avoids.

**6. The editor's decisions live in app support.**

A pure value describes the store's contents as the window shows them: the profile
and fragment lists, the selected profile's resolved entries with their sources,
its displaced entries, its problems with fragment and line, and the actions
available for the current state. The window scene renders that value and forwards
actions, so the decision logic is tested without SwiftUI, exactly as
`MenuPresentation` is.

## Risks / Trade-offs

- **A save silently changing the live file** → the re-apply happens only when the
  live block is byte-identical to what Hazmat wrote for that profile, and its
  outcome is reported in the same place every other apply outcome is.
- **A store write succeeding while the apply is refused** → reported as two
  results: the store holds the edit, the live file does not, and the reason is
  shown. The store is the source of truth, so this is a recoverable state rather
  than a lost edit.
- **Deleting the applied profile leaves drift behind** → the derivation already
  reports a block no profile owns as drift, and the window offers the overwrite
  as its own action.
- **Renaming onto a name that exists silently destroying it** → the target is
  checked first and the rename is refused; the target's text is untouched.
- **A large fragment making the window sluggish** → the store holds host entries;
  no requirement here covers files of other sizes.
- **The shell's isolation test forbids the editor** → the guard that asserts the
  editor and resolved view are absent is replaced in the same change by a guard
  for the editor's thinness and by a guard for what is still absent, packaging.

## Migration Plan

Not applicable: no deployed users, and the store's location and layout do not
change. A store written by hand before this change is a store the editor opens.
Rollback is deleting the change, after which the store it wrote stays readable by
hand.

# Design

## Context

The window is one scrolling column that renders `EditorPresentation` values; the
shell model forwards choices to the editor model in app support, which reads the
store and the live file on every read. Scene isolation is enforced by tests: the
editor scene must not name store, composition or path types, and the app entry
point holds nothing but scenes. Anything the new window needs must therefore
arrive as a presentation value.

Constraints that shape the approach:

- macOS 15 deployment target, SwiftPM executables, no asset catalog today, no app
  icon; a development bundle script assembles and ad-hoc signs the bundle that
  `SMAppService` needs.
- The store is plain text and the profile file is the layer stack: one reference
  per line, applied in order, later layers winning conflicts. A profile's comments
  and blank lines are tolerated when read but are not preserved when the window
  rewrites the file.
- Applied versus drift is byte equality between the live block and the rendering,
  so "what would be written" needs no new stored state.
- The privileged boundary takes finished bytes and carries no path; the XPC
  interface is two methods and a test asserts that count.
- The design reference (measured review, clickable prototype, brand tokens) lives
  outside this repository; only its decisions and token values carry over.

## Goals / Non-Goals

**Goals:**

- Keep the view a renderer: every phase, count, state and path the panes show is a
  value computed in app support and testable without a window.
- Derive the window's phase from values that already exist: store existence, the
  profile and fragment lists, the layer list, the resolved entries, the live block
  state, and the helper state.
- Keep the write path's behaviour identical. The confirmation and the revert are
  app-side wrappers around the existing replacement contract, which already
  refuses a write when the file moved on.
- Land the window in steps that keep the app buildable and the specs' scenarios
  testable.

**Non-Goals:**

- Packaging, signing, notarization and the update channel.
- Any layer state beyond the profile file's lines: no switched-off layer.
- Preserving hand-written comments when the window rewrites a profile. It is a
  pre-existing property of the store writer, and worth its own change.
- Redesigning the status item's title or the menu bar menu; the existing switcher
  spec stands.
- Drawing new icon artwork; the mark, wordmark and icon set already exist as
  files.

## Decisions

### Three panes, and the model's relation is the layout

Sidebar (profiles, fragments, helper footer), content (the selected fragment's
text, or the selected profile's layers), detail (the resolved block as text or as
a table). The alternative — one column with a segmented switch between "edit" and
"preview" — was rejected because the relation the model expresses is exactly
sidebar → content → detail, and the review's flattened-relationship and
no-selection findings come from not expressing it.

### The phase is one value computed in app support

A window phase (no store, store without profiles, profile without layers, changes
pending, in sync, write blocked) plus a write state is computed from the
presentation and the helper state, and the view switches on it. Computing this in
the view was rejected: the isolation tests exist to keep decisions out of the
scene, and a phase value is testable where a view body is not.

### Pending names the entries it would write, not a line diff

Byte comparison already answers "is it applied"; the count of what would be
written comes from the composition. A line-level diff against the live block was
rejected because a block written by another tool says nothing about which lines
changed, so the number would be a guess — and a diff engine would have to exist in
app support to produce it.

### The confirmation and the revert are app-side

The view presents a confirmation from a value (the hosts file path and the entry
count). The shell model keeps the block an apply replaced for the session, and a
revert writes it back as a replacement of the block that apply wrote, so the
existing byte-identity check refuses a revert after any outside edit. Persisting
the previous block inside the store was rejected: the store is deliberately plain
text that a person edits, and an undo does not belong in it. A revert is offered
only where an apply happened, and it inherits the helper's refusal reasons
unchanged.

### Store location resolves as environment, then choice, then default

An environment override outranks a saved choice so a development or test store
cannot be hijacked by a preference; the choice outranks Application Support. The
chosen path is a preference, not store content. Changing it re-points the shell
model's store root — catalogue, editor model, applier and the live-file reading
move together — and the window then shows the new location's contents rather than
merging them. A chosen location that is not there reports as no store and offers
creation instead of falling back, so a write never lands somewhere the user is not
looking at. Putting the last-used location inside the store was rejected as
circular, and a settings file in the store was rejected because a preference is
not something a user should have to version.

### New values go into the presentation, and search is one of them

The editor presentation gains the hosts file path, entry and layer counts,
per-layer counts, the profiles that use the selected fragment, the write state,
modal actions (new, rename, duplicate, delete, save, apply, revert, install
helper) and the search results for the search text the shell model holds. The
alternative — handing the view core types such as the store layout or the
composition — is what the isolation tests forbid, and keeping search out of the
view is what makes "the selection survives while it matches" testable.

### Brand colour as code-defined tokens

The brand sheet's tokens are plain hex values with derived steps. A palette in the
app target expresses them directly, including the contrast rules: white on the
accent measures 4.1:1, so the filled control uses the accent's darker step at
5.8:1; the muted tier is reserved for 18 point and above, or for non-text detail;
the amber status colour is darkened to reach 3:1 on the sidebar. A named-colour
asset catalog was rejected for now because SwiftPM puts resources in a separate
bundle that the development bundle script would have to copy, while a code palette
puts the rules where a test can read them. The app icon and the menu-bar mark are
files the bundle script copies into the bundle's resources.

### Commands live in a commands value driven by the one shell model

The entry point keeps holding nothing but scenes, and a test asserts that one
model instance is shared by both scenes. Menu items call the model's existing
methods and carry the shortcuts, so every action stays discoverable even when the
window hides a control it cannot act on. Attaching shortcuts only to view
controls was rejected: it leaves the actions unreachable from the menu bar, which
the specs require.

### Onboarding is a phase of the same window

No store is a phase, not a separate welcome window: the spec's phase model says
the window explains the phase it is in, and a second window would need its own
state machine and its own relationship to the helper.

### No switched-off layer

A layer is a line in the profile file. A switch has nowhere to persist, and the
two ways to give it one are both worse: commenting the line makes a hand-written
note indistinguishable from a switched-off layer, and an explicit marker adds
profile grammar, a layer type and re-apply handling for a control the layer list
does not need. The layer list keeps reordering, entry counts and removal, and a
note in the caption states that a later layer wins.

## Risks / Trade-offs

- [The prototype's resolved block is illustrative text, not what the renderer writes] → the detail pane renders the real block bytes; marker lines and section comments from the prototype are not adopted.
- [1080×700 with three panes is tighter than the current 760×915 column] → a documented default, a content minimum, and panes that degrade: the table view carries the wide case, the text view scrolls.
- [Hiding controls that cannot act can hide discoverability] → every action keeps a menu item, so nothing becomes unreachable.
- [A revert lives only for the session] → the byte-identity check makes a wrong revert impossible; persisting the previous block is a follow-up if users want undo across launches.
- [A resolved store location may hold something that is not a store] → the store reads as missing and creation is offered; writes stay inside `fragments/` and `profiles/` under that root.
- [Rewriting a profile from the window drops hand-written comments in it] → pre-existing, out of scope, and the strongest candidate for the next change because the store is advertised as hand-editable.
- [Isolation tests fail while the window is rewritten] → updated in the same change: the shell's helper-status assertion becomes a presentation assertion, the scene rules stay, and new view files are held to them.
- [The review was measured from a first-run screenshot] → its first-run findings are treated as phase requirements rather than as permanent defects; the phase model is what makes the first run correct.

## Migration Plan

- No store migration: layout, file names and formats are unchanged, and the chosen
  location starts unset so existing stores keep being read from Application
  Support.
- Rollback is a revert of the window and app-support additions; the store and the
  live file are untouched by them, and no state is written outside the store's own
  files.
- Order: panes and phase model first, then write state with the confirmation and
  revert, then commands, search, settings and the bundle assets. Each step leaves
  the app buildable and its scenarios testable.

## Open Questions

- Whether the pending bar should name written entries (as specified) or changed
  lines; entries are specified, and switching later is a wording change plus one
  scenario.

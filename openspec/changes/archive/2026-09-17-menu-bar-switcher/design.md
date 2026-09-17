# Design

## Context

- The shell already reads the store (`ProfileCatalogue`), classifies the live file
  (`BlockState`), and applies through the approved helper (`HostsFileApplier` with a
  `DaemonClient`). The menu bar needs the same three things, not new ones.
- Nothing records which profile was applied. The only link between the store and
  the live file is the block bytes, and `BlockState.classify` already answers the
  question for one rendering.
- The store has no enumeration of its own: profiles are files under
  `<root>/profiles/*.profile`, and the shell globs the directory.
- Deployment floor is macOS 15, so `MenuBarExtra` is available. The app is a
  SwiftUI `App` with a window scene and no AppKit plumbing.
- The window is the only place these commands live today, and it must keep
  working. The privileged interface already refuses drift and reports reasons.

## Goals / Non-Goals

**Goals:**

- One derivation rule for "what does the live file represent", expressed as a
  function of bytes so it can be tested without a UI, a helper, or root.
- A menu bar that answers that question at open time, from the store and the file
  as they are, without a second copy of the state the window shows.
- Activation, overwrite, and removal reuse the existing apply path unchanged.
- No new privileged surface.

**Non-Goals:**

- App lifetime changes: the app keeps its window and does not become an
  accessory-only process.
- Profile editing, the resolved view, packaging, store-format changes.
- Any new XPC method or any change to the daemon's input contract.
- File watching, background polling, or notifications when the file changes.

## Decisions

**1. The active profile is a pure derivation in the core.** `Activation.match`
takes the live bytes and a list of `(profile, rendered bytes)` and returns one of:
off (no block), unreadable (a reason), drifted, or the profiles whose bytes match.
_Alternatives_: record the applied profile in the store or in preferences (lies
after any external edit, which is the failure this project exists to avoid); ask
the daemon (moves an unprivileged read into the privileged process and adds a
method for no benefit).

**2. Reading is done once, rendering per profile.** The app-support layer reads
the live file once, renders each profile in the store, and hands both to the
derivation, so a store with many profiles still reads the file once.
_Alternative_: derive per profile by calling the existing single-render
classification (re-reads the file per profile and can observe two different
files in one answer).

**3. A profile that fails to render is reported, not treated as unmatched.** A
profile whose fragments are missing or malformed cannot match the live block,
and that has to be visible: the derivation carries a per-profile problem next to
the matches, and the menu shows it as a line rather than dropping the profile
silently.
_Alternative_: skip the profile (indistinguishable from "not active", so a
broken profile looks like a profile that simply is not selected).

**4. One model instance for both scenes.** `ShellModel` stays the single owner of
helper state, the catalogue, and the applier, and the app hands the same instance
to the window and the menu bar. The window's observable surface does not change.
_Alternatives_: a second model for the menu bar (two readers of the same file,
two drift answers); a singleton (untestable, and the current model is already
constructed with injected paths).

**5. The menu reads at open time.** The menu's content is built from a refresh
performed when it is opened and after every action, so a profile created since
the last look appears without a watcher, a timer, or a cache. SwiftUI does not
rebuild a `MenuBarExtra` menu on its own when it is opened, so the read is driven
by menu tracking: the menu view refreshes when the status item's menu begins
tracking, which is the moment it opens.
_Alternative_: cache profiles and drift in the model (needs invalidation, and the
only moment the values matter is the moment the menu is open).

**6. Drift is answered with labelled items, not a dialog.** A profile item
switches to that profile. Switching over a block another profile owns asks the
apply path for the replace; a block no profile owns is drift, so a profile item is
refused there and the menu offers the replace as its own item naming the profile it
would write. Choosing that item is the deliberate act; nothing overwrites a
drifted block implicitly.
_Alternatives_: a confirmation sheet (a menu extra has no window of its own, and
the menu closes on click); a separate "overwrite" mode toggled in the menu (two
steps for one intention, and easy to leave armed).

**7. Off removes the block; an empty profile still writes one.** Off is
`removeBlock`, so an "empty" profile - one that resolves to no entries - is a
different state with a visible block.
_Alternative_: treat a block with no entries as off (two different files become
indistinguishable, and the project's staging-by-profile idea depends on the
distinction).

**8. The helper section mirrors existing state, it does not invent it.** The menu
shows `HelperState` as it already exists, offers registration when the helper is
not registered, and reports an awaiting-approval state by pointing at System
Settings, where the approval actually happens.
_Alternative_: poll `SMAppService` on a timer (no new information, an extra
running loop).

**9. Menu logic is data, the scene is presentation.** The mapping from a
derivation plus helper state to menu items is a pure value in app support, and the
scene renders it. This keeps the choice of items, labels, and disabled states
testable without a UI, and keeps `HazmatApp` thin - the same split the existing
isolation tests assume.
_Alternative_: decide item labels inside the SwiftUI view (untestable without a
host, and the isolation tests would have to be relaxed).

**10. No new privileged surface.** The menu calls the same `HostsFileApplier` the
window calls, with the same `DaemonClient`, so verification, the compare-and-swap
baseline, drift refusal, and the refusal reasons are inherited rather than
re-implemented.

## Risks / Trade-offs

- **The status item can be hidden by menu bar overflow** → the window keeps every
  command, and the switcher stays an accelerator rather than the only route.
- **Deriving at each open re-renders every profile** → the files are small, the
  reads are unprivileged, and a human opens the menu; no caching means no
  staleness, which matters more here.
- **Byte equality is the only signal** → editing a fragment after applying shows
  drift even though nothing else changed. Consistent with the store being the
  source of truth, and the deliberate overwrite repairs it.
- **A drifted block hides which profile it came from** → the menu reports drift
  without naming a profile rather than guessing, and the profile names in the
  overwrite items say what would replace it.
- **Menu content refresh depends on menu tracking** → the read is driven by the
  status item's menu beginning to track, so a menu extra that stopped reporting
  tracking would show the last look; the end-to-end check verifies a store edit
  made between two opens.

## Migration Plan

- No migration: the change adds a scene and a derivation. The store, the block
  format, and the daemon interface are untouched, so an older build still reads
  the same files.
- Rollback is removing the scene; the live file and the store are unaffected by
  the presence or absence of the menu bar item.

# Proposal

## Why

Hazmat can only manage hosts entries that are pasted into its own store, so a
periodically published hosts file — a tracker blocklist such as
someonewhocares.org — has to be fetched by hand in a browser, pasted into a
fragment, and re-pasted whenever it changes. Issue #2 asks for such files to be
added from a URL and refreshed.

## What Changes

- A fragment can carry an origin: the URL it is fetched from, how often to
  refresh it, and the state of the last refresh. The fetched text is an ordinary
  fragment, so listing, composition, apply, and drift reporting need no change.
- The origin lives beside the fragment in the store as one sidecar per source,
  so the store stays plain text and a store that is copied or version controlled
  keeps its sources.
- A source is refreshed when it is due at launch, on its interval while the
  application runs, and on demand from its row.
- A fetch is conditional (ETag / Last-Modified), HTTPS only, redirects stay
  HTTPS, and it is bounded in time and size. A body that is not UTF-8, that is
  larger than the block bound, or that carries a `hazmat:` directive is refused
  before anything is stored. A refresh that fails keeps the previous text and
  reports the reason.
- A refresh that changes the text counts as an edit: when the profile stacking
  the fragment is the live one and the live block still matches what that profile
  rendered, the new block is applied; otherwise drift is reported and the live
  file is left alone.
- The window offers adding a source (name, URL, interval), marks remote fragments
  with their URL and last refresh, offers Refresh Now, and presents a remote
  fragment's text read-only.

## Capabilities

### New Capabilities

- `remote-fragments`: a fragment fetched from a URL — what an origin records,
  when and how it is refreshed, what a fetch refuses, and what a refresh does
  when it changes an applied block.

### Modified Capabilities

- `profile-store`: the layout gains one sidecar per remote source, and renaming
  or deleting a remote fragment carries the sidecar with it.
- `profile-editor`: the window manages remote sources and presents a remote
  fragment's text read-only rather than editable.

## Impact

- `HazmatCore`: the store layout, authoring (rename and delete carry the
  sidecar), a remote-source model with its sidecar format, and the fetch bounds.
  Foundation only, so the core stays pure.
- `HazmatAppSupport`: deciding what is due, refusing what a fetch returns,
  writing through the store writer, and re-applying through the editor model.
  The fetch itself sits behind a seam, so the suite never reaches the network.
- `HazmatApp`: the network fetch, the refresh schedule (launch plus a repeating
  due check), the add-source sheet, the sidebar's remote mark, and the read-only
  text view.
- No new dependencies. No change to composition, the block grammar, the profile
  format, the XPC protocol, or the helper.

import Foundation
import HazmatCore

/// What an editor operation did: the store's answer, and the apply's answer when
/// an edit of the profile whose block is live reached the live file.
public struct EditorOutcome: Equatable, Sendable {
    /// What the store did, or why it refused. `nil` when no store change was
    /// asked for.
    public let store: Result<StoreWrite, StoreWriteError>?
    /// What the apply did, when the edit was re-applied.
    public let apply: ApplyOutcome?
    /// A refusal taken before the store was touched.
    public let problem: String?
    /// What a refresh did, when this outcome is a refresh's. A refresh is an
    /// edit, so its store answer and its apply are above; this is the part only
    /// a refresh has: the exchange, its outcome, and the source's new state.
    public let refresh: RemoteRefresh?

    public init(
        store: Result<StoreWrite, StoreWriteError>? = nil,
        apply: ApplyOutcome? = nil,
        problem: String? = nil,
        refresh: RemoteRefresh? = nil
    ) {
        self.store = store
        self.apply = apply
        self.problem = problem
        self.refresh = refresh
    }

    /// Whether the store is different afterwards.
    public var didChangeTheStore: Bool {
        guard case .success(let write)? = store else { return false }
        return write.didChange
    }

    /// Whether something went wrong: the store refused, the applier refused or
    /// failed, or a check refused before either was touched.
    public var needsAttention: Bool {
        if case .failure = store { return true }
        if let apply {
            switch apply {
            case .refused, .failed: return true
            case .nothingToDo, .applied: break
            }
        }
        return problem != nil || refresh?.wasRefused == true
    }

    public var description: String {
        var parts: [String] = []
        if let refresh {
            parts.append(refresh.description)
        }
        switch store {
        case .success(let write):
            parts.append(Self.describe(write))
        case .failure(let error):
            parts.append("refused: \(error)")
        case nil:
            break
        }
        if let apply {
            parts.append(apply.description)
        }
        if let problem {
            parts.append(problem)
        }
        return parts.joined(separator: " ")
    }

    private static func describe(_ write: StoreWrite) -> String {
        switch write {
        case .wrote: return "the store holds the edit"
        case .unchanged: return "the store already held that text"
        case .deleted: return "the name was deleted"
        case .nothingToDo: return "nothing to do"
        }
    }
}

/// Reads the store and the live file when it is asked, edits the store, and
/// re-applies an edit of the profile whose block is live. Every decision it
/// makes is a value in the presentation, so the window can render and forward
/// without holding a model of its own.
public struct EditorModel: Sendable {
    public let layout: StoreLayout
    public let fileURL: URL
    public let writer: PrivilegedWriter
    /// What a read may reuse across reads. `nil` reads everything from scratch,
    /// which is what a test that wants no reuse passes.
    public let cache: StoreCache?
    /// The moment a read is answered from, so "out of date" is decided once, in
    /// one place, rather than wherever a row is rendered.
    public let now: @Sendable () -> Date

    public init(
        storeRoot: URL,
        fileURL: URL,
        writer: PrivilegedWriter,
        cache: StoreCache? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        layout = StoreLayout(root: storeRoot)
        self.fileURL = fileURL
        self.writer = writer
        self.cache = cache
        self.now = now
    }

    private var store: DirectoryStore { DirectoryStore(root: layout.root) }
    private var composer: HostsComposer { HostsComposer(store: store) }
    private var storeWriter: StoreWriter { StoreWriter(layout: layout) }
    private var applier: HostsFileApplier { HostsFileApplier(fileURL: fileURL, writer: writer) }

    // MARK: - Reading

    /// Reads the store's profiles and fragments, the selected items' detail, and
    /// what the live file holds. Every answer comes from one reading of the
    /// store, so a fragment is parsed once and a profile is composed and
    /// rendered once, however many rows and views ask a question of it.
    public func read(
        selection: SidebarSelection? = nil,
        search: StoreSearch = .none
    ) -> EditorPresentation {
        let reading = StoreReading(layout: layout, cache: cache)
        let profiles = reading.profiles
        let sources = RemoteSourceCatalogue(layout: layout).readings()
        // The fragments section is the union of the store's fragments and its
        // sources, so a source whose first fetch failed — a sidecar and no
        // fragment — still has a row.
        let fragments = Array(Set(reading.fragments).union(sources.map(\.fragment))).sorted()
        let at = now()
        let matchingProfiles = search.profiles(profiles)
        let matchingFragments = search.fragments(fragments)

        let resolvedSelection = Self.resolve(selection, profiles: matchingProfiles, fragments: matchingFragments, searching: search.isActive)
        let selectedProfile = resolvedSelection.selectedProfile ?? (selection == nil ? matchingProfiles.first : nil)
        let selectedFragment = resolvedSelection.selectedFragment ?? (selection == nil ? matchingFragments.first : nil)

        let selectedFragmentText = selectedFragment.flatMap { reading.fragment($0)?.text } ?? ""

        var layers: [FragmentID] = []
        var layerRows: [LayerRow] = []
        if let selectedProfile, let profile = reading.profile(selectedProfile) {
            layers = profile.outcome.profile.references.map(\.fragment)
            layerRows = layers.enumerated().map { index, fragment in
                LayerRow(fragment: fragment, position: index + 1, entryCount: Self.entryCount(of: fragment, in: reading))
            }
        }

        var storeProblem: String?
        let resolved: ResolvedView
        if let selectedProfile {
            do {
                resolved = .composed(
                    try reading.composition(of: selectedProfile),
                    rendering: try reading.rendering(of: selectedProfile)
                )
            } catch let error as CompositionError {
                resolved = .unresolvable(error.problems)
            } catch {
                storeProblem = "\(error)"
                resolved = .unresolvable([])
            }
        } else {
            resolved = .unresolvable([])
        }

        let live = liveReading(reading: reading, rendering: resolved.renderedBlock, profiles: profiles)

        return EditorPresentation(
            storePath: layout.root.path,
            hostsFilePath: fileURL.path,
            storeExists: layout.exists,
            profiles: profiles,
            fragments: fragments,
            profileRows: matchingProfiles.map { profile in
                ProfileRow(
                    profile: profile,
                    layerCount: Self.layerCount(of: profile, in: reading),
                    isApplied: live.appliedProfiles.contains(profile)
                )
            },
            fragmentRows: matchingFragments.map { fragment in
                FragmentRow(
                    fragment: fragment,
                    entryCount: Self.entryCount(of: fragment, in: reading),
                    origin: Self.origin(
                        of: fragment,
                        sources: sources,
                        hasText: reading.fragment(fragment) != nil,
                        at: at
                    )
                )
            },
            selectedProfile: selectedProfile,
            selectedFragment: selectedFragment,
            selection: resolvedSelection.selection,
            hiddenSelection: resolvedSelection.hidden,
            search: search,
            fragmentText: selectedFragmentText,
            layers: layers,
            layerRows: layerRows,
            resolved: resolved,
            renderedBlock: resolved.renderedBlock,
            entryLines: resolved.composition.map(BlockRenderer.entries) ?? [],
            usingProfiles: selectedFragment.map { Self.profiles(using: $0, in: profiles, reading: reading) } ?? [],
            appliedProfiles: live.appliedProfiles,
            liveBlock: live.block,
            live: live.state,
            storeProblem: storeProblem,
            actions: Self.actions(
                profiles: profiles,
                fragments: fragments,
                selectedProfile: selectedProfile,
                selectedFragment: selectedFragment,
                layers: layers,
                live: live.state,
                sources: Set(sources.map(\.fragment))
            ),
            fragmentUsers: Self.fragmentUsers(in: profiles, reading: reading)
        )
    }

    /// What the sidebar's selection resolves to: which item the content pane
    /// edits, and which selection a search hid. A selection that no longer
    /// exists falls back to the first match; a selection the search hides
    /// selects nothing rather than an item the sidebar is not showing.
    private static func resolve(
        _ selection: SidebarSelection?,
        profiles: [ProfileID],
        fragments: [FragmentID],
        searching: Bool
    ) -> (selection: SidebarSelection?, selectedProfile: ProfileID?, selectedFragment: FragmentID?, hidden: SidebarSelection?) {
        switch selection {
        case .profile(let profile):
            if profiles.contains(profile) {
                return (.profile(profile), profile, fragments.first, nil)
            }
            if searching {
                return (nil, nil, fragments.first, .profile(profile))
            }
            if let fallback = profiles.first {
                return (.profile(fallback), fallback, fragments.first, nil)
            }
            return (nil, nil, fragments.first, nil)
        case .fragment(let fragment):
            if fragments.contains(fragment) {
                return (.fragment(fragment), profiles.first, fragment, nil)
            }
            if searching {
                return (nil, profiles.first, nil, .fragment(fragment))
            }
            if let fallback = fragments.first {
                return (.fragment(fallback), profiles.first, fallback, nil)
            }
            return (nil, profiles.first, nil, nil)
        case nil:
            if let profile = profiles.first {
                return (.profile(profile), profile, fragments.first, nil)
            }
            if let fragment = fragments.first {
                return (.fragment(fragment), nil, fragment, nil)
            }
            return (nil, nil, nil, nil)
        }
    }

    /// The entries the fragment holds, as its sidebar row reports them.
    private static func entryCount(of fragment: FragmentID, in reading: StoreReading) -> Int {
        reading.fragment(fragment)?.outcome.fragment.entries.count ?? 0
    }

    /// Where the fragment comes from, or `nil` when it is an ordinary fragment.
    private static func origin(
        of fragment: FragmentID,
        sources: [RemoteSourceReading],
        hasText: Bool,
        at now: Date
    ) -> FragmentRow.Origin? {
        guard let source = sources.first(where: { $0.fragment == fragment }) else { return nil }
        return FragmentRow.Origin(
            url: source.url,
            interval: source.source?.interval,
            lastAttempt: source.source?.lastAttempt,
            lastSuccess: source.source?.lastSuccess,
            failure: source.failure,
            isOutOfDate: !hasText || source.source.map { RemoteSchedule.isOutOfDate($0, at: now) } == true
        )
    }

    private static func layerCount(of profile: ProfileID, in reading: StoreReading) -> Int {
        reading.profile(profile)?.outcome.profile.references.count ?? 0
    }

    private static func profiles(using fragment: FragmentID, in profiles: [ProfileID], reading: StoreReading) -> [ProfileID] {
        profiles.filter { profile in
            guard let parsed = reading.profile(profile) else { return false }
            return parsed.outcome.profile.references.contains { $0.fragment == fragment }
        }
    }

    /// Which profiles reference each fragment, built once from the same reading
    /// so a question about any fragment costs no second pass over the profiles.
    private static func fragmentUsers(in profiles: [ProfileID], reading: StoreReading) -> [FragmentID: [ProfileID]] {
        var users: [FragmentID: [ProfileID]] = [:]
        for profile in profiles {
            guard let parsed = reading.profile(profile) else { continue }
            var seen: Set<FragmentID> = []
            for reference in parsed.outcome.profile.references where seen.insert(reference.fragment).inserted {
                users[reference.fragment, default: []].append(profile)
            }
        }
        return users
    }

    /// The live file read once, classified against the block the selected
    /// profile renders, with the profiles whose block is the live one. One read
    /// answers both, and every profile's rendering comes from the same reading
    /// of the store, so the sidebar's marks cost no second read and no second
    /// parse.
    private func liveReading(
        reading: StoreReading,
        rendering: Data?,
        profiles: [ProfileID]
    ) -> (state: LiveBlockState, appliedProfiles: [ProfileID], block: Data?) {
        let live: Data
        do {
            live = try LiveHostsFile(url: fileURL).read()
        } catch {
            return (.unreadable(reason: "\(error)"), [], nil)
        }

        let located: ManagedBlockLocation?
        do {
            located = try ManagedBlock.locate(in: live)
        } catch let error as BlockError {
            return (.refused(error), [], nil)
        } catch {
            return (.unreadable(reason: "\(error)"), [], nil)
        }

        guard let located else { return (.absent, [], nil) }
        guard located.version == ManagedBlock.version else {
            return (.refused(.unsupportedVersion(found: located.version, expected: ManagedBlock.version)), [], nil)
        }
        let block = Data(live[located.range])
        let applied = profiles.filter { (try? reading.rendering(of: $0)) == block }
        if let rendering, block == rendering { return (.applied, applied, block) }
        return (.drifted(liveBlock: block), applied, block)
    }

    private static func actions(
        profiles: [ProfileID],
        fragments: [FragmentID],
        selectedProfile: ProfileID?,
        selectedFragment: FragmentID?,
        layers: [FragmentID],
        live: LiveBlockState,
        sources: Set<FragmentID>
    ) -> [EditorPresentation.Action] {
        var actions: [EditorPresentation.Action] = [.newProfile, .newFragment]

        if let selectedProfile {
            actions.append(.renameProfile(selectedProfile))
            actions.append(.duplicateProfile(selectedProfile))
            actions.append(.deleteProfile(selectedProfile))
            actions.append(.applyProfile(selectedProfile))
            if case .drifted(let block) = live {
                actions.append(.overwriteDrift(selectedProfile, liveBlock: block))
            }
            for index in layers.indices {
                actions.append(.removeLayer(selectedProfile, index: index))
                if index > 0 {
                    actions.append(.moveLayer(selectedProfile, from: index, to: index - 1))
                }
                if index < layers.count - 1 {
                    actions.append(.moveLayer(selectedProfile, from: index, to: index + 1))
                }
            }
            for fragment in fragments {
                actions.append(.addLayer(selectedProfile, fragment))
            }
        }

        if let selectedFragment {
            actions.append(.renameFragment(selectedFragment))
            actions.append(.duplicateFragment(selectedFragment))
            actions.append(.deleteFragment(selectedFragment))
            if sources.contains(selectedFragment) {
                // A remote fragment's text is the last fetch, so the window
                // presents it read-only and offers the refresh that replaces it
                // instead of a save that would be overwritten.
                actions.append(.refreshSource(selectedFragment))
            } else {
                actions.append(.saveFragment(selectedFragment))
            }
        }

        return actions
    }

    // MARK: - Profiles

    /// Creates a profile with an empty layer stack, creating the store's
    /// directories when they do not exist yet.
    @discardableResult
    public func createProfile(named name: String) -> EditorOutcome {
        plain { try storeWriter.save("", asProfile: ProfileID(name)) }
    }

    @discardableResult
    public func rename(profile: ProfileID, to name: String) -> EditorOutcome {
        plain { try storeWriter.rename(profile: profile, to: ProfileID(name)) }
    }

    @discardableResult
    public func duplicate(profile: ProfileID, as name: String) -> EditorOutcome {
        plain { try storeWriter.duplicate(profile: profile, as: ProfileID(name)) }
    }

    /// Deletes the profile. A block the deleted profile rendered is left in the
    /// live file and reported as drift, because only an apply may write it.
    @discardableResult
    public func delete(profile: ProfileID) -> EditorOutcome {
        plain { try storeWriter.delete(profile: profile) }
    }

    // MARK: - Fragments

    /// Creates a fragment with placeholder text an editor can replace.
    @discardableResult
    public func createFragment(named name: String) -> EditorOutcome {
        plain { try storeWriter.save("", asFragment: FragmentID(name)) }
    }

    @discardableResult
    public func rename(fragment: FragmentID, to name: String) -> EditorOutcome {
        plain { try storeWriter.rename(fragment: fragment, to: FragmentID(name)) }
    }

    @discardableResult
    public func duplicate(fragment: FragmentID, as name: String) -> EditorOutcome {
        plain { try storeWriter.duplicate(fragment: fragment, as: FragmentID(name)) }
    }

    @discardableResult
    public func delete(fragment: FragmentID) -> EditorOutcome {
        plain { try storeWriter.delete(fragment: fragment) }
    }

    /// Records where the fragment is fetched from, leaving its text alone. A
    /// source's origin is authored exactly like a fragment, so this needs no
    /// helper and no privilege; the text follows on the first fetch that
    /// succeeds.
    @discardableResult
    public func recordSource(_ source: RemoteSource, as fragment: FragmentID) -> EditorOutcome {
        plain { try storeWriter.save(source, as: fragment) }
    }

    /// Forgets a source's origin. A caller that wants the text gone too deletes
    /// the fragment, which takes the sidecar with it.
    @discardableResult
    public func removeSource(_ fragment: FragmentID) -> EditorOutcome {
        plain { try storeWriter.deleteRemoteSource(fragment) }
    }

    // MARK: - Edits that can reach the live file

    /// Saves the fragment's text, then re-applies the profile when its block is
    /// live and is still the block that profile rendered before the edit.
    /// `profile` is `nil` when the store holds none: the text is saved and there
    /// is nothing to re-apply.
    @discardableResult
    public func save(
        fragment: FragmentID,
        text: String,
        editing profile: ProfileID?,
        previous: EditorPresentation
    ) -> EditorOutcome {
        guard let profile else {
            return plain { try storeWriter.save(text, asFragment: fragment) }
        }
        return writing(profile: profile, previous: previous) {
            try storeWriter.save(text, asFragment: fragment)
        }
    }

    // MARK: - Refreshing a source

    /// Fetches the fragment's source and stores what came back, then re-applies
    /// the profile whose block is live when that profile stacks the refreshed
    /// fragment.
    ///
    /// A refresh that changed the text is an edit: it goes through the store
    /// writer and the same re-apply path, with the live block named as the
    /// replacement, so a live file that moved since the read is reported as
    /// drift rather than overwritten. A refresh of a fragment no applied profile
    /// stacks leaves the live file alone.
    public func refresh(
        fragment: FragmentID,
        source: RemoteSource,
        previous: EditorPresentation,
        fetcher: any RemoteFetching,
        at now: Date = Date()
    ) async -> EditorOutcome {
        let refresher = RemoteRefresher(layout: layout, writer: storeWriter, fetcher: fetcher)
        let refresh = await refresher.refresh(fragment: fragment, source: source, at: now)

        guard refresh.didWrite else {
            return EditorOutcome(store: .success(.unchanged), refresh: refresh)
        }

        let store: Result<StoreWrite, StoreWriteError> = .success(.wrote)
        guard let profile = Self.appliedProfile(stacking: fragment, in: previous), let before = previous.liveBlock else {
            return EditorOutcome(store: store, refresh: refresh)
        }
        return applying(profile: profile, replacing: before, store: store, refresh: refresh)
    }

    /// The live profile that stacks `fragment`, when one does. Every applied
    /// profile renders the live block, so when one of them stacks the refreshed
    /// fragment the first is the one to re-apply.
    private static func appliedProfile(stacking fragment: FragmentID, in previous: EditorPresentation) -> ProfileID? {
        let users = previous.stacks(fragment)
        return previous.appliedProfiles.first { users.contains($0) }
    }

    @discardableResult
    public func addLayer(
        _ fragment: FragmentID,
        to profile: ProfileID,
        previous: EditorPresentation
    ) -> EditorOutcome {
        layers(previous.layers + [fragment], for: profile, previous: previous)
    }

    @discardableResult
    public func removeLayer(
        at index: Int,
        from profile: ProfileID,
        previous: EditorPresentation
    ) -> EditorOutcome {
        guard previous.layers.indices.contains(index) else {
            return EditorOutcome(problem: "layer \(index + 1) is not in the stack")
        }
        var remaining = previous.layers
        remaining.remove(at: index)
        return layers(remaining, for: profile, previous: previous)
    }

    /// Moves the layer at `index` to `destination`, changing which layer wins.
    @discardableResult
    public func moveLayer(
        from index: Int,
        to destination: Int,
        in profile: ProfileID,
        previous: EditorPresentation
    ) -> EditorOutcome {
        guard previous.layers.indices.contains(index), previous.layers.indices.contains(destination) else {
            return EditorOutcome(problem: "the layer to move is not in the stack")
        }
        var reordered = previous.layers
        let layer = reordered.remove(at: index)
        reordered.insert(layer, at: destination)
        return layers(reordered, for: profile, previous: previous)
    }

    private func layers(
        _ layers: [FragmentID],
        for profile: ProfileID,
        previous: EditorPresentation
    ) -> EditorOutcome {
        writing(profile: profile, previous: previous) {
            try storeWriter.save(ProfileText.render(layers), asProfile: profile)
        }
    }

    // MARK: - The two write paths

    /// Applies a profile's block, and reports what the apply did together with
    /// what is needed to undo it: the block written, and the block it replaced
    /// (`nil` when it installed where the file held none). Nothing is recorded
    /// for an apply that did not write.
    public func apply(
        _ profile: ProfileID,
        replacing replacement: Replacement
    ) -> (outcome: ApplyOutcome, change: ApplyRecord?) {
        let block: Data
        do {
            block = try BlockRenderer.render(composer.compose(profile: profile))
        } catch {
            return (.failed(reason: "rendering \(profile): \(error)"), nil)
        }

        let outcome = applier.apply(block: block, replacement: replacement)
        guard outcome.isApplied else { return (outcome, nil) }

        let replaced: Data?
        switch replacement {
        case .onlyIfAbsent: replaced = nil
        case .block(let expected): replaced = expected
        }
        return (outcome, ApplyRecord(profile: profile, block: block, replaced: replaced))
    }

    /// Undoes an apply by replacing the block it wrote with the block it
    /// replaced, or by removing the block when the apply installed it. The
    /// apply's own byte-identity check refuses a revert once the live block is
    /// no longer the block that apply wrote.
    public func revert(_ change: ApplyRecord) -> ApplyOutcome {
        let live: Data
        do {
            live = try LiveHostsFile(url: fileURL).read()
        } catch {
            return .failed(reason: "reading \(fileURL.path): \(error)")
        }

        let present: Data?
        do {
            if let located = try ManagedBlock.locate(in: live) {
                present = Data(live[located.range])
            } else {
                present = nil
            }
        } catch let error as BlockError {
            return .refused(.liveFile(error))
        } catch {
            return .refused(.liveFile(.invalidBlock("\(error)")))
        }

        guard present == change.block else { return .refused(.driftNotOverwritten) }
        guard let replaced = change.replaced else {
            return applier.removeBlock()
        }
        return applier.apply(block: replaced, replacement: .block(change.block))
    }

    /// A store change that cannot reach the live file: authoring is unprivileged
    /// and needs no helper.
    private func plain(_ body: () throws -> StoreWrite) -> EditorOutcome {
        do {
            return EditorOutcome(store: .success(try body()))
        } catch let error as StoreWriteError {
            return EditorOutcome(store: .failure(error))
        } catch {
            return EditorOutcome(store: .failure(.failed("\(error)")))
        }
    }

    /// Writes the store first, then re-applies the profile whose block is live,
    /// naming the block that profile rendered before the edit. The store write
    /// is already durable when the apply runs, so a refused apply leaves the
    /// edit in place and reports the reason.
    private func writing(
        profile: ProfileID,
        previous: EditorPresentation,
        _ body: () throws -> StoreWrite
    ) -> EditorOutcome {
        let write: StoreWrite
        do {
            write = try body()
        } catch let error as StoreWriteError {
            return EditorOutcome(store: .failure(error))
        } catch {
            return EditorOutcome(store: .failure(.failed("\(error)")))
        }

        guard write == .wrote, previous.isApplied, let before = previous.rendering else {
            return EditorOutcome(store: .success(write))
        }
        return applying(profile: profile, replacing: before, store: .success(write))
    }

    /// The apply half of a change that can reach the live file: renders the
    /// profile again and replaces `before` with it through the privileged write.
    /// `before` is the block the live file is expected to hold, so the applier's
    /// own byte-identity check refuses a file that moved and reports drift
    /// instead of overwriting it.
    private func applying(
        profile: ProfileID,
        replacing before: Data,
        store: Result<StoreWrite, StoreWriteError>,
        refresh: RemoteRefresh? = nil
    ) -> EditorOutcome {
        let block: Data
        do {
            block = try BlockRenderer.render(composer.compose(profile: profile))
        } catch {
            return EditorOutcome(
                store: store,
                apply: .failed(reason: "the changed profile cannot be rendered: \(error)"),
                refresh: refresh
            )
        }
        return EditorOutcome(
            store: store,
            apply: applier.apply(block: block, replacement: .block(before)),
            refresh: refresh
        )
    }
}

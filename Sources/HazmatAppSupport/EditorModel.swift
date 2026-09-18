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

    public init(
        store: Result<StoreWrite, StoreWriteError>? = nil,
        apply: ApplyOutcome? = nil,
        problem: String? = nil
    ) {
        self.store = store
        self.apply = apply
        self.problem = problem
    }

    /// Whether the store is different afterwards.
    public var didChangeTheStore: Bool {
        guard case .success(let write)? = store else { return false }
        return write.didChange
    }

    public var description: String {
        var parts: [String] = []
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

    public init(storeRoot: URL, fileURL: URL, writer: PrivilegedWriter) {
        layout = StoreLayout(root: storeRoot)
        self.fileURL = fileURL
        self.writer = writer
    }

    private var store: DirectoryStore { DirectoryStore(root: layout.root) }
    private var composer: HostsComposer { HostsComposer(store: store) }
    private var storeWriter: StoreWriter { StoreWriter(layout: layout) }
    private var applier: HostsFileApplier { HostsFileApplier(fileURL: fileURL, writer: writer) }

    // MARK: - Reading

    /// Reads the store's profiles and fragments, the selected items' detail, and
    /// what the live file holds. Nothing is cached, so a file another tool wrote
    /// appears in the next read.
    public func read(
        selection: SidebarSelection? = nil,
        search: StoreSearch = .none
    ) -> EditorPresentation {
        let profiles = layout.profiles()
        let fragments = layout.fragments()
        let matchingProfiles = search.profiles(profiles)
        let matchingFragments = search.fragments(fragments)

        let resolvedSelection = Self.resolve(selection, profiles: matchingProfiles, fragments: matchingFragments, searching: search.isActive)
        let selectedProfile = resolvedSelection.selectedProfile ?? (selection == nil ? matchingProfiles.first : nil)
        let selectedFragment = resolvedSelection.selectedFragment ?? (selection == nil ? matchingFragments.first : nil)

        let selectedFragmentText = selectedFragment.flatMap { fragmentText(of: $0) } ?? ""

        var layers: [FragmentID] = []
        var layerRows: [LayerRow] = []
        if let selectedProfile, let text = profileText(of: selectedProfile) {
            layers = ProfileParser.parse(text, as: selectedProfile).profile.references.map(\.fragment)
            layerRows = layers.enumerated().map { index, fragment in
                LayerRow(fragment: fragment, position: index + 1, entryCount: entryCount(of: fragment))
            }
        }

        var storeProblem: String?
        let resolved: ResolvedView
        if let selectedProfile {
            do {
                resolved = .composed(try composer.compose(profile: selectedProfile))
            } catch let error as CompositionError {
                resolved = .unresolvable(error.problems)
            } catch {
                storeProblem = "\(error)"
                resolved = .unresolvable([])
            }
        } else {
            resolved = .unresolvable([])
        }

        let live = liveReading(rendering: resolved.renderedBlock, profiles: profiles)

        return EditorPresentation(
            storePath: layout.root.path,
            hostsFilePath: fileURL.path,
            storeExists: layout.exists,
            profiles: profiles,
            fragments: fragments,
            profileRows: matchingProfiles.map { profile in
                ProfileRow(
                    profile: profile,
                    layerCount: layerCount(of: profile),
                    isApplied: live.appliedProfiles.contains(profile)
                )
            },
            fragmentRows: matchingFragments.map { fragment in
                FragmentRow(fragment: fragment, entryCount: entryCount(of: fragment))
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
            entryLines: resolved.composition.map(BlockRenderer.entries) ?? [],
            usingProfiles: selectedFragment.map { profilesUsing($0, in: profiles) } ?? [],
            appliedProfiles: live.appliedProfiles,
            live: live.state,
            storeProblem: storeProblem,
            actions: Self.actions(
                profiles: profiles,
                fragments: fragments,
                selectedProfile: selectedProfile,
                selectedFragment: selectedFragment,
                layers: layers,
                live: live.state
            )
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

    private func fragmentText(of fragment: FragmentID) -> String? {
        guard let text = try? store.fragment(named: fragment) else { return nil }
        return text
    }

    private func profileText(of profile: ProfileID) -> String? {
        guard let text = try? store.profile(named: profile) else { return nil }
        return text
    }

    /// The entries the fragment holds, as its sidebar row reports them.
    private func entryCount(of fragment: FragmentID) -> Int {
        guard let text = fragmentText(of: fragment) else { return 0 }
        return FragmentParser.parse(text, as: fragment).fragment.entries.count
    }

    private func layerCount(of profile: ProfileID) -> Int {
        guard let text = profileText(of: profile) else { return 0 }
        return ProfileParser.parse(text, as: profile).profile.references.count
    }

    private func profilesUsing(_ fragment: FragmentID, in profiles: [ProfileID]) -> [ProfileID] {
        profiles.filter { profile in
            guard let text = profileText(of: profile) else { return false }
            return ProfileParser.parse(text, as: profile).profile.references.contains { $0.fragment == fragment }
        }
    }

    /// The block a profile renders, or `nil` when it cannot be resolved.
    public func renderedBlock(of profile: ProfileID) -> Data? {
        guard let composition = try? composer.compose(profile: profile) else { return nil }
        return BlockRenderer.render(composition)
    }

    /// The live file read once, classified against the block the selected
    /// profile renders, with the profiles whose block is the live one. One read
    /// answers both, so the sidebar's marks cost no second read.
    private func liveReading(rendering: Data?, profiles: [ProfileID]) -> (state: LiveBlockState, appliedProfiles: [ProfileID]) {
        let live: Data
        do {
            live = try LiveHostsFile(url: fileURL).read()
        } catch {
            return (.unreadable(reason: "\(error)"), [])
        }

        let located: ManagedBlockLocation?
        do {
            located = try ManagedBlock.locate(in: live)
        } catch let error as BlockError {
            return (.refused(error), [])
        } catch {
            return (.unreadable(reason: "\(error)"), [])
        }

        guard let located else { return (.absent, []) }
        guard located.version == ManagedBlock.version else {
            return (.refused(.unsupportedVersion(found: located.version, expected: ManagedBlock.version)), [])
        }
        let block = Data(live[located.range])
        let applied = profiles.filter { renderedBlock(of: $0) == block }
        if let rendering, block == rendering { return (.applied, applied) }
        return (.drifted(liveBlock: block), applied)
    }

    private static func actions(
        profiles: [ProfileID],
        fragments: [FragmentID],
        selectedProfile: ProfileID?,
        selectedFragment: FragmentID?,
        layers: [FragmentID],
        live: LiveBlockState
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
            actions.append(.saveFragment(selectedFragment))
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

    // MARK: - Edits that can reach the live file

    /// Saves the fragment's text, then re-applies the profile when its block is
    /// live and is still the block that profile rendered before the edit.
    @discardableResult
    public func save(
        fragment: FragmentID,
        text: String,
        editing profile: ProfileID,
        previous: EditorPresentation
    ) -> EditorOutcome {
        writing(profile: profile, previous: previous) {
            try storeWriter.save(text, asFragment: fragment)
        }
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

        let block: Data
        do {
            block = try BlockRenderer.render(composer.compose(profile: profile))
        } catch {
            return EditorOutcome(
                store: .success(write),
                apply: .failed(reason: "the edited profile cannot be rendered: \(error)")
            )
        }
        return EditorOutcome(
            store: .success(write),
            apply: applier.apply(block: block, replacement: .block(before))
        )
    }
}

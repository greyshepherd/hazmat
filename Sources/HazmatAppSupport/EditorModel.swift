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

    /// Reads the store's profiles and fragments, the selected fragment's text,
    /// the selected profile's layer list, and what the live file holds for it.
    /// Nothing is cached, so a file another tool wrote appears in the next read.
    public func read(profile: ProfileID? = nil, fragment: FragmentID? = nil) -> EditorPresentation {
        let profiles = layout.profiles()
        let fragments = layout.fragments()
        let selectedProfile = Self.selected(profile, in: profiles)
        let selectedFragment = Self.selected(fragment, in: fragments)

        let fragmentText = selectedFragment
            .flatMap { try? store.fragment(named: $0) }
            .flatMap { $0 } ?? ""

        var layers: [FragmentID] = []
        if let selectedProfile, let text = (try? store.profile(named: selectedProfile)) ?? nil {
            layers = ProfileParser.parse(text, as: selectedProfile).profile.references.map(\.fragment)
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

        let live = liveState(rendering: resolved.renderedBlock)
        return EditorPresentation(
            storePath: layout.root.path,
            storeExists: layout.exists,
            profiles: profiles,
            fragments: fragments,
            selectedProfile: selectedProfile,
            selectedFragment: selectedFragment,
            fragmentText: fragmentText,
            layers: layers,
            resolved: resolved,
            live: live,
            storeProblem: storeProblem,
            actions: Self.actions(
                profiles: profiles,
                fragments: fragments,
                selectedProfile: selectedProfile,
                selectedFragment: selectedFragment,
                layers: layers,
                live: live
            )
        )
    }

    /// The live file read now, classified against the block the selected profile
    /// renders now.
    private func liveState(rendering: Data?) -> LiveBlockState {
        let live: Data
        do {
            live = try LiveHostsFile(url: fileURL).read()
        } catch {
            return .unreadable(reason: "\(error)")
        }

        let located: ManagedBlockLocation?
        do {
            located = try ManagedBlock.locate(in: live)
        } catch let error as BlockError {
            return .refused(error)
        } catch {
            return .unreadable(reason: "\(error)")
        }

        guard let located else { return .absent }
        guard located.version == ManagedBlock.version else {
            return .refused(.unsupportedVersion(found: located.version, expected: ManagedBlock.version))
        }
        let block = Data(live[located.range])
        if let rendering, block == rendering { return .applied }
        return .drifted(liveBlock: block)
    }

    private static func selected<T: Equatable>(_ wanted: T?, in available: [T]) -> T? {
        if let wanted, available.contains(wanted) { return wanted }
        return available.first
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

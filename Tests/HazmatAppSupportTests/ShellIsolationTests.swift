import Foundation
import XCTest

final class ShellIsolationTests: XCTestCase {
    /// What is still absent: packaging, signing, notarization, and the update
    /// channel. The profile editor and the resolved view are built, so they are
    /// no longer guarded against; the editor's own thinness is guarded below.
    func testTheSourcesCarryNoPackagingSigningNotarizationOrUpdateCode() {
        let sources = [
            "Sources/HazmatApp",
            "Sources/HazmatAppSupport",
            "Sources/HazmatCore",
            "Sources/HazmatDaemon",
            "Sources/HazmatPrivileged",
            "Sources/HazmatProtocol"
        ].flatMap { sourceFiles(in: $0) }
        XCTAssertFalse(sources.isEmpty, "the sources are missing")

        let forbidden = [
            "pkgbuild",
            "productbuild",
            "hdiutil",
            "__MACOSX",
            "codesign",
            "notariz",
            "Notariz",
            "notarytool",
            "altool",
            "stapler",
            "Sparkle",
            "SUUpdater",
            "SUFeedURL",
            "appcast"
        ]

        for (file, source) in sources {
            for needle in forbidden {
                XCTAssertNil(source.range(of: needle), "\(file) contains \(needle)")
            }
        }
    }

    /// Everything the window renders and forwards. A scene names no store, no
    /// composition, and no file path; those arrive as presentation values.
    private static let windowScenes = [
        "ShellView.swift",
        "SidebarView.swift",
        "ContentPane.swift",
        "DetailPane.swift",
        "StatusRow.swift",
        "HelperSheetView.swift",
        "SettingsView.swift",
        "ShellCommands.swift",
        "StatusMark.swift",
        "WindowViews.swift"
    ]

    private static let storeAndCompositionNames = [
        "StoreLayout",
        "StoreWriter",
        "DirectoryStore",
        "InMemoryStore",
        "HostsStore",
        "HostsComposer",
        "Composition",
        "BlockRenderer",
        "ManagedBlock",
        "LiveHostsFile",
        "ProfileCatalogue",
        "ProfileParser",
        "EditorModel",
        "HostsFileApplier",
        "PrivilegedWriter",
        "DaemonClient",
        "ApplyOutcome",
        "Replacement",
        "FileManager",
        "appendingPathComponent",
        "Data(contentsOf",
        "String(contentsOf",
        "URL("
    ]

    /// The editor scene renders the presentation and forwards choices. The rest
    /// of the window is held to the same rule below.
    func testTheEditorSceneDecidesNothingItself() {
        let scene = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellView.swift" }?.1 ?? ""
        XCTAssertFalse(scene.isEmpty, "the editor scene is missing")
        XCTAssertTrue(scene.contains("EditorPresentation"), scene)
        XCTAssertTrue(scene.contains("let editor: EditorPresentation = model.editor"), scene)

        for needle in Self.storeAndCompositionNames {
            XCTAssertNil(scene.range(of: needle), "the editor scene contains \(needle)")
        }
    }

    /// Every window scene added with the three panes is held to the same rule:
    /// the store, the composition and the paths stay in app support.
    func testEveryWindowSceneDecidesNothingItself() {
        let scenes = sourceFiles(in: "Sources/HazmatApp").filter { Self.windowScenes.contains($0.0) }
        XCTAssertEqual(
            scenes.map(\.0).sorted(),
            Self.windowScenes.sorted(),
            "the window scenes are missing"
        )

        for (file, scene) in scenes {
            for needle in Self.storeAndCompositionNames {
                XCTAssertNil(scene.range(of: needle), "\(file) contains \(needle)")
            }
        }
    }

    func testTheShellIsOneAppWithOneWindowAndOneStatusItem() {
        let entryPoint = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "HazmatApp.swift" }?.1 ?? ""

        XCTAssertTrue(entryPoint.contains("@main"), entryPoint)
        XCTAssertTrue(entryPoint.contains("struct HazmatApp: App"), entryPoint)
        XCTAssertTrue(entryPoint.contains("Window(\"Hazmat\", id: Self.windowID)"), entryPoint)
        XCTAssertFalse(entryPoint.contains("WindowGroup"), entryPoint)
        XCTAssertTrue(entryPoint.contains("MenuBarExtra"), entryPoint)
    }

    /// The shell model may know the live file's path, but every write goes
    /// through the writer it was handed, never through one it made for itself.
    func testTheShellOnlyWritesThroughTheInjectedWriter() {
        let model = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellModel.swift" }?.1 ?? ""

        XCTAssertTrue(model.contains("writer: PrivilegedWriter? = nil"), model)
        let daemonClient = "Daemon" + "Client()"
        XCTAssertTrue(model.contains("let writer = writer ?? client"), model)
        XCTAssertTrue(model.contains("let client = \(daemonClient)"), model)
        XCTAssertTrue(model.contains("writer: writer"), model)
        XCTAssertFalse(model.contains("\(daemonClient).write"), model)
        XCTAssertFalse(model.contains("\(daemonClient).removeBlock"), model)
    }

    /// One model, shared by the window, the settings scene, the commands and the
    /// status item, so they cannot disagree about the store they are looking at.
    func testTheAppCreatesOneModelAndHandsItToEveryScene() {
        let sources = sourceFiles(in: "Sources/HazmatApp")
        let constructions = sources.reduce(0) { total, source in
            total + source.1.components(separatedBy: "ShellModel()").count - 1
        }

        XCTAssertEqual(constructions, 1, "one instance, shared: \(sources.map(\.0))")

        let entryPoint = sources.first { $0.0 == "HazmatApp.swift" }?.1 ?? ""
        XCTAssertTrue(entryPoint.contains("ShellView(model: model)"), entryPoint)
        XCTAssertTrue(entryPoint.contains("StatusMenu(model: model)"), entryPoint)
        XCTAssertTrue(entryPoint.contains("SettingsView(model: model)"), entryPoint)
        XCTAssertTrue(entryPoint.contains("ShellCommands(model: model)"), entryPoint)
        XCTAssertTrue(entryPoint.contains("StatusMark(model: model)"), entryPoint)
    }

    /// The entry point declares scenes and nothing else: no item, label, or
    /// condition lives there.
    func testTheAppEntryPointHoldsNothingBeyondTheScenes() {
        let entryPoint = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "HazmatApp.swift" }?.1 ?? ""

        XCTAssertTrue(
            entryPoint.contains("StatusMark(model: model)"),
            "the status item's label comes from the mark beside the presentation: \(entryPoint)"
        )
        XCTAssertTrue(
            entryPoint.contains("Settings {"),
            "the settings scene is declared in the entry point: \(entryPoint)"
        )
        XCTAssertTrue(
            entryPoint.contains(".commands { ShellCommands(model: model) }"),
            "the menu bar is declared in the entry point: \(entryPoint)"
        )
        XCTAssertTrue(
            entryPoint.contains(".defaultSize(width: 1080, height: 700)"),
            "the documented default size is declared in the entry point: \(entryPoint)"
        )

        for needle in ["if ", "guard ", "switch ", "ForEach", "filter", ".contains(", "== "] {
            XCTAssertNil(entryPoint.range(of: needle), "\(entryPoint) contains \(needle)")
        }

        let mark = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "StatusMark.swift" }?.1 ?? ""
        XCTAssertTrue(mark.contains("Text(model.menu.statusTitle)"), mark)
    }

    /// The menu bar scene renders the presentation; it does not name labels,
    /// decide item sets, or read the store and the file itself.
    func testTheMenuBarSceneDecidesNothingItself() {
        let menu = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "StatusMenu.swift" }?.1 ?? ""

        XCTAssertFalse(menu.isEmpty, "the menu bar scene is missing")
        XCTAssertTrue(menu.contains("MenuPresentation"), menu)
        XCTAssertTrue(menu.contains("let action = item.action"), menu)

        for label in ["Overwrite", "Register Helper", "Turn Hazmat Off", "Hazmat:", "catalogue", "ProfileCatalogue"] {
            XCTAssertNil(menu.range(of: label), "\(menu) contains \(label)")
        }
    }
}

import Foundation
import XCTest

final class ShellIsolationTests: XCTestCase {
    /// Where packaging, signing, notarization, and update code may live: nowhere
    /// below the app. The core, the protocol, the privileged side, and app
    /// support describe behavior, so none of them may reach for a feed, a
    /// signature, or a tool that ships a release.
    func testThePackagingAndUpdateVocabularyStaysOutOfTheLibraries() {
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

        for directory in [
            "Sources/HazmatCore",
            "Sources/HazmatProtocol",
            "Sources/HazmatPrivileged",
            "Sources/HazmatAppSupport"
        ] {
            let sources = sourceFiles(in: directory)
            XCTAssertFalse(sources.isEmpty, "\(directory) has no sources")
            for (file, source) in sources {
                for needle in forbidden {
                    XCTAssertNil(source.range(of: needle), "\(directory)/\(file) contains \(needle)")
                }
            }
        }
    }

    /// ... and in the app it is one file: the adapter that performs the check.
    /// Everything else, including the presentation, talks about updates without
    /// knowing what performs them.
    func testTheAppNamesTheUpdateFrameworkInOnePlace() {
        let sources = sourceFiles(in: "Sources/HazmatApp")
        let naming = sources.filter { $0.1.contains("Sparkle") }.map(\.0)
        XCTAssertEqual(naming, ["UpdateChecker.swift"], "the update framework is named in: \(naming)")

        let adapter = sources.first { $0.0 == "UpdateChecker.swift" }?.1 ?? ""
        XCTAssertTrue(adapter.contains("import Sparkle"), adapter)
        XCTAssertTrue(adapter.contains("UpdateChecking"), "the adapter must implement what app support declares")

        for (file, source) in sources where file != "UpdateChecker.swift" {
            XCTAssertNil(source.range(of: "SUFeedURL"), "\(file) reads the feed for itself")
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

    /// The editor scene renders and forwards; it names no store, composition or
    /// path type. The panes it composes are held to the same rule below.
    func testTheEditorSceneDecidesNothingItself() {
        let scene = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellView.swift" }?.1 ?? ""
        XCTAssertFalse(scene.isEmpty, "the editor scene is missing")

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
            total + source.1.components(separatedBy: "ShellModel(").count - 1
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
        XCTAssertTrue(mark.contains("accessibilityLabel(model.menu.statusTitle)"), mark)
        XCTAssertNil(mark.range(of: "Text("), "the bar carries the mark alone: \(mark)")
    }

    /// The mark is a template image the system tints and the app never
    /// recolours. One file reads it from the bundle; the status item shows it
    /// alone, so its accessibility name is what still says what is on.
    func testTheMarkIsATemplateTheSystemTints() {
        let loader = sourceFiles(in: "Sources/HazmatAppSupport").first { $0.0 == "MenuMark.swift" }?.1 ?? ""
        XCTAssertFalse(loader.isEmpty, "the mark's loader is missing")
        XCTAssertTrue(loader.contains("isTemplate = true"), loader)
        XCTAssertTrue(
            loader.contains("forResource: \"menu-bar-template\""),
            "the mark must be looked up by name: \(loader)"
        )
        // Both the one-times and the two-times file have to be loaded, or the
        // mark is soft on a Retina menu bar.
        XCTAssertTrue(
            loader.contains("menu-bar-template@2x"),
            "the two-times representation must be attached by hand: \(loader)"
        )

        let label = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "StatusMark.swift" }?.1 ?? ""
        XCTAssertFalse(label.isEmpty, "the status item's mark is missing")
        XCTAssertTrue(
            label.contains("accessibilityLabel(model.menu.statusTitle)"),
            "the mark carries the state, so it must name it: \(label)"
        )

        let sources =
            sourceFiles(in: "Sources/HazmatApp") + sourceFiles(in: "Sources/HazmatAppSupport")
        for (file, source) in sources {
            for needle in ["renderingMode(.original)", "isTemplate = false", "isTemplate=false", ".tint("] {
                XCTAssertNil(source.range(of: needle), "\(file) recolours the mark with \(needle)")
            }
        }
    }

    /// The application menu's settings item belongs to the settings scene, which
    /// declares it. A command group that replaces that group renders a second one,
    /// so the menu shows the same control twice.
    func testTheApplicationMenuDoesNotRenderASecondSettingsItem() {
        let commands = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellCommands.swift" }?.1 ?? ""
        XCTAssertFalse(commands.isEmpty, "the commands scene is missing")

        XCTAssertNil(
            commands.range(of: "replacing: .appSettings"),
            "the settings item is the settings scene's own: \(commands)"
        )
        XCTAssertNil(commands.range(of: "openSettings()"), "the settings scene opens itself: \(commands)")
    }

    /// The commands scene renders the model's one value. Rebuilding it is a second
    /// copy that can disagree with it, and the update check it would drop is the
    /// kind of disagreement nothing else catches.
    func testTheCommandsSceneRendersTheModelsOwnMenu() {
        let commands = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellCommands.swift" }?.1 ?? ""
        XCTAssertFalse(commands.isEmpty, "the commands scene is missing")

        XCTAssertTrue(commands.contains("model.commands"), commands)
        XCTAssertNil(
            commands.range(of: "CommandPresentation.menuBar("),
            "the menu bar is built once, in the model: \(commands)"
        )
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

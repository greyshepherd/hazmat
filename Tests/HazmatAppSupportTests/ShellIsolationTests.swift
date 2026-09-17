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

    /// The editor scene renders the presentation and forwards choices: it names
    /// no store, no composition, and no file path. The menu bar scene is held to
    /// the same rule below.
    func testTheEditorSceneDecidesNothingItself() {
        let scene = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellView.swift" }?.1 ?? ""
        XCTAssertFalse(scene.isEmpty, "the editor scene is missing")
        XCTAssertTrue(scene.contains("EditorPresentation"), scene)
        XCTAssertTrue(scene.contains("let editor = model.editor"), scene)

        let forbidden = [
            "StoreLayout",
            "StoreWriter",
            "DirectoryStore",
            "InMemoryStore",
            "HostsStore",
            "HostsComposer",
            "Composition",
            "ProfileCatalogue",
            "ProfileParser",
            "EditorModel",
            "HostsFileApplier",
            "PrivilegedWriter",
            "DaemonClient",
            "FileManager",
            "appendingPathComponent",
            "Data(contentsOf",
            "String(contentsOf",
            "URL("
        ]

        for needle in forbidden {
            XCTAssertNil(scene.range(of: needle), "the editor scene contains \(needle)")
        }
    }

    func testTheShellIsOneAppWithOneWindowAndOneStatusItem() {
        let entryPoint = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "HazmatApp.swift" }?.1 ?? ""

        XCTAssertTrue(entryPoint.contains("@main"), entryPoint)
        XCTAssertTrue(entryPoint.contains("struct HazmatApp: App"), entryPoint)
        XCTAssertTrue(entryPoint.contains("WindowGroup"), entryPoint)
        XCTAssertTrue(entryPoint.contains("MenuBarExtra"), entryPoint)
    }

    func testTheShellOnlyWritesThroughTheInjectedWriter() {
        let model = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellModel.swift" }?.1 ?? ""
        let construction = "HostsFileApplier(fileURL: fileURL, writer: writer ?? Daemon" + "Client())"

        XCTAssertTrue(model.contains(construction), model)
    }

    /// One model, so the window and the status item cannot disagree about the
    /// file they are both looking at.
    func testTheAppCreatesOneModelAndHandsItToBothScenes() {
        let sources = sourceFiles(in: "Sources/HazmatApp")
        let constructions = sources.reduce(0) { total, source in
            total + source.1.components(separatedBy: "ShellModel()").count - 1
        }

        XCTAssertEqual(constructions, 1, "one instance, shared: \(sources.map(\.0))")

        let entryPoint = sources.first { $0.0 == "HazmatApp.swift" }?.1 ?? ""
        XCTAssertTrue(entryPoint.contains("ShellView(model: model)"), entryPoint)
        XCTAssertTrue(entryPoint.contains("StatusMenu(model: model)"), entryPoint)
    }

    /// The entry point declares scenes and nothing else: no item, label, or
    /// condition lives there.
    func testTheAppEntryPointHoldsNothingBeyondTheScenes() {
        let entryPoint = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "HazmatApp.swift" }?.1 ?? ""

        XCTAssertTrue(
            entryPoint.contains("Text(model.menu.statusTitle)"),
            "the title must come from the presentation in app support: \(entryPoint)"
        )

        for needle in ["if ", "guard ", "switch ", "ForEach", "filter", ".contains(", "== "] {
            XCTAssertNil(entryPoint.range(of: needle), "\(entryPoint) contains \(needle)")
        }
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

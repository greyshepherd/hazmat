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
            total + source.1.components(separatedBy: "ShellModel(").count - 1
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
            entryPoint.contains("StatusLabel(title: model.menu.statusTitle)"),
            "the status item's content must come from the presentation in app support: \(entryPoint)"
        )

        for needle in ["if ", "guard ", "switch ", "ForEach", "filter", ".contains(", "== "] {
            XCTAssertNil(entryPoint.range(of: needle), "\(entryPoint) contains \(needle)")
        }
    }

    /// The mark is a template image the system tints, and the title beside it is
    /// the part that says what is on.
    func testTheMarkIsATemplateTheSystemTints() {
        let mark = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "StatusMark.swift" }?.1 ?? ""
        XCTAssertFalse(mark.isEmpty, "the status item's mark is missing")
        XCTAssertTrue(mark.contains("isTemplate = true"), mark)
        XCTAssertTrue(mark.contains("Text(title)"), "the mark must not replace the state title: \(mark)")

        for (file, source) in sourceFiles(in: "Sources/HazmatApp") {
            for needle in ["renderingMode(.original)", "isTemplate = false", "isTemplate=false", ".tint("] {
                XCTAssertNil(source.range(of: needle), "\(file) recolours the mark with \(needle)")
            }
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

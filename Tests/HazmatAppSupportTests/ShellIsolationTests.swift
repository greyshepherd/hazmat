import Foundation
import XCTest

final class ShellIsolationTests: XCTestCase {
    func testTheShellCarriesNoProfileEditorAndNoResolvedView() {
        let sources = sourceFiles(in: "Sources/HazmatApp")
        XCTAssertFalse(sources.isEmpty, "the app target has no sources")

        let forbidden = [
            "NSStatusItem",
            "NSStatusBar",
            "Settings {",
            "Settings(",
            "ProfileEditor",
            "TextField",
            "TextEditor",
            "onDelete",
            ".resolved"
        ]

        for (file, source) in sources {
            for needle in forbidden {
                XCTAssertNil(source.range(of: needle), "\(file) contains \(needle)")
            }
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

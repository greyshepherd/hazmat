import Foundation
import XCTest

final class ShellIsolationTests: XCTestCase {
    func testTheShellCarriesNoMenuBarItemNoProfileEditorAndNoResolvedView() {
        let sources = sourceFiles(in: "Sources/HazmatApp")
        XCTAssertFalse(sources.isEmpty, "the app target has no sources")

        let forbidden = [
            "MenuBarExtra",
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

    func testTheShellIsOneAppWithOneWindow() {
        let entryPoint = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "HazmatApp.swift" }?.1 ?? ""

        XCTAssertTrue(entryPoint.contains("@main"), entryPoint)
        XCTAssertTrue(entryPoint.contains("struct HazmatApp: App"), entryPoint)
        XCTAssertTrue(entryPoint.contains("WindowGroup"), entryPoint)
    }

    func testTheShellOnlyWritesThroughTheInjectedWriter() {
        let model = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellModel.swift" }?.1 ?? ""
        let construction = "HostsFileApplier(fileURL: fileURL, writer: writer ?? Daemon" + "Client())"

        XCTAssertTrue(model.contains(construction), model)
    }
}

import Foundation
import HazmatAppSupport
import HazmatCore
import XCTest
@testable import HazmatApp

/// What the window takes for a name: a name with an interior space is a name,
/// and a name the store would refuse cannot be confirmed.
final class ShellNameEntryTests: XCTestCase {
    @MainActor
    func testTheFieldTakesASpaceInsideANameAndRefusesOneTheStoreWouldNotTake() async throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()

        model.beginCreate(.newProfile)
        XCTAssertFalse(model.nameDraftIsUsable, "an empty field is not a name")

        for refused in [" Local Dev", "Local Dev ", "Local/Dev", "Local..Dev"] {
            model.nameDraft = refused
            XCTAssertFalse(model.nameDraftIsUsable, refused)
        }

        model.nameDraft = "Local Dev"
        XCTAssertTrue(model.nameDraftIsUsable)

        model.commitNameEntry()
        await settle { model.editor.profiles.contains(ProfileID("Local Dev")) }

        XCTAssertNil(model.nameEntry, "the field closed")
        XCTAssertTrue(model.editor.profiles.contains(ProfileID("Local Dev")), "the profile was created")
    }

    @MainActor
    func testTheFieldIsNotUsableWhileNoNameIsAskedFor() throws {
        let world = try ShellWorld()
        defer { world.remove() }
        let model = world.model()

        XCTAssertFalse(model.nameDraftIsUsable)
    }
}

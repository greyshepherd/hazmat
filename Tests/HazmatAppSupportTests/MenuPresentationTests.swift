import Foundation
import HazmatCore
import XCTest
@testable import HazmatAppSupport

final class MenuPresentationTests: XCTestCase {
    private let work = ProfileID("work")
    private let ads = ProfileID("ads")

    private func derived(
        _ profiles: [ProfileID],
        _ state: ActiveProfileState,
        problems: [ProfileRenderProblem] = []
    ) -> ActiveProfileReading {
        .derived(profiles: profiles, activation: ActiveProfile(state: state, problems: problems))
    }

    private func section(_ menu: MenuPresentation, _ id: String) -> MenuPresentation.Section? {
        menu.sections.first { $0.id == id }
    }

    private func titles(_ menu: MenuPresentation, _ id: String) -> [String] {
        section(menu, id)?.items.map(\.title) ?? []
    }

    private func menuItem(_ menu: MenuPresentation, titled title: String) -> MenuPresentation.Item? {
        menu.sections.flatMap(\.items).first { $0.title == title }
    }

    private func actions(_ menu: MenuPresentation) -> [MenuPresentation.Action] {
        menu.sections.flatMap(\.items).compactMap(\.action)
    }

    /// Profile activations and overwrites: the items an empty or missing store suppresses.
    private func profileActions(_ menu: MenuPresentation) -> [MenuPresentation.Action] {
        actions(menu).filter { action in
            switch action {
            case .activate, .overwriteDrift: return true
            case .turnOff, .registerHelper, .checkForUpdates: return false
            }
        }
    }

    private func lines(_ menu: MenuPresentation) -> [String] {
        menu.sections.flatMap(\.items).filter { !$0.isSelectable }.map(\.title)
    }

    // MARK: - 4.2 The update check the bundle can offer

    func testTheUpdateCheckIsOfferedWhenTheBundleCanCheck() throws {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .enabled,
            notice: "",
            update: .available
        )

        XCTAssertEqual(titles(menu, "updates"), ["Check for Updates…"])
        XCTAssertEqual(try XCTUnwrap(menuItem(menu, titled: "Check for Updates…")).action, .checkForUpdates)
        XCTAssertTrue(lines(menu).filter { $0.contains("update") }.isEmpty, lines(menu).description)
    }

    func testTheUpdateCheckIsNotOfferedWhenTheBundleCannotCheck() {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .enabled,
            notice: ""
        )

        XCTAssertNil(section(menu, "updates"), menu.sections.map(\.id).description)
        XCTAssertFalse(actions(menu).contains(.checkForUpdates), actions(menu).description)
    }

    func testAFailedUpdateCheckIsReportedWithItsReason() {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .enabled,
            notice: "",
            update: .failed("the feed could not be reached")
        )

        XCTAssertTrue(
            lines(menu).contains { $0.contains("the feed could not be reached") },
            lines(menu).description
        )
        XCTAssertNotNil(menuItem(menu, titled: "Check for Updates…"), "a failed check must still be retryable")
    }

    // MARK: - 3.2 Items and labels for every state

    func testOneActiveProfileIsNamedMarkedAndActivatedByItsOwnItem() throws {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: work")
        XCTAssertEqual(titles(menu, "profiles"), ["work"])
        let workItem = try XCTUnwrap(menuItem(menu, titled: "work"))
        XCTAssertTrue(workItem.isMarked)
        XCTAssertEqual(workItem.action, .activate(work))
        XCTAssertNil(section(menu, "overwrite"))
        XCTAssertEqual(menuItem(menu, titled: "Turn Hazmat Off")?.action, .turnOff)
        XCTAssertNil(section(menu, "helper"), "an enabled helper needs no registration")
        XCTAssertTrue(lines(menu).contains(where: { $0.contains("Active: work") }), lines(menu).description)
    }

    func testSeveralMatchesAreAllNamedAndMarked() {
        let menu = MenuPresentation(
            reading: derived([ads, work], .active([ads, work])),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: ads, work")
        XCTAssertEqual(titles(menu, "profiles"), ["ads", "work"])
        XCTAssertEqual(
            section(menu, "profiles")?.items.map(\.isMarked),
            [true, true]
        )
    }

    func testNoBlockIsReportedAsOffWithUnmarkedProfiles() {
        let menu = MenuPresentation(
            reading: derived([work], .off),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: off")
        XCTAssertEqual(section(menu, "profiles")?.items.map(\.isMarked), [false])
        XCTAssertEqual(menuItem(menu, titled: "work")?.action, .activate(work))
        XCTAssertNil(section(menu, "overwrite"))
    }

    func testADriftedBlockReportsDriftAndOffersLabelledOverwrites() {
        let block = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        let menu = MenuPresentation(
            reading: derived([ads, work], .drifted(liveBlock: block)),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: drift")
        XCTAssertEqual(titles(menu, "profiles"), ["ads", "work"])
        XCTAssertEqual(titles(menu, "overwrite"), ["Overwrite drift with 'ads'", "Overwrite drift with 'work'"])
        XCTAssertEqual(
            menuItem(menu, titled: "Overwrite drift with 'work'")?.action,
            .overwriteDrift(work, liveBlock: block)
        )
        XCTAssertTrue(
            lines(menu).contains(where: { $0.contains("matches no profile") }),
            lines(menu).description
        )
    }

    func testAnUnreadableBlockIsReportedWithItsReason() {
        let menu = MenuPresentation(
            reading: derived([work], .unreadable(.multipleBlocks(firstLine: 1, secondLine: 3))),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: markers refused")
        XCTAssertTrue(
            lines(menu).contains(where: { $0.contains("more than one block") }),
            lines(menu).description
        )
        XCTAssertNil(section(menu, "overwrite"))
    }

    func testAMissingStoreSaysSoAndOffersNoActivation() {
        let menu = MenuPresentation(reading: .missingStore, helper: .enabled, notice: "")

        XCTAssertEqual(menu.statusTitle, "Hazmat: no store")
        XCTAssertTrue(lines(menu).contains(where: { $0.contains("No store") }), lines(menu).description)
        XCTAssertTrue(profileActions(menu).isEmpty, "\(profileActions(menu))")
        XCTAssertNil(section(menu, "profiles"))
        XCTAssertEqual(menuItem(menu, titled: "Turn Hazmat Off")?.action, .turnOff)
    }

    func testAnEmptyStoreSaysSoAndOffersNoActivation() {
        let menu = MenuPresentation(reading: .emptyStore, helper: .enabled, notice: "")

        XCTAssertEqual(menu.statusTitle, "Hazmat: no profiles")
        XCTAssertTrue(lines(menu).contains("The store holds no profiles."), lines(menu).description)
        XCTAssertTrue(profileActions(menu).isEmpty, "\(profileActions(menu))")
        XCTAssertNil(section(menu, "profiles"))
    }

    func testAnUnreadableFileIsReportedWithItsReasonInPlaceOfAProfile() {
        let menu = MenuPresentation(
            reading: .unreadableFile(profiles: [work], reason: "no such file"),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: unreadable")
        XCTAssertTrue(
            lines(menu).contains(where: { $0.contains("no such file") }),
            lines(menu).description
        )
    }

    func testANotRegisteredHelperIsReportedAndRegistrationOffered() {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .notRegistered,
            notice: ""
        )

        XCTAssertTrue(lines(menu).contains(HelperState.notRegistered.summary), lines(menu).description)
        XCTAssertEqual(titles(menu, "helper"), ["Register Helper"])
        XCTAssertEqual(menuItem(menu, titled: "Register Helper")?.action, .registerHelper)
    }

    func testAnAwaitingApprovalHelperIsReportedAndRegistrationOffered() {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .awaitingApproval,
            notice: ""
        )

        XCTAssertTrue(lines(menu).contains(HelperState.awaitingApproval.summary), lines(menu).description)
        XCTAssertEqual(titles(menu, "helper"), ["Register Helper"])
    }

    func testAProfileThatFailsToRenderIsReportedAndHasNoItem() {
        let broken = ProfileID("broken")
        let problem = ProfileRenderProblem(profile: broken, reason: "profile 'broken' line 1: fragment 'missing' is not in the store")
        let menu = MenuPresentation(
            reading: derived([broken, work], .active([work]), problems: [problem]),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menu.statusTitle, "Hazmat: work")
        XCTAssertTrue(
            lines(menu).contains(where: { $0.contains("could not be rendered") && $0.contains("missing") }),
            lines(menu).description
        )
        XCTAssertEqual(titles(menu, "profiles"), ["work"])
        XCTAssertNil(menuItem(menu, titled: "broken"))
    }

    func testTheLastOutcomeIsReportedInTheMenu() {
        let menu = MenuPresentation(
            reading: derived([work], .active([work])),
            helper: .enabled,
            notice: "applied: drift was overwritten"
        )

        XCTAssertTrue(lines(menu).contains("applied: drift was overwritten"), lines(menu).description)
    }

    // MARK: - 3.3 Overwrites are deliberate and labelled

    func testEveryOverwriteIsLabelledAndNamesTheProfileItWouldWrite() {
        let block = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        let menu = MenuPresentation(
            reading: derived([ads, work], .drifted(liveBlock: block)),
            helper: .enabled,
            notice: ""
        )

        let overwrites = menu.sections.flatMap(\.items).compactMap { item -> (String, ProfileID)? in
            guard case .overwriteDrift(let profile, _)? = item.action else { return nil }
            return (item.title, profile)
        }

        XCTAssertEqual(overwrites.count, 2)
        for (title, profile) in overwrites {
            XCTAssertTrue(title.contains("Overwrite"), title)
            XCTAssertTrue(title.contains("drift"), title)
            XCTAssertTrue(title.contains(profile.rawValue), title)
        }
    }

    /// The deliberate overwrite replaces exactly the block the derivation read:
    /// the block travels in the action rather than being located again.
    func testTheOverwriteCarriesTheBlockTheDerivationFound() {
        let block = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        let menu = MenuPresentation(
            reading: derived([ads, work], .drifted(liveBlock: block)),
            helper: .enabled,
            notice: ""
        )

        XCTAssertEqual(menuItem(menu, titled: "Overwrite drift with 'work'")?.action, .overwriteDrift(work, liveBlock: block))
        XCTAssertEqual(
            menuItem(menu, titled: "Overwrite drift with 'ads'")?.action,
            .overwriteDrift(ads, liveBlock: block)
        )
    }

    func testABareProfileNameIsASwitchAndNeverAnOverwrite() {
        let block = bytes("# >>> hazmat:managed v1 >>>\n10.1.2.3 stranger.example\n# <<< hazmat:managed v1 <<<\n")
        let menu = MenuPresentation(
            reading: derived([ads, work], .drifted(liveBlock: block)),
            helper: .enabled,
            notice: ""
        )

        let bare = section(menu, "profiles")?.items ?? []
        XCTAssertEqual(bare.map(\.title), ["ads", "work"])
        XCTAssertEqual(
            bare.compactMap(\.action),
            [.activate(ads), .activate(work)],
            "a profile name must switch, not overwrite"
        )
    }

    func testNoOverwriteIsOfferedWhenTheBlockMatchesAProfile() {
        let menu = MenuPresentation(
            reading: derived([ads, work], .active([work])),
            helper: .enabled,
            notice: ""
        )

        XCTAssertNil(section(menu, "overwrite"))
        XCTAssertTrue(actions(menu).allSatisfy { action in
            if case .overwriteDrift = action { return false }
            return true
        })
    }
}

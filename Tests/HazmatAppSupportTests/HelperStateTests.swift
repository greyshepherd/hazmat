import Foundation
import ServiceManagement
import XCTest
@testable import HazmatAppSupport

final class HelperStateTests: XCTestCase {
    func testEveryServiceStatusMapsToAStateTheAppCanActOn() {
        XCTAssertEqual(HelperState.state(for: .notRegistered), .notRegistered)
        XCTAssertEqual(HelperState.state(for: .requiresApproval), .awaitingApproval)
        XCTAssertEqual(HelperState.state(for: .enabled), .enabled)
        XCTAssertEqual(HelperState.state(for: .notFound), .notRegistered)
        XCTAssertEqual(HelperState.allCases.count, 4)
    }

    // MARK: - The check that separates approved from answering

    func testAnApprovedHelperThatDoesNotAnswerIsItsOwnState() {
        XCTAssertEqual(HelperState.enabled.refined(by: .answering), .enabled)
        XCTAssertEqual(HelperState.enabled.refined(by: .silent), .notAnswering)
        XCTAssertEqual(HelperState.enabled.refined(by: .refused(reason: "the helper is not running")), .notAnswering)
    }

    func testTheCheckOnlyRefinesAnApprovedHelper() {
        // A helper that is not registered or not yet approved keeps the
        // registration's own word: it is not a helper that failed to answer.
        for approval in [HelperState.notRegistered, .awaitingApproval] {
            XCTAssertEqual(approval.refined(by: .silent), approval)
            XCTAssertEqual(approval.refined(by: .refused(reason: "rejected")), approval)
        }
        XCTAssertEqual(HelperState.state(for: .enabled, reachability: .silent), .notAnswering)
        XCTAssertEqual(HelperState.state(for: .requiresApproval, reachability: .silent), .awaitingApproval)
    }

    func testTheStateThatDoesNotAnswerIsWordedAndOfferedTheRepair() {
        let state = HelperState.notAnswering

        XCTAssertEqual(state.label, "Helper not answering")
        XCTAssertEqual(state.symbolName, "bolt.slash")
        XCTAssertEqual(state.tone, .danger)
        XCTAssertFalse(state.canWrite, "a helper that did not answer cannot be written through")
        XCTAssertEqual(state.remedy, .repairHelper)
        XCTAssertEqual(WindowAction.repairHelper.title, "Repair the Helper…")
        XCTAssertTrue(state.summary.contains("did not answer"), state.summary)
        XCTAssertTrue(state.writeBlockCause.contains("did not answer"), state.writeBlockCause)
        XCTAssertTrue(state.writeBlockCause.contains("Repairing"), state.writeBlockCause)
        XCTAssertNotEqual(state.summary, HelperState.notRegistered.summary)
        XCTAssertNotEqual(state.summary, HelperState.enabled.summary)
    }

    /// The action that resolves the state is the one the window offers.
    func testTheRepairIsNotOfferedBeforeTheHelperIsRegisteredOrApproved() {
        XCTAssertEqual(HelperState.notRegistered.remedy, .installHelper)
        XCTAssertEqual(HelperState.awaitingApproval.remedy, .installHelper)
        XCTAssertEqual(HelperState.notAnswering.remedy, .repairHelper)
        XCTAssertNil(HelperState.enabled.remedy)
    }

    func testTheApprovalRequirementIsShownOnlyWhileAwaitingApproval() {
        XCTAssertTrue(HelperState.awaitingApproval.summary.contains("System Settings"))
        XCTAssertFalse(HelperState.enabled.summary.contains("System Settings"))
        XCTAssertFalse(HelperState.notRegistered.summary.contains("System Settings"))
        XCTAssertEqual(Set(HelperState.allCases.map(\.summary)).count, 4)
    }

    func testAWriteIsOnlyOfferedWhenTheHelperIsEnabled() {
        XCTAssertTrue(HelperState.enabled.canWrite)
        XCTAssertFalse(HelperState.awaitingApproval.canWrite)
        XCTAssertFalse(HelperState.notRegistered.canWrite)
        XCTAssertFalse(HelperState.notAnswering.canWrite)
    }

    func testTheShellShowsTheStateTheRegistrationAPIReports() {
        // Through the presentation: a glyph, a word and a tone, all derived
        // from what ServiceManagement reported.
        let sidebar = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "SidebarView.swift" }?.1 ?? ""
        XCTAssertFalse(sidebar.isEmpty, "the sidebar is missing")
        XCTAssertTrue(sidebar.contains("helper.symbolName"), sidebar)
        XCTAssertTrue(sidebar.contains("helper.label"), sidebar)
        XCTAssertTrue(sidebar.contains("helper.tone"), sidebar)
        XCTAssertTrue(sidebar.contains("helper.remedy"), sidebar)

        let model = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellModel.swift" }?.1 ?? ""
        XCTAssertTrue(model.contains("registration.state"), model)
        XCTAssertTrue(model.contains("HelperSheetPresentation(current: helper)"), model)
        // The registration alone is not the answer: what the window shows is the
        // registration refined by a check for the helper.
        XCTAssertTrue(model.contains(".refined(by:"), model)
        XCTAssertTrue(model.contains("checkPresence("), model)
        XCTAssertTrue(model.contains("presence.check()"), model)
        // The repair is the one sequence that removes and registers again, and it
        // is what the window reports the outcome of. Installing runs the same
        // sequence without the removal, because there is nothing to remove.
        XCTAssertTrue(model.contains("HelperRepair(registration: registration, presence: presence)"), model)
        XCTAssertTrue(model.contains("makeHelperAnswer("), model)
        XCTAssertTrue(model.contains("finishHelperWork("), model)
        // A write that did not go through is evidence the helper is not there, so
        // the shell checks after one rather than waiting for the next interval.
        XCTAssertTrue(model.contains("followUp(on: outcome)"), model)
        XCTAssertTrue(model.contains("checkPresence(forced: true)"), model)

        XCTAssertEqual(HelperState.notRegistered.label, "Helper not installed")
        XCTAssertEqual(HelperState.awaitingApproval.label, "Helper needs approval")
        XCTAssertEqual(HelperState.enabled.label, "Writes ready")
        XCTAssertEqual(HelperState.notAnswering.label, "Helper not answering")
    }

    func testTheHelperSheetNamesTheFourStatesAndTheActionsTheyNeed() {
        let sheet = HelperSheetPresentation(current: .notRegistered)

        XCTAssertEqual(sheet.states.map(\.state), [.notRegistered, .awaitingApproval, .enabled, .notAnswering])
        XCTAssertEqual(Set(sheet.states.map(\.detail)).count, 4)
        XCTAssertEqual(sheet.privileges.count, 3, "the three privileges the helper holds")
        for privilege in sheet.privileges {
            XCTAssertFalse(privilege.detail.isEmpty)
        }
        XCTAssertTrue(sheet.states.contains { $0.detail.contains("Login Items") }, "approval names where it is granted")
        XCTAssertTrue(
            sheet.states.contains { $0.state == .notAnswering && $0.detail.contains("Repairing") },
            "the state that does not answer names the repair"
        )
        XCTAssertEqual(sheet.current.remedy, .installHelper)
        XCTAssertNil(HelperState.enabled.remedy)
    }

    // MARK: - 5.2 Registration errors keep their cause

    func testRegistrationFailuresAreReportedWithTheirCause() {
        func failure(_ code: Int) -> RegistrationFailure {
            RegistrationFailure.classify(
                NSError(
                    domain: RegistrationFailure.serviceErrorDomain,
                    code: code,
                    userInfo: [NSLocalizedDescriptionKey: "reported by the system"]
                )
            )
        }

        XCTAssertEqual(failure(kSMErrorAlreadyRegistered), .alreadyRegistered)
        XCTAssertEqual(failure(kSMErrorLaunchDeniedByUser), .deniedByUser)
        XCTAssertEqual(failure(kSMErrorInvalidSignature), .invalidSignature)
        XCTAssertEqual(failure(kSMErrorJobNotFound), .jobNotFound)
        XCTAssertEqual(failure(kSMErrorJobPlistNotFound), .notPermitted("the launchd property list is not in the bundle"))
        XCTAssertEqual(failure(kSMErrorInvalidPlist), .notPermitted("the launchd property list is not valid"))
        XCTAssertEqual(failure(kSMErrorAuthorizationFailure), .notPermitted("authorization failed"))

        // Each cause is named rather than swallowed.
        XCTAssertEqual("\(failure(kSMErrorAlreadyRegistered))", "the helper is already registered")
        XCTAssertTrue("\(failure(kSMErrorLaunchDeniedByUser))".contains("denied"))
        XCTAssertTrue("\(failure(kSMErrorInvalidSignature))".contains("signature"))
    }

    func testAnErrorFromAnotherDomainIsStillReported() {
        let failure = RegistrationFailure.classify(
            NSError(domain: "com.example.other", code: 7, userInfo: [NSLocalizedDescriptionKey: "something else"])
        )

        guard case .other(let domain, let code, let message) = failure else {
            return XCTFail("expected the error to be carried through, got \(failure)")
        }
        XCTAssertEqual(domain, "com.example.other")
        XCTAssertEqual(code, 7)
        XCTAssertEqual(message, "something else")
        XCTAssertTrue("\(failure)".contains("com.example.other 7"))
        XCTAssertTrue("\(failure)".contains("something else"))
    }

    func testTheRegistrationWrapperNamesTheDaemonsPropertyList() throws {
        let registrationFile = sourceFiles(in: "Sources/HazmatAppSupport")
            .first { $0.0 == "HelperRegistration.swift" }?.1 ?? ""

        XCTAssertTrue(registrationFile.contains("HazmatIdentity.daemonPlistName"), registrationFile)
        XCTAssertTrue(registrationFile.contains("try service.register()"), registrationFile)
        XCTAssertTrue(registrationFile.contains("try service.unregister()"), registrationFile)
    }
}

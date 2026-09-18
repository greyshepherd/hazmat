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
        XCTAssertEqual(HelperState.allCases.count, 3)
    }

    func testTheApprovalRequirementIsShownOnlyWhileAwaitingApproval() {
        XCTAssertTrue(HelperState.awaitingApproval.summary.contains("System Settings"))
        XCTAssertFalse(HelperState.enabled.summary.contains("System Settings"))
        XCTAssertFalse(HelperState.notRegistered.summary.contains("System Settings"))
        XCTAssertEqual(Set(HelperState.allCases.map(\.summary)).count, 3)
    }

    func testAWriteIsOnlyOfferedWhenTheHelperIsEnabled() {
        XCTAssertTrue(HelperState.enabled.canWrite)
        XCTAssertFalse(HelperState.awaitingApproval.canWrite)
        XCTAssertFalse(HelperState.notRegistered.canWrite)
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

        XCTAssertEqual(HelperState.notRegistered.label, "Helper not installed")
        XCTAssertEqual(HelperState.awaitingApproval.label, "Helper needs approval")
        XCTAssertEqual(HelperState.enabled.label, "Writes ready")
    }

    func testTheHelperSheetNamesTheThreeStatesAndTheActionsTheyNeed() {
        let sheet = HelperSheetPresentation(current: .notRegistered)

        XCTAssertEqual(sheet.states.map(\.state), [.notRegistered, .awaitingApproval, .enabled])
        XCTAssertEqual(Set(sheet.states.map(\.detail)).count, 3)
        XCTAssertEqual(sheet.privileges.count, 3, "the three privileges the helper holds")
        for privilege in sheet.privileges {
            XCTAssertFalse(privilege.detail.isEmpty)
        }
        XCTAssertTrue(sheet.states.contains { $0.detail.contains("Login Items") }, "approval names where it is granted")
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

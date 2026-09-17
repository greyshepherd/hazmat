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
        let view = sourceFiles(in: "Sources/HazmatApp").first { $0.0 == "ShellView.swift" }?.1 ?? ""

        XCTAssertFalse(view.isEmpty)
        XCTAssertTrue(view.contains("model.helper.summary"), view)
        XCTAssertTrue(view.contains("model.helper != .enabled"), view)
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

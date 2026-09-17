import Foundation
import HazmatProtocol
import ServiceManagement

/// Why registration failed, with the cause ServiceManagement reported.
public enum RegistrationFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case alreadyRegistered
    case deniedByUser
    case invalidSignature
    case jobNotFound
    case notPermitted(String)
    case other(domain: String, code: Int, message: String)

    /// The domain ServiceManagement reports registration problems in.
    public static var serviceErrorDomain: String { SMAppServiceErrorDomain }

    public var description: String {
        switch self {
        case .alreadyRegistered:
            return "the helper is already registered"
        case .deniedByUser:
            return "an administrator denied the helper"
        case .invalidSignature:
            return "the app bundle's signature is not accepted"
        case .jobNotFound:
            return "the helper is not registered"
        case .notPermitted(let detail):
            return "the system refused the helper: \(detail)"
        case .other(let domain, let code, let message):
            return "registration failed (\(domain) \(code)): \(message)"
        }
    }

    /// Reads what ServiceManagement reported rather than swallowing it.
    public static func classify(_ error: Error) -> RegistrationFailure {
        let error = error as NSError
        guard error.domain == SMAppServiceErrorDomain else {
            return .other(domain: error.domain, code: error.code, message: error.localizedDescription)
        }
        switch error.code {
        case kSMErrorAlreadyRegistered:
            return .alreadyRegistered
        case kSMErrorLaunchDeniedByUser:
            return .deniedByUser
        case kSMErrorInvalidSignature:
            return .invalidSignature
        case kSMErrorJobNotFound:
            return .jobNotFound
        case kSMErrorAuthorizationFailure:
            return .notPermitted("authorization failed")
        case kSMErrorToolNotValid:
            return .notPermitted("the daemon executable is not valid")
        case kSMErrorJobPlistNotFound:
            return .notPermitted("the launchd property list is not in the bundle")
        case kSMErrorInvalidPlist:
            return .notPermitted("the launchd property list is not valid")
        default:
            return .other(domain: error.domain, code: error.code, message: error.localizedDescription)
        }
    }
}

/// Registration and unregistration of the daemon that lives in this bundle.
public struct HelperRegistration: Sendable {
    public let plistName: String

    public init(plistName: String = HazmatIdentity.daemonPlistName) {
        self.plistName = plistName
    }

    public var state: HelperState {
        HelperState.state(for: service.status)
    }

    public func register() throws {
        do {
            try service.register()
        } catch {
            throw RegistrationFailure.classify(error)
        }
    }

    public func unregister() throws {
        do {
            try service.unregister()
        } catch {
            throw RegistrationFailure.classify(error)
        }
    }

    private var service: SMAppService {
        SMAppService.daemon(plistName: plistName)
    }
}

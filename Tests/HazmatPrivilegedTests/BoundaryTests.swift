import Foundation
import HazmatProtocol
import Security
import XCTest
@testable import HazmatPrivileged

final class BoundaryTests: XCTestCase {
    // MARK: - 4.1 The interface is baseline digest plus bytes in, status out

    func testTheInterfaceCarriesNoTargetPathAndNoProfile() throws {
        // A protocol declared in Swift is registered under its module-qualified
        // name, and instantiating the interface is what makes the runtime hold it.
        _ = NSXPCInterface(with: HazmatDaemonXPC.self)
        let protocolObject: Protocol = try XCTUnwrap(objc_getProtocol("HazmatProtocol.HazmatDaemonXPC"))

        var methodCount: UInt32 = 0
        let methods = try XCTUnwrap(protocol_copyMethodDescriptionList(protocolObject, true, true, &methodCount))
        defer { free(methods) }
        XCTAssertEqual(methodCount, 3)

        var encodings: [String: String] = [:]
        for index in 0..<Int(methodCount) {
            let description = methods[index]
            let selector = NSStringFromSelector(try XCTUnwrap(description.name))
            encodings[selector] = String(cString: try XCTUnwrap(description.types))
            for forbidden in ["path", "profile", "url", "location", "destination", "target"] {
                XCTAssertFalse(selector.lowercased().contains(forbidden), "\(selector) names a \(forbidden)")
            }
        }

        XCTAssertEqual(
            Set(encodings.keys),
            ["writeFileBytes:baselineDigest:withReply:", "removeManagedBlock:withReply:", "checkInWithReply:"]
        )
        // void return, self, _cmd, then the parameters. The write carries exactly
        // two objects - the bytes and the state they were planned from - and the
        // removal exactly one; both reply with a block. The check carries no
        // request at all: it is answered by the daemon being there to answer it.
        // A parameter that named a path or a profile would have to appear here.
        XCTAssertEqual(argumentTypes(of: encodings["writeFileBytes:baselineDigest:withReply:"]), ["v", "@", ":", "@", "@", "@?"])
        XCTAssertEqual(argumentTypes(of: encodings["removeManagedBlock:withReply:"]), ["v", "@", ":", "@", "@?"])
        XCTAssertEqual(argumentTypes(of: encodings["checkInWithReply:"]), ["v", "@", ":", "@?"])
    }

    func testTheCheckAnswersAndTouchesNothing() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let live = appliedHosts()
        try directory.write(live)

        let service = DaemonService(
            handler: DaemonWriteHandler(
                service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
            )
        )

        var answered = false
        service.checkIn { answered = true }

        XCTAssertTrue(answered, "the check is answered by the daemon being there")
        XCTAssertEqualBytes(try directory.contents(), live)
    }

    func testTheStatusesAreSharedByBothSides() {
        XCTAssertEqual(HazmatWriteStatus.written.rawValue, 0)
        XCTAssertEqual(HazmatWriteStatus.refused.rawValue, 1)
        XCTAssertEqual(HazmatWriteStatus.failed.rawValue, 2)
    }

    // MARK: - 4.2 One fixed target

    func testTheDaemonsTargetIsTheHostsFileAndNothingElse() throws {
        let hostsFile = "/etc" + "/hosts"
        XCTAssertEqual(HazmatIdentity.hostsFilePath, hostsFile)
        XCTAssertEqual(DaemonTarget.hostsFile.path, hostsFile)

        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let live = appliedHosts()
        try directory.write(live)

        let handler = DaemonWriteHandler(
            service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
        )
        let planned = bytes(text(live).replacingOccurrences(of: "::1 api.internal", with: "::1 api.changed"))

        let (status, reason) = handler.write(bytes: planned, baselineDigest: BaselineDigest.of(live))

        XCTAssertEqual(status, HazmatWriteStatus.written.rawValue)
        XCTAssertNil(reason)
        XCTAssertEqualBytes(try directory.contents(), planned)
        XCTAssertEqual(try directory.entries(), ["hosts"], "a request touched something else")
    }

    func testARefusalIsReportedWithItsReason() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let live = appliedHosts()
        try directory.write(live)
        let handler = DaemonWriteHandler(
            service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
        )

        let (status, reason) = handler.write(bytes: bytes("no block here\n"), baselineDigest: BaselineDigest.of(live))
        XCTAssertEqual(status, HazmatWriteStatus.refused.rawValue)
        XCTAssertEqual(reason, WriteRefusal.noBlock.description)

        let (staleStatus, staleReason) = handler.write(bytes: live, baselineDigest: BaselineDigest.of(bytes("other")))
        XCTAssertEqual(staleStatus, HazmatWriteStatus.refused.rawValue)
        XCTAssertEqual(staleReason, WriteRefusal.baselineMismatch.description)

        let (removeStatus, _) = handler.remove(baselineDigest: BaselineDigest.of(live))
        XCTAssertEqual(removeStatus, HazmatWriteStatus.written.rawValue)
        XCTAssertFalse(text(try directory.contents()).contains("hazmat:managed"))
    }

    // MARK: - 4.3 The caller's code signature

    func testTheDevelopmentRequirementNamesTheIdentifierOnly() {
        let requirement = SignatureVerifier.development(appIdentifier: "com.greyshepherd.hazmat")

        XCTAssertEqual(requirement.requirement, "identifier \"com.greyshepherd.hazmat\"")
        XCTAssertFalse(requirement.requirement.contains("anchor apple"))
        XCTAssertFalse(requirement.requirement.contains("certificate"))
    }

    func testTheShippingRequirementAnchorsTeamAndIdentifier() {
        let requirement = SignatureVerifier.shipping(appIdentifier: "com.greyshepherd.hazmat", teamIdentifier: "ABCDE12345")

        XCTAssertTrue(requirement.requirement.contains("identifier \"com.greyshepherd.hazmat\""))
        XCTAssertTrue(requirement.requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.requirement.contains("certificate leaf[subject.OU] = \"ABCDE12345\""))
    }

    /// The rule the daemon applies is the one its own signature implies, so it
    /// cannot disagree with how the daemon was built.
    func testTheRequirementFollowsTheDaemonsOwnSignature() {
        let requirement = SignatureVerifier.forOwnBundle()

        XCTAssertTrue(
            requirement.requirement.hasPrefix("identifier \"com.greyshepherd.hazmat\""),
            requirement.requirement
        )
        // This test bundle carries no team, so there is nothing to anchor; a
        // distribution build gets the anchored form, which is checked by signing
        // one and asking it.
        XCTAssertFalse(requirement.requirement.contains("anchor apple"), requirement.requirement)
        XCTAssertEqual(requirement.requirement, SignatureVerifier.development(appIdentifier: "com.greyshepherd.hazmat").requirement)
    }

    func testATeamAnchoredRequirementRefusesAClientWithoutThatTeam() throws {
        var selfCode: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &selfCode), errSecSuccess)
        let code = try XCTUnwrap(selfCode)
        let ownIdentifier = try signingIdentifier(of: code)

        // The process being checked is this one, which was not signed by the team
        // the daemon would name: an ad-hoc build of the same identifier is exactly
        // the client a distribution daemon must refuse.
        let anchored = SignatureVerifier.shipping(appIdentifier: ownIdentifier, teamIdentifier: "ABCDE12345")
        XCTAssertFalse(anchored.accepts(code: code))
    }

    func testAClientThatDoesNotSatisfyTheRequirementIsRefused() throws {
        var selfCode: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &selfCode), errSecSuccess)
        let code = try XCTUnwrap(selfCode)
        let ownIdentifier = try signingIdentifier(of: code)

        XCTAssertTrue(SignatureVerifier.development(appIdentifier: ownIdentifier).accepts(code: code))
        XCTAssertFalse(
            SignatureVerifier.development(appIdentifier: "com.greyshepherd.somebody.else").accepts(code: code)
        )
        XCTAssertFalse(SignatureVerifier(requirement: "not a requirement at all").accepts(code: code))
    }

    func testAnUnreadableRequirementRefusesTheConnectionRatherThanRaising() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try directory.write(appliedHosts())
        let handler = DaemonWriteHandler(
            service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
        )

        XCTAssertThrowsError(try SignatureVerifier(requirement: "not a requirement at all").readableRequirement())

        let listener = NSXPCListener.anonymous()
        let delegate = DaemonListenerDelegate(
            handler: handler,
            verifier: SignatureVerifier(requirement: "not a requirement at all")
        )
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        XCTAssertFalse(delegate.listener(listener, shouldAcceptNewConnection: connection))
        XCTAssertNil(connection.exportedObject, "a connection with no readable requirement must not be given the handler")
    }

    /// The requirement is put on the connection, and the system checks the
    /// sender of every message against it, so the refusal is seen by the client
    /// as a message that is never answered rather than by the delegate as a
    /// decision at accept time. Both directions are exercised through a real
    /// listener: this process satisfies its own identifier and no other.
    func testAProcessThatDoesNotSatisfyTheRequirementNeverReachesTheHandler() throws {
        var selfCode: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &selfCode), errSecSuccess)
        let ownIdentifier = try signingIdentifier(of: try XCTUnwrap(selfCode))

        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let live = appliedHosts()
        try directory.write(live)
        let handler = DaemonWriteHandler(
            service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
        )

        // The listener holds its delegate weakly, so each is kept for its exchange.
        let rejecting = DaemonListenerDelegate(
            handler: handler,
            verifier: SignatureVerifier.development(appIdentifier: "com.greyshepherd.somebody.else")
        )
        let refused = try answer(to: rejecting)
        XCTAssertEqual(refused, .unanswered, "a client that does not satisfy the requirement must not be answered")
        XCTAssertEqualBytes(try directory.contents(), live, "the file changed for a refused client")

        let accepting = DaemonListenerDelegate(
            handler: handler,
            verifier: SignatureVerifier.development(appIdentifier: ownIdentifier)
        )
        let accepted = try answer(to: accepting)
        XCTAssertEqual(accepted, .answered, "a client that satisfies the requirement is answered")
        XCTAssertEqualBytes(try directory.contents(), live, "accepting a connection must write nothing")
    }

    private enum CheckAnswer: Equatable {
        case answered
        case unanswered
    }

    /// Sends one check through a listener the delegate serves, and reports
    /// whether it was answered before the connection failed or the bound ran out.
    private func answer(to delegate: DaemonListenerDelegate) throws -> CheckAnswer {
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: HazmatDaemonXPC.self)
        let outcome = FirstAnswer()
        let done = expectation(description: "the check is answered or the connection fails")
        connection.invalidationHandler = { if outcome.record(.unanswered) { done.fulfill() } }
        connection.interruptionHandler = { if outcome.record(.unanswered) { done.fulfill() } }
        connection.resume()
        defer { connection.invalidate() }

        let proxy = try XCTUnwrap(
            connection.remoteObjectProxyWithErrorHandler { _ in
                if outcome.record(.unanswered) { done.fulfill() }
            } as? HazmatDaemonXPC
        )
        proxy.checkIn { if outcome.record(.answered) { done.fulfill() } }

        wait(for: [done], timeout: 5)
        return outcome.value ?? .unanswered
    }

    /// First answer wins: the reply, the error handler and the invalidation
    /// handler can each arrive on their own thread.
    private final class FirstAnswer: @unchecked Sendable {
        private let lock = NSLock()
        private var answer: CheckAnswer?

        func record(_ value: CheckAnswer) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard answer == nil else { return false }
            answer = value
            return true
        }

        var value: CheckAnswer? {
            lock.lock()
            defer { lock.unlock() }
            return answer
        }
    }

    /// The listener hands connection open and close to the idle rule, so a daemon
    /// with nothing to serve stops and the build on disk serves the next request.
    func testTheListenerKeepsTheDaemonAliveOnlyWhileAClientIsConnected() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        try directory.write(appliedHosts())
        let handler = DaemonWriteHandler(
            service: PrivilegedWriteService(target: directory.target, owner: testOwnership())
        )

        let stoppedWhileConnected = expectation(description: "the rule must not fire while a client is connected")
        stoppedWhileConnected.isInverted = true
        let stoppedWhenIdle = expectation(description: "the rule fires once the client is gone")
        let phase = ConnectionPhase()
        let idle = IdleExit(after: .milliseconds(100)) {
            if phase.isConnected {
                stoppedWhileConnected.fulfill()
            } else {
                stoppedWhenIdle.fulfill()
            }
        }
        let delegate = DaemonListenerDelegate(
            handler: handler,
            verifier: OwnIdentifier(),
            idleExit: idle
        )
        let listener = NSXPCListener.anonymous()
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)

        XCTAssertTrue(delegate.listener(listener, shouldAcceptNewConnection: connection))
        wait(for: [stoppedWhileConnected], timeout: 0.3)

        phase.disconnect()
        connection.invalidate()
        wait(for: [stoppedWhenIdle], timeout: 3)
    }

    // MARK: - 4.4 No shell, no external program

    func testTheWritePathRunsNoExternalProgram() {
        let forbidden = ["Process(", "NSTask", "posix_spawn", "popen(", "system(", "execv", "execl", "fork("]

        for (file, source) in sourceFiles(in: "Sources/HazmatPrivileged") + sourceFiles(in: "Sources/HazmatDaemon") {
            for needle in forbidden {
                XCTAssertNil(source.range(of: needle), "\(file) uses \(needle)")
            }
        }
    }

    private func signingIdentifier(of code: SecCode) throws -> String {
        var staticCode: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(code, [], &staticCode), errSecSuccess)
        var information: CFDictionary?
        let status = SecCodeCopySigningInformation(
            try XCTUnwrap(staticCode),
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        )
        XCTAssertEqual(status, errSecSuccess)
        let dictionary = try XCTUnwrap(information as? [String: Any])
        return try XCTUnwrap(dictionary[kSecCodeInfoIdentifier as String] as? String)
    }
}

/// The seam the listener is tested through: the requirement this process
/// satisfies, so a connection from it is served.
private struct OwnIdentifier: ConnectionVerifying {
    func readableRequirement() throws -> String {
        var selfCode: SecCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode else {
            throw SignatureError.requirementUnreadable("own code")
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(selfCode, [], &staticCode) == errSecSuccess, let staticCode else {
            throw SignatureError.requirementUnreadable("own static code")
        }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let identifier = dictionary[kSecCodeInfoIdentifier as String] as? String
        else {
            throw SignatureError.requirementUnreadable("own identifier")
        }
        return try SignatureVerifier.development(appIdentifier: identifier).readableRequirement()
    }
}

/// The argument types of an Objective-C encoding, with the byte offsets the
/// compiler writes between them removed.
func argumentTypes(of encoding: String?) -> [String] {
    guard let encoding else { return [] }
    let qualifiers: Set<Character> = ["r", "n", "o", "O", "R", "V"]
    var types: [String] = []
    var index = encoding.startIndex

    while index < encoding.endIndex {
        let character = encoding[index]
        if character.isNumber || qualifiers.contains(character) {
            index = encoding.index(after: index)
            continue
        }
        if character == "@", encoding.index(after: index) < encoding.endIndex, encoding[encoding.index(after: index)] == "?" {
            types.append("@?")
            index = encoding.index(after: encoding.index(after: index))
            continue
        }
        types.append(String(character))
        index = encoding.index(after: index)
    }
    return types
}

/// Which phase a test's idle rule is in.
private final class ConnectionPhase: @unchecked Sendable {
    private let lock = NSLock()
    private var connected = true

    var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return connected
    }

    func disconnect() {
        lock.lock()
        defer { lock.unlock() }
        connected = false
    }
}

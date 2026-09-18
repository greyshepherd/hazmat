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

        let listener = NSXPCListener.anonymous()

        let rejecting = DaemonListenerDelegate(
            handler: handler,
            verifier: SignatureVerifier.development(appIdentifier: "com.greyshepherd.somebody.else")
        )
        let refusedConnection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        XCTAssertFalse(rejecting.listener(listener, shouldAcceptNewConnection: refusedConnection))
        XCTAssertNil(refusedConnection.exportedObject, "a refused client must not be given the handler")
        XCTAssertEqualBytes(try directory.contents(), live, "the file changed for a refused client")

        // The daemon identifies the client by the process behind the connection.
        XCTAssertFalse(
            SignatureVerifier.development(appIdentifier: "com.greyshepherd.somebody.else").accepts(processIdentifier: getpid())
        )
        XCTAssertTrue(SignatureVerifier.development(appIdentifier: ownIdentifier).accepts(processIdentifier: getpid()))

        // A connection that satisfies the requirement gets the handler exported.
        let accepting = DaemonListenerDelegate(handler: handler, verifier: AlwaysAccepts())
        let acceptedConnection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        XCTAssertTrue(accepting.listener(listener, shouldAcceptNewConnection: acceptedConnection))
        XCTAssertNotNil(acceptedConnection.exportedInterface)
        XCTAssertNotNil(acceptedConnection.exportedObject)
        XCTAssertEqualBytes(try directory.contents(), live, "accepting a connection must write nothing")
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

/// The seam the listener is tested through: a connection's process identity is
/// supplied by the transport, so the decision can be exercised without one.
private struct AlwaysAccepts: ConnectionVerifying {
    func accepts(processIdentifier: pid_t) -> Bool { true }
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

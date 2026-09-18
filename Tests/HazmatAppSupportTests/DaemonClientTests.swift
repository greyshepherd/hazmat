import Foundation
import HazmatAppSupport
import HazmatProtocol
import XCTest
@testable import HazmatAppSupport

/// What a check for the helper makes of a service that answers, one that never
/// answers, and one that refuses the connection. Each service is a listener this
/// test holds, so the whole privileged boundary is exercised in this process: no
/// daemon, no root, and no hosts file.
final class DaemonClientTests: XCTestCase {
    private var listeners: [NSXPCListener] = []

    override func tearDown() {
        for listener in listeners { listener.invalidate() }
        listeners = []
        super.tearDown()
    }

    /// A service that answers a check.
    private final class AnsweringDaemon: NSObject, HazmatDaemonXPC {
        private(set) var checks = 0
        private(set) var writes = 0

        func checkIn(withReply reply: @escaping () -> Void) {
            checks += 1
            reply()
        }

        func writeFileBytes(_ bytes: Data, baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
            writes += 1
            reply(HazmatWriteStatus.written.rawValue, nil)
        }

        func removeManagedBlock(_ baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
            reply(HazmatWriteStatus.written.rawValue, nil)
        }
    }

    /// A service that takes the connection and then says nothing, which is what a
    /// helper the system can no longer start looks like from the client's side.
    private final class MuteDaemon: NSObject, HazmatDaemonXPC {
        func checkIn(withReply reply: @escaping () -> Void) {
        }

        func writeFileBytes(_ bytes: Data, baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        }

        func removeManagedBlock(_ baselineDigest: Data, withReply reply: @escaping (Int32, String?) -> Void) {
        }
    }

    private final class Exporter: NSObject, NSXPCListenerDelegate {
        private let object: HazmatDaemonXPC
        private let accepts: Bool

        init(_ object: HazmatDaemonXPC, accepts: Bool = true) {
            self.object = object
            self.accepts = accepts
        }

        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            guard accepts else { return false }
            connection.exportedInterface = NSXPCInterface(with: HazmatDaemonXPC.self)
            connection.exportedObject = object
            connection.resume()
            return true
        }
    }

    /// An endpoint is the only way to reach a listener the process holds, so it
    /// is carried to the client's connection factory. A listener keeps its
    /// delegate weakly, so the delegate is held here.
    private final class Endpoint: @unchecked Sendable {
        let listener: NSXPCListener
        private let delegate: NSXPCListenerDelegate

        init(_ delegate: NSXPCListenerDelegate) {
            self.delegate = delegate
            listener = NSXPCListener.anonymous()
            listener.delegate = delegate
            listener.resume()
        }
    }

    private func client(
        _ object: HazmatDaemonXPC,
        accepts: Bool = true,
        writeBoundSeconds: Int = 2,
        presenceBoundSeconds: Int = 2
    ) -> (DaemonClient, Endpoint) {
        let endpoint = Endpoint(Exporter(object, accepts: accepts))
        listeners.append(endpoint.listener)
        let client = DaemonClient(
            connectionFor: { NSXPCConnection(listenerEndpoint: endpoint.listener.endpoint) },
            writeBoundSeconds: writeBoundSeconds,
            presenceBoundSeconds: presenceBoundSeconds
        )
        return (client, endpoint)
    }

    func testAServiceThatAnswersIsReportedAsAnswering() {
        let daemon = AnsweringDaemon()
        let (client, _) = client(daemon)

        XCTAssertEqual(client.check(), .answering)
        XCTAssertEqual(daemon.checks, 1, "the check is the one call the helper is asked")
    }

    func testAServiceThatSaysNothingIsReportedAsSilent() {
        let (client, _) = client(MuteDaemon(), presenceBoundSeconds: 1)
        let start = Date()

        XCTAssertEqual(client.check(), .silent)

        let waited = Date().timeIntervalSince(start)
        XCTAssertGreaterThanOrEqual(waited, 1, "silence is concluded when the bound is reached, not before")
        XCTAssertLessThan(waited, 3, "silence is bounded")
    }

    func testAServiceThatRefusesTheConnectionIsReportedWithItsReason() {
        let (client, _) = client(AnsweringDaemon(), accepts: false)

        guard case .refused(let reason) = client.check() else {
            return XCTFail("a refused connection is not silence")
        }
        XCTAssertFalse(reason.isEmpty)
    }

    func testAWriteThatNothingAnswersFailsWithinItsBoundAndNamesTheRepair() {
        let (client, _) = client(MuteDaemon(), writeBoundSeconds: 1)
        let start = Date()

        let result = client.write(bytes: Data("127.0.0.1 localhost\n".utf8), baseline: Data("shipped\n".utf8))

        XCTAssertLessThan(Date().timeIntervalSince(start), 4, "a write must not wait without an outcome")
        guard case .failed(let reason) = result else {
            return XCTFail("expected a failure, got \(result)")
        }
        XCTAssertTrue(reason.contains("did not answer"), reason)
        XCTAssertTrue(reason.contains("Repair the helper"), reason)
    }

    func testAWriteThatIsAnsweredIsReportedAsWritten() {
        let daemon = AnsweringDaemon()
        let (client, _) = client(daemon)

        XCTAssertEqual(client.write(bytes: Data("bytes".utf8), baseline: Data("shipped\n".utf8)), .written)
        XCTAssertEqual(daemon.writes, 1)
    }

    /// The bound the app documents is the one it words its failure with.
    func testTheDocumentedBoundsAreTheOnesTheAppUses() {
        XCTAssertEqual(DaemonClient.writeBoundSeconds, 10)
        XCTAssertEqual(DaemonClient.presenceBoundSeconds, 3)
    }
}

/// The retry around a request: the daemon stops when it has nothing to serve, so
/// the moment a request lands as it stops must not read as a failure — and a
/// helper that was given its whole bound and said nothing must not be asked
/// twice, because the report has to arrive inside that bound.
extension DaemonClientTests {
    func testARequestIsMadeAgainWhenTheConnectionDiedBeforeAnAnswer() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return attempts == 1 ? .noReply(reason: "the helper is not running") : .answer(.written)
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(outcome, .answer(.written))
    }

    func testAnAnswerIsNeverRepeated() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return .answer(.refused(reason: "drift"))
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcome, .answer(.refused(reason: "drift")))
    }

    func testABoundThatWasReachedIsAnAnswerAndNotAnotherRequest() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return .answer(.failed(reason: "the helper did not answer within 10 seconds"))
        }

        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(outcome.result, .failed(reason: "the helper did not answer within 10 seconds"))
    }

    func testAFailureThatRepeatsReportsTheReasonItStartedWith() {
        var attempts = 0
        let outcome = attemptedTwice {
            attempts += 1
            return .noReply(reason: "the helper is not running")
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(outcome.result, .failed(reason: "the helper is not running"))
    }
}

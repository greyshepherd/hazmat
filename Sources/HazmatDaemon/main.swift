import Foundation
import HazmatCore
import HazmatPrivileged
import HazmatProtocol
import os

// The daemon serves one mach service and can affect one path. The target is
// built here from a constant; nothing a client sends can name another.

let logger = Logger(subsystem: HazmatIdentity.bundleIdentifier, category: "daemon")

/// Nothing else keeps the daemon running, so a replaced build cannot serve the
/// next request; launchd starts the installed one on demand.
let idlePeriod = DispatchTimeInterval.seconds(30)

let service = PrivilegedWriteService(target: DaemonTarget.hostsFile)
let delegate = DaemonListenerDelegate(
    handler: DaemonWriteHandler(service: service),
    verifier: SignatureVerifier.forOwnBundle(),
    idleExit: IdleExit(after: idlePeriod) { exit(EXIT_SUCCESS) },
    logger: logger
)

let listener = NSXPCListener(machServiceName: HazmatIdentity.machServiceName)
listener.delegate = delegate
listener.resume()

logger.notice(
    "HazmatDaemon serving \(HazmatIdentity.machServiceName, privacy: .public) for \(HazmatIdentity.hostsFilePath, privacy: .public); block version \(ManagedBlock.version), write bound \(PlannedBytes.sizeBound) bytes, stopping after 30s idle"
)

RunLoop.current.run()

import Foundation
import HazmatCore
import HazmatPrivileged
import HazmatProtocol
import os

// The daemon serves one mach service and can affect one path. The target is
// built here from a constant; nothing a client sends can name another.

let logger = Logger(subsystem: HazmatIdentity.bundleIdentifier, category: "daemon")

let service = PrivilegedWriteService(target: DaemonTarget.hostsFile)
let delegate = DaemonListenerDelegate(
    handler: DaemonWriteHandler(service: service),
    verifier: SignatureVerifier.development(appIdentifier: HazmatIdentity.bundleIdentifier),
    logger: logger
)

let listener = NSXPCListener(machServiceName: HazmatIdentity.machServiceName)
listener.delegate = delegate
listener.resume()

logger.notice(
    "HazmatDaemon serving \(HazmatIdentity.machServiceName, privacy: .public) for \(HazmatIdentity.hostsFilePath, privacy: .public); block version \(ManagedBlock.version), write bound \(PlannedBytes.sizeBound) bytes"
)

RunLoop.current.run()

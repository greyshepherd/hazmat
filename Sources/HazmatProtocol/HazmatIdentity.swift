import CryptoKit
import Foundation

/// The names the bundle, the app, and the daemon agree on. The bundle script
/// writes the same values into the property lists it assembles.
public enum HazmatIdentity {
    public static let bundleIdentifier = "com.greyshepherd.hazmat"
    public static let daemonLabel = "com.greyshepherd.hazmat.daemon"
    public static let machServiceName = "com.greyshepherd.hazmat.daemon"
    public static let daemonPlistName = "com.greyshepherd.hazmat.daemon.plist"
    public static let daemonExecutableName = "HazmatDaemon"
    public static let appExecutableName = "HazmatApp"
    /// The one path the privileged side can affect.
    public static let hostsFilePath = "/etc/hosts"
}

/// The one digest both sides compute, so a request can carry the state its plan
/// was based on without carrying the file.
public enum BaselineDigest {
    public static func of(_ bytes: Data) -> Data {
        Data(SHA256.hash(data: bytes))
    }
}

/// The status a write request comes back with.
public enum HazmatWriteStatus: Int32, Sendable {
    case written = 0
    case refused = 1
    case failed = 2
}

/// The privileged interface. A request carries finished bytes and the state the
/// plan was based on; it never carries a target path, a profile, or a fragment.
/// Removal carries no bytes: the privileged side strips the block itself.
@objc public protocol HazmatDaemonXPC {
    /// Whether the daemon is there. Carries no request and answers nothing but
    /// its own arrival, which is what separates a registered helper from one
    /// that answers. A daemon the system can no longer start never replies, so
    /// the client's own bound is what reports it.
    func checkIn(withReply reply: @escaping () -> Void)

    func writeFileBytes(
        _ bytes: Data,
        baselineDigest: Data,
        withReply reply: @escaping (Int32, String?) -> Void
    )

    func removeManagedBlock(
        _ baselineDigest: Data,
        withReply reply: @escaping (Int32, String?) -> Void
    )
}

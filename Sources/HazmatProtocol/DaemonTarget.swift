import Foundation

/// The one path the daemon can affect is built here and never taken from a
/// request or the environment.
public enum DaemonTarget {
    public static var hostsFile: URL {
        URL(fileURLWithPath: HazmatIdentity.hostsFilePath)
    }
}

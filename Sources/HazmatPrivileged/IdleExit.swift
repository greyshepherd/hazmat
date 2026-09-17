import Foundation

/// How long the daemon stays alive with nothing to serve. A build that has been
/// replaced on disk should not keep answering requests, so a process with no open
/// connection for this long stops, and launchd starts the installed build on the
/// next message. A client with no answer retries once, which covers the moment a
/// request arrives as the process is going away.
public final class IdleExit: @unchecked Sendable {
    private let queue: DispatchQueue
    private let after: DispatchTimeInterval
    private let stop: @Sendable () -> Void
    private var timer: DispatchSourceTimer?
    private var openConnections = 0

    public init(after: DispatchTimeInterval, stop: @escaping @Sendable () -> Void) {
        self.after = after
        self.stop = stop
        self.queue = DispatchQueue(label: "com.greyshepherd.hazmat.idle-exit")
    }

    /// A connection arrived: the daemon has something to serve, so it stays.
    public func connectionOpened() {
        queue.async { [self] in
            openConnections += 1
            timer?.cancel()
            timer = nil
        }
    }

    /// A connection went away. When none is left, the countdown to stopping
    /// starts; the next connection cancels it.
    public func connectionClosed() {
        queue.async { [self] in
            openConnections = max(0, openConnections - 1)
            guard openConnections == 0 else { return }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + after)
            timer.setEventHandler { [self] in
                timer.cancel()
                self.timer = nil
                stop()
            }
            self.timer = timer
            timer.resume()
        }
    }
}

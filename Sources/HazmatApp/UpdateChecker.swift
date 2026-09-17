import Foundation
import HazmatAppSupport
import Sparkle

/// The only place that knows the update framework exists. A bundle that declares
/// no feed never starts it, because an updater with no feed can only fail — so a
/// development build offers no check and shows no error.
@MainActor
final class UpdateChecker: NSObject, UpdateChecking, SPUUpdaterDelegate {
    private var controller: SPUStandardUpdaterController?
    private var failure: String?

    override init() {
        super.init()
        // The controller holds its delegate weakly and only takes one at
        // construction, so it is built after this object exists and started by
        // hand, which is the documented path for exactly this case.
        guard Self.declaredFeed != nil else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
        controller.startUpdater()
        self.controller = controller
    }

    var availability: UpdateAvailability {
        guard controller != nil else { return .unavailable }
        if let failure { return .failed(failure) }
        return .available
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    /// Sparkle reports the answer as well as the problems through one callback;
    /// "no update was found" is the answer.
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard let reported = error else {
            failure = nil
            return
        }
        let failure = reported as NSError
        if failure.domain == SUSparkleErrorDomain, failure.code == SUError.noUpdateError.rawValue {
            self.failure = nil
            return
        }
        self.failure = failure.localizedDescription
    }

    private static var declaredFeed: String? {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
    }
}

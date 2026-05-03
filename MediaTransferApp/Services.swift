import Foundation
import StoreKit
import UIKit

// MARK: - User Stats
enum UserStats {
    private static let totalItemsKey = "stats.totalItemsTransferred"
    private static let totalTransfersKey = "stats.totalTransfers"
    private static let firstUseDateKey = "stats.firstUseDate"
    private static let hasSeenOnboardingKey = "stats.hasSeenOnboarding"
    private static let lastReviewRequestKey = "stats.lastReviewRequestDate"

    static var totalItems: Int {
        get { UserDefaults.standard.integer(forKey: totalItemsKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalItemsKey) }
    }

    static var totalTransfers: Int {
        get { UserDefaults.standard.integer(forKey: totalTransfersKey) }
        set { UserDefaults.standard.set(newValue, forKey: totalTransfersKey) }
    }

    static var firstUseDate: Date {
        if let date = UserDefaults.standard.object(forKey: firstUseDateKey) as? Date {
            return date
        }
        let now = Date()
        UserDefaults.standard.set(now, forKey: firstUseDateKey)
        return now
    }

    static var hasSeenOnboarding: Bool {
        get { UserDefaults.standard.bool(forKey: hasSeenOnboardingKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasSeenOnboardingKey) }
    }

    static var lastReviewRequest: Date? {
        get { UserDefaults.standard.object(forKey: lastReviewRequestKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastReviewRequestKey) }
    }

    static func recordTransfer(succeededItems: Int) {
        totalItems += succeededItems
        totalTransfers += 1
    }
}

// MARK: - Review Prompter
enum ReviewPrompter {
    private static let minTransfers = 5
    private static let minDaysBetweenRequests: TimeInterval = 120 * 24 * 60 * 60 // 4 maanden

    static func requestIfAppropriate() {
        guard UserStats.totalTransfers >= minTransfers else { return }
        if let last = UserStats.lastReviewRequest,
           Date().timeIntervalSince(last) < minDaysBetweenRequests {
            return
        }
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
        UserStats.lastReviewRequest = Date()
    }
}

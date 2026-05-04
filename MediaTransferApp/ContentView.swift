import SwiftUI
import Photos
import UniformTypeIdentifiers
import AVFoundation
import UIKit
import UserNotifications

// MARK: - Transfer Controller
@MainActor
final class TransferController: ObservableObject {
    struct Outcome {
        var succeeded: Int = 0
        var failed: [String] = []
        var cancelled: Bool = false
        var outOfSpace: Bool = false
    }

    @Published private(set) var isTransferring = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentFileName: String = ""
    @Published private(set) var completed: Int = 0
    @Published private(set) var total: Int = 0

    private var task: Task<Void, Never>?
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func start(assets: [PHAsset], destination: URL, deleteAfter: Bool, onFinish: @escaping (Outcome) -> Void) {
        guard !isTransferring else { return }
        isTransferring = true
        progress = 0
        completed = 0
        total = assets.count
        currentFileName = ""

        UIApplication.shared.isIdleTimerDisabled = true
        beginBackgroundTask()
        requestNotificationPermissionIfNeeded()

        task = Task { [weak self] in
            let result = await self?.run(assets: assets, destination: destination, deleteAfter: deleteAfter) ?? Outcome()
            self?.isTransferring = false
            self?.task = nil
            UIApplication.shared.isIdleTimerDisabled = false
            self?.endBackgroundTask()
            self?.postCompletionNotificationIfBackgrounded(result)
            onFinish(result)
        }
    }

    func cancel() { task?.cancel() }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "MediaTransfer") { [weak self] in
            self?.task?.cancel()
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    private func postCompletionNotificationIfBackgrounded(_ outcome: Outcome) {
        guard UIApplication.shared.applicationState != .active else { return }
        let content = UNMutableNotificationContent()
        if outcome.outOfSpace {
            content.title = NSLocalizedString("Not enough space", comment: "")
            content.body = String(format: NSLocalizedString("The destination doesn't have enough free space. %lld item(s) were copied before stopping.", comment: ""), outcome.succeeded)
        } else if outcome.cancelled {
            content.title = NSLocalizedString("Cancelled", comment: "")
            content.body = String(format: NSLocalizedString("Transfer cancelled. %lld item(s) copied.", comment: ""), outcome.succeeded)
        } else if !outcome.failed.isEmpty {
            content.title = NSLocalizedString("Transfer completed with errors", comment: "")
            content.body = String(format: NSLocalizedString("All %lld item(s) copied successfully.", comment: ""), outcome.succeeded)
        } else {
            content.title = NSLocalizedString("Transfer completed", comment: "")
            content.body = String(format: NSLocalizedString("All %lld item(s) copied successfully.", comment: ""), outcome.succeeded)
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private static let batchSize = 50
    private static let batchPauseNanos: UInt64 = 200_000_000

    private func run(assets: [PHAsset], destination: URL, deleteAfter: Bool) async -> Outcome {
        var outcome = Outcome()

        if let needed = totalEstimatedSize(of: assets),
           let free = freeSpace(at: destination),
           needed > free {
            outcome.outOfSpace = true
            return outcome
        }

        var assetsToDelete: [PHAsset] = []
        var globalIndex = 0
        var stop = false

        let batches = stride(from: 0, to: assets.count, by: Self.batchSize).map {
            Array(assets[$0..<min($0 + Self.batchSize, assets.count)])
        }

        for batch in batches {
            if stop || Task.isCancelled { break }

            for asset in batch {
                if Task.isCancelled {
                    outcome.cancelled = true
                    stop = true
                    break
                }

                guard let sourceURL = await fileURL(for: asset) else {
                    outcome.failed.append("Item \(globalIndex + 1)")
                    globalIndex += 1
                    completed = globalIndex
                    progress = Double(completed) / Double(max(total, 1))
                    continue
                }

                let uniqueName = Self.uniqueFileName(at: destination, original: sourceURL.lastPathComponent)
                currentFileName = uniqueName

                do {
                    try FileManager.default.copyItem(at: sourceURL, to: destination.appendingPathComponent(uniqueName))
                    outcome.succeeded += 1
                    if deleteAfter { assetsToDelete.append(asset) }
                } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError {
                    outcome.outOfSpace = true
                    stop = true
                    break
                } catch {
                    outcome.failed.append(sourceURL.lastPathComponent)
                }

                globalIndex += 1
                completed = globalIndex
                progress = Double(completed) / Double(max(total, 1))

                await Task.yield()
            }

            if !stop && !Task.isCancelled && batch.count == Self.batchSize {
                try? await Task.sleep(nanoseconds: Self.batchPauseNanos)
            }
        }

        if deleteAfter && !assetsToDelete.isEmpty && !outcome.cancelled {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }
        }

        return outcome
    }

    private func fileURL(for asset: PHAsset) async -> URL? {
        await withCheckedContinuation { continuation in
            if asset.mediaType == .video {
                let options = PHVideoRequestOptions()
                options.version = .original
                options.deliveryMode = .highQualityFormat
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                    continuation.resume(returning: (avAsset as? AVURLAsset)?.url)
                }
            } else {
                let options = PHContentEditingInputRequestOptions()
                options.isNetworkAccessAllowed = true
                options.canHandleAdjustmentData = { _ in true }
                asset.requestContentEditingInput(with: options) { input, _ in
                    continuation.resume(returning: input?.fullSizeImageURL)
                }
            }
        }
    }

    private func totalEstimatedSize(of assets: [PHAsset]) -> Int64? {
        var total: Int64 = 0
        var anyKnown = false
        for asset in assets {
            guard let resource = PHAssetResource.assetResources(for: asset).first,
                  let size = resource.value(forKey: "fileSize") as? Int64 else { continue }
            total += size
            anyKnown = true
        }
        return anyKnown ? total : nil
    }

    private func freeSpace(at url: URL) -> Int64? {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
        return attrs?[.systemFreeSize] as? Int64
    }

    static func uniqueFileName(at destinationURL: URL, original: String) -> String {
        let ext = (original as NSString).pathExtension
        let base = (original as NSString).deletingPathExtension
        var candidate = original
        var counter = 1
        while FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            counter += 1
        }
        return candidate
    }
}

// MARK: - App State (security-scoped folder)
final class AppState: ObservableObject {
    @Published var selectedDirectory: URL? {
        didSet {
            if let oldURL = oldValue {
                oldURL.stopAccessingSecurityScopedResource()
                hasAccess = false
            }
            if let newURL = selectedDirectory {
                hasAccess = newURL.startAccessingSecurityScopedResource()
            }
        }
    }

    private var hasAccess = false

    func requestAccess() -> Bool {
        guard let url = selectedDirectory else { return false }
        if !hasAccess {
            hasAccess = url.startAccessingSecurityScopedResource()
        }
        return hasAccess
    }

    func stopAccess() {
        if let url = selectedDirectory {
            url.stopAccessingSecurityScopedResource()
            hasAccess = false
        }
    }

    deinit { stopAccess() }
}

// MARK: - Splash Screen
private struct SplashScreen: View {
    @State private var isRotating = false
    @Binding var isVisible: Bool
    private let appBlue = Color(red: 0, green: 0.478, blue: 1.0)

    var body: some View {
        ZStack {
            appBlue.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 124, height: 124)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))
                VStack(spacing: 8) {
                    Text("USB Photo Transfer")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("No cloud. No account.")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                isRotating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { isVisible = false }
            }
        }
    }
}

// MARK: - Root
struct ContentView: View {
    @State private var showSplashScreen = true
    @State private var hasSeenOnboarding: Bool = UserStats.hasSeenOnboarding

    var body: some View {
        ZStack {
            if showSplashScreen {
                SplashScreen(isVisible: $showSplashScreen)
            } else if !hasSeenOnboarding {
                OnboardingView {
                    UserStats.hasSeenOnboarding = true
                    withAnimation { hasSeenOnboarding = true }
                }
            } else {
                MediaPickerView()
            }
        }
    }
}

#Preview {
    ContentView()
}

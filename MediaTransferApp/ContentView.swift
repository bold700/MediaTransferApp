import SwiftUI
import Photos
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Constants
private enum Constants {
    static let progressViewHeight: CGFloat = 100
    static let buttonCornerRadius: CGFloat = 10
    static let buttonStrokeWidth: CGFloat = 1
    static let buttonOpacity: Double = 0.1
    static let minButtonWidth: CGFloat = 280
    static let maxButtonWidth: CGFloat = 500
    static let appBlue = Color(red: 0.0, green: 0.478, blue: 1.0) // #007AFF
}

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

    func start(assets: [PHAsset], destination: URL, deleteAfter: Bool, onFinish: @escaping (Outcome) -> Void) {
        guard !isTransferring else { return }
        isTransferring = true
        progress = 0
        completed = 0
        total = assets.count
        currentFileName = ""

        task = Task { [weak self] in
            let result = await self?.run(assets: assets, destination: destination, deleteAfter: deleteAfter) ?? Outcome()
            self?.isTransferring = false
            self?.task = nil
            onFinish(result)
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func run(assets: [PHAsset], destination: URL, deleteAfter: Bool) async -> Outcome {
        var outcome = Outcome()

        // Pre-flight free space check (best-effort).
        if let needed = totalEstimatedSize(of: assets),
           let free = freeSpace(at: destination),
           needed > free {
            outcome.outOfSpace = true
            return outcome
        }

        var assetsToDelete: [PHAsset] = []

        for (index, asset) in assets.enumerated() {
            if Task.isCancelled {
                outcome.cancelled = true
                break
            }

            guard let sourceURL = await fileURL(for: asset) else {
                outcome.failed.append("Item \(index + 1)")
                completed = index + 1
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
                break
            } catch {
                outcome.failed.append(sourceURL.lastPathComponent)
            }

            completed = index + 1
            progress = Double(completed) / Double(max(total, 1))
        }

        if deleteAfter && !assetsToDelete.isEmpty && !outcome.cancelled {
            try? await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
            }
        }

        return outcome
    }

    // MARK: - Helpers
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

// MARK: - App State
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

    deinit {
        stopAccess()
    }
}

// MARK: - Splash Screen
private struct SplashScreen: View {
    @State private var isRotating = false
    @Binding var isVisible: Bool

    var body: some View {
        ZStack {
            Constants.appBlue
                .ignoresSafeArea()

            VStack(spacing: 11) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 124, height: 124)
                    .foregroundColor(.white)
                    .rotationEffect(.degrees(isRotating ? 360 : 0))

                Text("Media Transfer App")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                isRotating = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    isVisible = false
                }
            }
        }
    }
}

// MARK: - Content View
struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var transfer = TransferController()
    @State private var selectedAssets: [PHAsset] = []
    @State private var showImagePicker = false
    @State private var showDirectoryPicker = false
    @State private var shouldDeleteAfterTransfer = false
    @State private var showSplashScreen = true
    @State private var resultAlert: ResultAlert?
    @State private var showError = false
    @State private var errorMessage = ""

    private struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let resetSelection: Bool
    }

    private var selectedMediaCount: (photos: Int, videos: Int) {
        let photos = selectedAssets.filter { $0.mediaType == .image }.count
        let videos = selectedAssets.filter { $0.mediaType == .video }.count
        return (photos, videos)
    }

    var body: some View {
        ZStack {
            if showSplashScreen {
                SplashScreen(isVisible: $showSplashScreen)
            } else {
                mainView
            }
        }
    }

    private var mainView: some View {
        GeometryReader { geometry in
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        Spacer()

                        VStack(spacing: 20) {
                            headerView
                                .padding(.top, 20)
                                .padding(.bottom, 16)

                            mediaSelectionButton
                                .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                            if !selectedAssets.isEmpty {
                                selectedAssetsListView
                                    .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                            }
                            directorySelectionButton
                                .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                            transferButton
                                .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                            deleteToggle
                                .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))

                            if transfer.isTransferring {
                                transferProgressView
                                    .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                            }
                        }
                        .padding(.horizontal)

                        Spacer()
                    }
                    .frame(minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedAssets: $selectedAssets)
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    appState.selectedDirectory = url
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    if alert.resetSelection {
                        selectedAssets = []
                    }
                }
            )
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - View Components
    private var headerView: some View {
        Text("Media Transfer")
            .font(.largeTitle)
            .fontWeight(.bold)
    }

    private var mediaSelectionButton: some View {
        Button(action: {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        showImagePicker = true
                    }
                }
            }
        }) {
            HStack {
                Image(systemName: "photo.on.rectangle")
                Text("Select Media")
                if !selectedAssets.isEmpty {
                    Text("(\(selectedMediaCount.photos) photos, \(selectedMediaCount.videos) videos)")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Constants.appBlue.opacity(Constants.buttonOpacity))
            .foregroundColor(Constants.appBlue)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.buttonCornerRadius)
                    .stroke(Constants.appBlue, lineWidth: Constants.buttonStrokeWidth)
            )
            .cornerRadius(Constants.buttonCornerRadius)
        }
        .disabled(transfer.isTransferring)
    }

    private var selectedAssetsListView: some View {
        VStack(alignment: .leading, spacing: 5) {
            if selectedMediaCount.photos > 0 {
                HStack {
                    Image(systemName: "photo.fill")
                        .foregroundColor(Constants.appBlue)
                    Text("\(selectedMediaCount.photos) Photos")
                        .foregroundColor(.primary)
                }
            }
            if selectedMediaCount.videos > 0 {
                HStack {
                    Image(systemName: "video.fill")
                        .foregroundColor(Constants.appBlue)
                    Text("\(selectedMediaCount.videos) Videos")
                        .foregroundColor(.primary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(UIColor.systemBackground).opacity(0.1))
        .cornerRadius(Constants.buttonCornerRadius)
    }

    private var directorySelectionButton: some View {
        Button(action: {
            showDirectoryPicker = true
        }) {
            HStack {
                Image(systemName: "folder.badge.plus")
                Text("Save to...")
                if let directory = appState.selectedDirectory {
                    Text("(\(directory.lastPathComponent))")
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Constants.appBlue.opacity(Constants.buttonOpacity))
            .foregroundColor(Constants.appBlue)
            .overlay(
                RoundedRectangle(cornerRadius: Constants.buttonCornerRadius)
                    .stroke(Constants.appBlue, lineWidth: Constants.buttonStrokeWidth)
            )
            .cornerRadius(Constants.buttonCornerRadius)
        }
        .disabled(transfer.isTransferring)
    }

    private var transferButton: some View {
        Button(action: startTransfer) {
            HStack {
                Image(systemName: "arrow.right.circle.fill")
                Text("Start Transfer")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(canTransfer ? Constants.appBlue : Color.gray)
            .foregroundColor(.white)
            .cornerRadius(Constants.buttonCornerRadius)
        }
        .disabled(!canTransfer)
    }

    private var deleteToggle: some View {
        Toggle("Automatically delete after transfer", isOn: $shouldDeleteAfterTransfer)
            .padding(.horizontal)
            .tint(Constants.appBlue)
            .disabled(transfer.isTransferring)
    }

    private var transferProgressView: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Transferring...")
                Spacer()
                Text("\(transfer.completed) / \(transfer.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            ProgressView(value: transfer.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: Constants.appBlue))
                .frame(height: 10)
            if !transfer.currentFileName.isEmpty {
                Text(transfer.currentFileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("\(Int(transfer.progress * 100))%")
                    .font(.caption)
                Spacer()
                Button(role: .destructive) {
                    transfer.cancel()
                } label: {
                    Text("Cancel")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
        }
        .padding()
        .background(Constants.appBlue.opacity(0.05))
        .cornerRadius(Constants.buttonCornerRadius)
    }

    // MARK: - Helper Functions
    private func startTransfer() {
        guard let destinationURL = appState.selectedDirectory else { return }

        guard appState.requestAccess() else {
            errorMessage = "No access to selected folder"
            showError = true
            return
        }

        transfer.start(
            assets: selectedAssets,
            destination: destinationURL,
            deleteAfter: shouldDeleteAfterTransfer
        ) { outcome in
            self.resultAlert = makeAlert(for: outcome)
        }
    }

    private func makeAlert(for outcome: TransferController.Outcome) -> ResultAlert {
        if outcome.outOfSpace {
            return ResultAlert(
                title: "Not enough space",
                message: "The destination doesn't have enough free space. \(outcome.succeeded) item(s) were copied before stopping.",
                resetSelection: false
            )
        }
        if outcome.cancelled {
            return ResultAlert(
                title: "Cancelled",
                message: "Transfer cancelled. \(outcome.succeeded) item(s) copied.",
                resetSelection: false
            )
        }
        if !outcome.failed.isEmpty {
            let preview = outcome.failed.prefix(5).joined(separator: "\n")
            let extra = outcome.failed.count > 5 ? "\n…and \(outcome.failed.count - 5) more" : ""
            return ResultAlert(
                title: "Transfer completed with errors",
                message: "Copied \(outcome.succeeded) item(s). Failed:\n\(preview)\(extra)",
                resetSelection: outcome.succeeded > 0
            )
        }
        return ResultAlert(
            title: "Transfer completed",
            message: "All \(outcome.succeeded) item(s) copied successfully.",
            resetSelection: true
        )
    }

    private var canTransfer: Bool {
        !selectedAssets.isEmpty && appState.selectedDirectory != nil && !transfer.isTransferring
    }
}

#Preview {
    ContentView()
}

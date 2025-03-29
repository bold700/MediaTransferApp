import SwiftUI
import Photos
import UniformTypeIdentifiers
import AVFoundation

// MARK: - Constants
private enum Constants {
    static let timeoutInterval: TimeInterval = 30
    static let progressViewHeight: CGFloat = 100
    static let buttonCornerRadius: CGFloat = 10
    static let buttonStrokeWidth: CGFloat = 1
    static let buttonOpacity: Double = 0.1
    static let minButtonWidth: CGFloat = 280
    static let maxButtonWidth: CGFloat = 500
    static let appBlue = Color(red: 0.0, green: 0.478, blue: 1.0) // #007AFF
}

// MARK: - Transfer Service
final class TransferService {
    static func getUniqueFileName(at destinationURL: URL, originalFileName: String) -> String {
        let fileExtension = (originalFileName as NSString).pathExtension
        let fileNameWithoutExtension = (originalFileName as NSString).deletingPathExtension
        var counter = 1
        var newFileName = originalFileName
        
        while FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(newFileName).path) {
            newFileName = "\(fileNameWithoutExtension) (\(counter)).\(fileExtension)"
            counter += 1
        }
        
        return newFileName
    }

    static func getFileURL(for asset: PHAsset) -> URL? {
        var fileURL: URL?
        let semaphore = DispatchSemaphore(value: 0)
        
        if asset.mediaType == .video {
            let options = PHVideoRequestOptions()
            options.version = .original
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { (avAsset, _, _) in
                if let urlAsset = avAsset as? AVURLAsset {
                    fileURL = urlAsset.url
                }
                semaphore.signal()
            }
        } else {
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            options.canHandleAdjustmentData = { _ in true }
            
            asset.requestContentEditingInput(with: options) { input, info in
                fileURL = input?.fullSizeImageURL
                semaphore.signal()
            }
        }
        
        _ = semaphore.wait(timeout: .now() + Constants.timeoutInterval)
        return fileURL
    }
    
    static func transfer(assets: [PHAsset], to destinationURL: URL, shouldDelete: Bool, 
                        progressHandler: @escaping (Float) -> Void,
                        completionHandler: @escaping (Bool, String?) -> Void) {
        let queue = DispatchQueue(label: "com.mediatransfer.filetransfer", qos: .userInitiated)
        
        queue.async {
            let totalFiles = assets.count
            var completedFiles = 0
            var assetsToDelete: [PHAsset] = []
            
            for asset in assets {
                if let sourceURL = getFileURL(for: asset) {
                    do {
                        let uniqueFileName = getUniqueFileName(at: destinationURL, originalFileName: sourceURL.lastPathComponent)
                        let destinationFileURL = destinationURL.appendingPathComponent(uniqueFileName)
                        try FileManager.default.copyItem(at: sourceURL, to: destinationFileURL)
                        
                        if shouldDelete {
                            assetsToDelete.append(asset)
                        }
                        
                        completedFiles += 1
                        DispatchQueue.main.async {
                            progressHandler(Float(completedFiles) / Float(totalFiles))
                        }
                    } catch {
                        DispatchQueue.main.async {
                            completionHandler(false, "Error copying file: \(error.localizedDescription)")
                        }
                        return
                    }
                }
            }
            
            if shouldDelete && !assetsToDelete.isEmpty {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.deleteAssets(assetsToDelete as NSArray)
                }) { success, error in
                    if let error = error {
                        print("Error deleting assets: \(error.localizedDescription)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                completionHandler(true, nil)
            }
        }
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

// MARK: - Content View
struct ContentView: View {
    @StateObject private var appState = AppState()
    @State private var selectedAssets: [PHAsset] = []
    @State private var isTransferring = false
    @State private var transferProgress: Float = 0
    @State private var showImagePicker = false
    @State private var showDirectoryPicker = false
    @State private var shouldDeleteAfterTransfer = false
    @State private var transferCompleted = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showPhotoPermissionAlert = false
    
    private var selectedMediaCount: (photos: Int, videos: Int) {
        let photos = selectedAssets.filter { $0.mediaType == .image }.count
        let videos = selectedAssets.filter { $0.mediaType == .video }.count
        return (photos, videos)
    }
    
    var body: some View {
        GeometryReader { geometry in
            NavigationView {
                ScrollView {
                    VStack(spacing: 20) {
                        headerView
                            .padding(.top, 20)
                        
                        VStack(spacing: 20) {
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
                        }
                        .padding(.horizontal)
                        
                        if isTransferring {
                            transferProgressView
                                .frame(maxWidth: min(Constants.maxButtonWidth, geometry.size.width * 0.9))
                                .padding(.horizontal)
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
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
                        // Stop accessing previous URL if any
                        if let oldURL = appState.selectedDirectory {
                            oldURL.stopAccessingSecurityScopedResource()
                        }
                        appState.selectedDirectory = url
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .alert("Transfer completed", isPresented: $transferCompleted, actions: transferCompletedAlert)
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Photo Access", isPresented: $showPhotoPermissionAlert, actions: photoPermissionAlert)
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
            PHPhotoLibrary.requestAuthorization { status in
                DispatchQueue.main.async {
                    if status == .authorized {
                        showImagePicker = true
                    } else {
                        showPhotoPermissionAlert = true
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
    }
    
    private var transferProgressView: some View {
        VStack(spacing: 10) {
            Text("Transferring...")
            ProgressView(value: transferProgress)
                .progressViewStyle(LinearProgressViewStyle(tint: Constants.appBlue))
                .frame(height: 10)
            Text("\(Int(transferProgress * 100))%")
                .font(.caption)
        }
        .padding()
        .background(Constants.appBlue.opacity(0.05))
        .cornerRadius(Constants.buttonCornerRadius)
    }
    
    // MARK: - Alert Views
    private func transferCompletedAlert() -> some View {
        Button("OK") {
            transferCompleted = false
            selectedAssets = []
        }
    }
    
    private func photoPermissionAlert() -> some View {
        Group {
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) {
                showPhotoPermissionAlert = false
            }
        }
    }
    
    // MARK: - Helper Functions
    private func startTransfer() {
        guard let destinationURL = appState.selectedDirectory else { return }
        
        // Request access before starting transfer
        guard appState.requestAccess() else {
            errorMessage = "No access to selected folder"
            showError = true
            return
        }
        
        isTransferring = true
        transferProgress = 0
        
        TransferService.transfer(
            assets: selectedAssets,
            to: destinationURL,
            shouldDelete: shouldDeleteAfterTransfer,
            progressHandler: { progress in
                self.transferProgress = progress
            },
            completionHandler: { success, error in
                self.isTransferring = false
                
                if success {
                    self.transferCompleted = true
                } else if let error = error {
                    self.errorMessage = error
                    self.showError = true
                }
            }
        )
    }
    
    private var canTransfer: Bool {
        !selectedAssets.isEmpty && appState.selectedDirectory != nil
    }
}

#Preview {
    ContentView()
} 

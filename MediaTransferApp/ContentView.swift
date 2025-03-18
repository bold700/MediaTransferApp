import SwiftUI
import Photos
import UniformTypeIdentifiers
import AVFoundation

struct ContentView: View {
    @State private var selectedAssets: [PHAsset] = []
    @State private var selectedDirectory: URL?
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
    
    init() {
        // Maak een vaste map in de Documents directory
        if let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let transferPath = documentsPath.appendingPathComponent("MediaTransfers")
            do {
                // Maak de map aan als deze nog niet bestaat
                if !FileManager.default.fileExists(atPath: transferPath.path) {
                    try FileManager.default.createDirectory(at: transferPath, withIntermediateDirectories: true)
                }
                _selectedDirectory = State(initialValue: transferPath)
            } catch {
                print("Fout bij maken van map: \(error)")
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Titel
                Text("Media Transfer")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.top, 20)
                
                // Selecteer Foto's knop
                Button(action: checkPhotoLibraryPermission) {
                    HStack {
                        Image(systemName: "photo.on.rectangle")
                        Text("Selecteer Media")
                        if !selectedAssets.isEmpty {
                            Text("(\(selectedMediaCount.photos) foto's, \(selectedMediaCount.videos) video's)")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // Als er items geselecteerd zijn, toon een lijst
                if !selectedAssets.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(selectedAssets, id: \.localIdentifier) { asset in
                                HStack {
                                    Image(systemName: asset.mediaType == .video ? "video.fill" : "photo.fill")
                                        .foregroundColor(asset.mediaType == .video ? .red : .blue)
                                    if asset.mediaType == .video {
                                        Text(formatDuration(asset.duration))
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                            .frame(width: 50)
                                    }
                                    Text(asset.value(forKey: "filename") as? String ?? "Onbekend")
                                        .lineLimit(1)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .frame(maxHeight: 100)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(10)
                }
                
                // Kies Bestemming knop
                Button(action: {
                    showDirectoryPicker = true
                }) {
                    HStack {
                        Image(systemName: "folder")
                        Text("Kies Bestemming")
                        if let directory = selectedDirectory {
                            Text("(\(directory.lastPathComponent))")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                
                // Start Transfer knop
                Button(action: {
                    startTransfer(shouldDelete: shouldDeleteAfterTransfer)
                }) {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                        Text("Start Transfer")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background((selectedAssets.isEmpty || selectedDirectory == nil) ? Color.gray : Color.orange)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(selectedAssets.isEmpty || selectedDirectory == nil)
                
                // Toggle voor verwijderen na transfer
                Toggle("Verwijder bestanden na succesvolle transfer", isOn: $shouldDeleteAfterTransfer)
                    .padding(.horizontal)
                
                if isTransferring {
                    ProgressView(value: transferProgress) {
                        Text("\(Int(transferProgress * 100))%")
                            .font(.caption)
                    }
                    .padding()
                }
                
                // Info tekst
                Text("Bestanden worden opgeslagen in de MediaTransfers map in de app")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding()
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
                        // Sla de URL op en start direct met toegang
                        url.startAccessingSecurityScopedResource()
                        selectedDirectory = url
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            .alert("Transfer voltooid", isPresented: $transferCompleted) {
                Button("OK") {
                    selectedAssets = []
                    // Reset alleen de voortgang, behoud de geselecteerde map
                    transferProgress = 0
                }
            } message: {
                Text("Alle bestanden zijn succesvol overgebracht.")
            }
            .alert("Fout", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .alert("Foto Toegang", isPresented: $showPhotoPermissionAlert) {
                Button("Open Instellingen", role: .none) {
                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(settingsURL)
                    }
                }
                Button("Annuleren", role: .cancel) {}
            } message: {
                Text("Voor het verwijderen van foto's heeft de app volledige toegang nodig tot je fotobibliotheek. Je kunt dit aanpassen in de instellingen van je apparaat.")
            }
        }
    }
    
    private func checkPhotoLibraryPermission() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        
        switch status {
        case .notDetermined:
            // Vraag volledige toegang aan
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        // Als we beperkte toegang hebben, vraag dan om volledige toegang
                        if status == .limited {
                            self.showPhotoPermissionAlert = true
                        } else {
                            self.showImagePicker = true
                        }
                    } else {
                        self.showPhotoPermissionAlert = true
                    }
                }
            }
        case .restricted, .denied:
            self.showPhotoPermissionAlert = true
        case .authorized:
            self.showImagePicker = true
        case .limited:
            // Als we beperkte toegang hebben, vraag dan om volledige toegang
            self.showPhotoPermissionAlert = true
        @unknown default:
            self.showPhotoPermissionAlert = true
        }
    }
    
    private func startTransfer(shouldDelete: Bool) {
        guard let destinationURL = selectedDirectory else { return }
        
        isTransferring = true
        transferProgress = 0
        
        let queue = DispatchQueue(label: "com.mediatransfer.filetransfer", qos: .userInitiated)
        
        queue.async {
            let totalFiles = selectedAssets.count
            var completedFiles = 0
            var assetsToDelete: [PHAsset] = []
            
            for asset in selectedAssets {
                if let url = getFileURL(for: asset) {
                    do {
                        let destinationFileURL = destinationURL.appendingPathComponent(url.lastPathComponent)
                        try FileManager.default.copyItem(at: url, to: destinationFileURL)
                        
                        if shouldDelete {
                            assetsToDelete.append(asset)
                        }
                        
                        completedFiles += 1
                        DispatchQueue.main.async {
                            transferProgress = Float(completedFiles) / Float(totalFiles)
                        }
                    } catch {
                        DispatchQueue.main.async {
                            errorMessage = "Fout bij kopiëren van bestand: \(error.localizedDescription)"
                            showError = true
                            isTransferring = false
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
                        print("Fout bij verwijderen van assets: \(error.localizedDescription)")
                    }
                }
            }
            
            DispatchQueue.main.async {
                isTransferring = false
                transferCompleted = true
            }
        }
    }
    
    private func getFileURL(for asset: PHAsset) -> URL? {
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
        
        _ = semaphore.wait(timeout: .now() + 30)
        return fileURL
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#Preview {
    ContentView()
} 
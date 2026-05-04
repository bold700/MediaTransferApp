import Foundation
import Photos
import PhotosUI
import UIKit

@MainActor
final class PhotoLibrary: NSObject, ObservableObject, PHPhotoLibraryChangeObserver {
    enum Filter: CaseIterable, Identifiable {
        case all, photos, videos
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return NSLocalizedString("All", comment: "Filter: all")
            case .photos: return NSLocalizedString("Photos", comment: "Filter: photos")
            case .videos: return NSLocalizedString("Videos", comment: "Filter: videos")
            }
        }
        var predicate: NSPredicate? {
            switch self {
            case .all: return nil
            case .photos: return NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            case .videos: return NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            }
        }
    }

    @Published private(set) var assets: PHFetchResult<PHAsset>?
    @Published private(set) var totalCount: Int = 0
    @Published var filter: Filter = .all { didSet { reload() } }
    @Published private(set) var authStatus: PHAuthorizationStatus
    @Published private(set) var selectedIdentifiers: [String] = []

    let imageManager = PHCachingImageManager()
    let thumbnailSize = CGSize(width: 240, height: 240)

    override init() {
        self.authStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isAuthorized { self.reload() }
        }
    }

    var isLimited: Bool { authStatus == .limited }
    var isAuthorized: Bool { authStatus == .authorized || authStatus == .limited }

    var selectedAssets: [PHAsset] {
        guard !selectedIdentifiers.isEmpty else { return [] }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: selectedIdentifiers, options: nil)
        var out: [PHAsset] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in out.append(asset) }
        let order = Dictionary(uniqueKeysWithValues: selectedIdentifiers.enumerated().map { ($1, $0) })
        return out.sorted { (order[$0.localIdentifier] ?? 0) < (order[$1.localIdentifier] ?? 0) }
    }

    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        self.authStatus = status
        if status == .authorized || status == .limited {
            reload()
        }
    }

    func reload() {
        guard isAuthorized else {
            assets = nil
            totalCount = 0
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let predicate = filter.predicate {
            options.predicate = predicate
        }
        let result = PHAsset.fetchAssets(with: options)
        assets = result
        totalCount = result.count
        // Drop identifiers that no longer match
        selectedIdentifiers.removeAll { id in
            PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).count == 0
        }
        imageManager.stopCachingImagesForAllAssets()
    }

    func toggle(_ asset: PHAsset) {
        if let idx = selectedIdentifiers.firstIndex(of: asset.localIdentifier) {
            selectedIdentifiers.remove(at: idx)
        } else {
            selectedIdentifiers.append(asset.localIdentifier)
        }
    }

    func isSelected(_ asset: PHAsset) -> Bool {
        selectedIdentifiers.contains(asset.localIdentifier)
    }

    func clearSelection() {
        selectedIdentifiers.removeAll()
    }

    func presentLimitedPicker(from controller: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }
}

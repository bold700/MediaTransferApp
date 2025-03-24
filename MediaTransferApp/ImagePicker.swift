import SwiftUI
import Photos
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedAssets: [PHAsset]
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .any(of: [.images, .videos])
        configuration.selectionLimit = 0 // No limit
        configuration.preferredAssetRepresentationMode = .current
        
        // Configureer de layout voor iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            configuration.preselectedAssetIdentifiers = selectedAssets.map { $0.localIdentifier }
            // Gebruik een grotere kolombreedte op iPad
            configuration.selection = .ordered
        }
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        
        // Pas de collection view layout aan voor iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            if let collectionView = picker.view.subviews.first?.subviews.first as? UICollectionView {
                let layout = UICollectionViewFlowLayout()
                let spacing: CGFloat = 2
                let width = (UIScreen.main.bounds.width - spacing * 5) / 4
                layout.itemSize = CGSize(width: width, height: width)
                layout.minimumInteritemSpacing = spacing
                layout.minimumLineSpacing = spacing
                collectionView.collectionViewLayout = layout
            }
        }
        
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            let identifiers = results.compactMap(\.assetIdentifier)
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            
            parent.selectedAssets = (0..<fetchResult.count).compactMap { fetchResult.object(at: $0) }
            picker.dismiss(animated: true)
        }
    }
}

protocol CustomImagePickerControllerDelegate: AnyObject {
    func imagePickerDidFinish(with assets: [PHAsset])
}

class CustomImagePickerController: UIViewController {
    weak var delegate: CustomImagePickerControllerDelegate?
    var selectedAssets: [PHAsset] = []
    private var collectionView: UICollectionView!
    private var assets: PHFetchResult<PHAsset>!
    private var panGesture: UIPanGestureRecognizer!
    private var selectionLabel: UILabel!
    private var filterButton: UIButton!
    private var lastSelectedIndexPath: IndexPath?
    private var isSelecting = false
    
    enum FilterType {
        case allItems
        case favorites
        case photos
        case videos
        case screenshots
        
        var title: String {
            switch self {
            case .allItems: return "All Items"
            case .favorites: return "Favorites"
            case .photos: return "Photos"
            case .videos: return "Videos"
            case .screenshots: return "Screenshots"
            }
        }
        
        var predicate: NSPredicate? {
            switch self {
            case .allItems:
                return nil
            case .favorites:
                return NSPredicate(format: "favorite == YES")
            case .photos:
                return NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
            case .videos:
                return NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
            case .screenshots:
                return NSPredicate(format: "(mediaSubtype & %d) != 0", PHAssetMediaSubtype.photoScreenshot.rawValue)
            }
        }
    }
    
    private var currentFilter: FilterType = .allItems {
        didSet {
            loadAssets()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        loadAssets()
    }
    
    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePanGesture(_:)))
        panGesture.delegate = self
        collectionView.addGestureRecognizer(panGesture)
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: collectionView)
        
        switch gesture.state {
        case .began:
            if let indexPath = collectionView.indexPathForItem(at: location) {
                lastSelectedIndexPath = indexPath
                isSelecting = !(collectionView.indexPathsForSelectedItems?.contains(indexPath) == true)
                toggleSelection(at: indexPath)
            }
            
        case .changed:
            if let indexPath = collectionView.indexPathForItem(at: location),
               indexPath != lastSelectedIndexPath {
                lastSelectedIndexPath = indexPath
                toggleSelection(at: indexPath)
            }
            
        case .ended, .cancelled:
            lastSelectedIndexPath = nil
            isSelecting = false
            
        default:
            break
        }
    }
    
    private func toggleSelection(at indexPath: IndexPath) {
        if isSelecting {
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        } else {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        updateSelectionCount()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Create filter button
        filterButton = UIButton(type: .system)
        let filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
        filterButton.setImage(filterImage, for: .normal)
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.menu = createFilterMenu()
        
        // Create collection view layout
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        
        updateLayoutForCurrentOrientation(layout)
        
        // Create collection view
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Add navigation bar buttons
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Done",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Cancel",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        
        view.addSubview(collectionView)
        
        // Add toolbar with filter button and selection count
        selectionLabel = UILabel()
        selectionLabel.textAlignment = .center
        selectionLabel.font = .systemFont(ofSize: 17)
        selectionLabel.text = "No media selected"
        let labelItem = UIBarButtonItem(customView: selectionLabel)
        
        let filterBarButton = UIBarButtonItem(customView: filterButton)
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [filterBarButton, flexSpace, labelItem, flexSpace]
        navigationController?.setToolbarHidden(false, animated: false)
        
        // Register for orientation changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }
    
    private func createFilterMenu() -> UIMenu {
        let filters: [FilterType] = [
            .allItems,
            .favorites,
            .photos,
            .videos,
            .screenshots
        ]
        
        let actions = filters.map { filter in
            UIAction(title: filter.title, state: currentFilter == filter ? .on : .off) { [weak self] _ in
                self?.currentFilter = filter
                self?.filterButton.menu = self?.createFilterMenu()
            }
        }
        
        return UIMenu(title: "", options: .displayInline, children: actions)
    }
    
    private func updateLayoutForCurrentOrientation(_ layout: UICollectionViewFlowLayout) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let isLandscape = screenWidth > screenHeight
        
        // Bepaal het aantal items per rij op basis van de oriëntatie
        let numberOfItemsPerRow: CGFloat = isLandscape ? 6 : 4
        let spacing: CGFloat = 1
        let totalSpacing = (numberOfItemsPerRow - 1) * spacing
        let width = floor((screenWidth - totalSpacing) / numberOfItemsPerRow)
        layout.itemSize = CGSize(width: width, height: width)
    }
    
    @objc private func orientationDidChange() {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        updateLayoutForCurrentOrientation(layout)
        layout.invalidateLayout()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        
        if let predicate = currentFilter.predicate {
            options.predicate = predicate
        }
        
        assets = PHAsset.fetchAssets(with: options)
        collectionView.reloadData()
        
        // Reselect visible items that were previously selected
        for asset in selectedAssets {
            let index = assets.index(of: asset)
            if index != NSNotFound {
                let indexPath = IndexPath(item: index, section: 0)
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        
        updateSelectionLabel()
    }
    
    @objc private func cancelTapped() {
        delegate?.imagePickerDidFinish(with: [])
    }
    
    @objc private func doneTapped() {
        // Get newly selected items from current view
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let currentlySelectedAssets = selectedIndexPaths.map { assets.object(at: $0.item) }
        
        // Add newly selected items to existing selection if they're not already included
        for asset in currentlySelectedAssets {
            if !selectedAssets.contains(asset) {
                selectedAssets.append(asset)
            }
        }
        
        delegate?.imagePickerDidFinish(with: selectedAssets)
    }
    
    private func updateSelectionCount() {
        // Add newly selected items to selectedAssets
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let currentlySelectedAssets = Set(selectedIndexPaths.map { assets.object(at: $0.item) })
        
        // Remove deselected items that are visible in current filter
        let visibleAssets = Set((0..<assets.count).map { assets.object(at: $0) })
        selectedAssets.removeAll { asset in
            if visibleAssets.contains(asset) {
                return !currentlySelectedAssets.contains(asset)
            }
            return false
        }
        
        // Add newly selected items
        for asset in currentlySelectedAssets {
            if !selectedAssets.contains(asset) {
                selectedAssets.append(asset)
            }
        }
        
        updateSelectionLabel()
    }
    
    private func updateSelectionLabel() {
        let selectedPhotos = selectedAssets.filter { $0.mediaType == .image }.count
        let selectedVideos = selectedAssets.filter { $0.mediaType == .video }.count
        
        if selectedPhotos > 0 || selectedVideos > 0 {
            selectionLabel.text = "\(selectedPhotos) photos, \(selectedVideos) videos"
        } else {
            selectionLabel.text = "No media selected"
        }
    }
}

extension CustomImagePickerController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assets?.count ?? 0
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        let asset = assets.object(at: indexPath.item)
        cell.configure(with: asset)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        updateSelectionCount()
    }
    
    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        updateSelectionCount()
    }
}

class ImageCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let checkmarkView = UIImageView()
    private let videoIndicatorView = UIView()
    private let durationLabel = UILabel()
    private var requestID: PHImageRequestID?
    
    override var isSelected: Bool {
        didSet {
            checkmarkView.isHidden = !isSelected
            
            // Voeg een kleine animatie toe voor de selectie
            if isSelected {
                checkmarkView.transform = CGAffineTransform(scaleX: 0.1, y: 0.1)
                UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseOut], animations: {
                    self.checkmarkView.transform = .identity
                })
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        // Setup imageView
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // Setup video indicator view
        videoIndicatorView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        videoIndicatorView.isHidden = true
        contentView.addSubview(videoIndicatorView)
        
        // Setup duration label
        durationLabel.textColor = .white
        durationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        durationLabel.textAlignment = .right
        videoIndicatorView.addSubview(durationLabel)
        
        // Setup checkmarkView
        let checkmarkSize: CGFloat = 28
        checkmarkView.frame = CGRect(x: contentView.bounds.width - checkmarkSize - 4,
                                   y: contentView.bounds.height - checkmarkSize - 4,
                                   width: checkmarkSize,
                                   height: checkmarkSize)
        checkmarkView.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
        
        // Maak een configuratie voor het vinkje symbool
        var config = UIImage.SymbolConfiguration(pointSize: checkmarkSize - 8, weight: .medium)
        config = config.applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
        
        // Maak het vinkje met een cirkel eromheen
        let checkmark = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?.withRenderingMode(.alwaysOriginal)
        checkmarkView.image = checkmark
        checkmarkView.isHidden = true
        
        // Voeg een witte achtergrond toe
        checkmarkView.backgroundColor = .white
        checkmarkView.layer.cornerRadius = checkmarkSize / 2
        checkmarkView.clipsToBounds = true
        
        contentView.addSubview(checkmarkView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Update video indicator frame
        let height: CGFloat = 24
        videoIndicatorView.frame = CGRect(x: 0, y: bounds.height - height,
                                        width: bounds.width, height: height)
        
        // Update duration label frame
        durationLabel.frame = videoIndicatorView.bounds.insetBy(dx: 8, dy: 0)
    }
    
    func configure(with asset: PHAsset) {
        // Reset cell state
        imageView.image = nil
        checkmarkView.isHidden = !isSelected
        videoIndicatorView.isHidden = true
        
        // Cancel any existing request
        if let requestID = requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        
        // Request thumbnail
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        requestID = PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 200, height: 200),
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            self?.imageView.image = image
        }
        
        // Setup video indicator if needed
        if asset.mediaType == .video {
            videoIndicatorView.isHidden = false
            let duration = Int(asset.duration)
            let minutes = duration / 60
            let seconds = duration % 60
            durationLabel.text = String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    override func prepareForReuse() {
        super.prepareForReuse()
        if let requestID = requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        imageView.image = nil
        checkmarkView.isHidden = true
        videoIndicatorView.isHidden = true
    }
}

extension CustomImagePickerController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
} 
import SwiftUI
import Photos
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController

    @Binding var selectedAssets: [PHAsset]
    @Environment(\.presentationMode) private var presentationMode

    func makeUIViewController(context: Context) -> UINavigationController {
        let imagePicker = CustomImagePickerController()
        imagePicker.delegate = context.coordinator
        imagePicker.selectedAssets = selectedAssets
        return UINavigationController(rootViewController: imagePicker)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, CustomImagePickerControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerDidFinish(with assets: [PHAsset]) {
            parent.selectedAssets = assets
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}

protocol CustomImagePickerControllerDelegate: AnyObject {
    func imagePickerDidFinish(with assets: [PHAsset])
}

final class CustomImagePickerController: UIViewController {
    weak var delegate: CustomImagePickerControllerDelegate?
    var selectedAssets: [PHAsset] = []

    private var collectionView: UICollectionView!
    private var assets: PHFetchResult<PHAsset>?
    private var panGesture: UIPanGestureRecognizer!
    private var selectionLabel: UILabel!
    private var filterButton: UIButton!
    private var lastSelectedIndexPath: IndexPath?
    private var isSelecting = false
    private var collectionViewTopConstraint: NSLayoutConstraint!

    private let imageManager = PHCachingImageManager()
    private let thumbnailSize = CGSize(width: 240, height: 240)
    private let hapticGenerator = UISelectionFeedbackGenerator()

    private lazy var emptyStateView: UIView = {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let icon = UIImageView(image: UIImage(systemName: "photo.on.rectangle.angled"))
        icon.tintColor = .tertiaryLabel
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true

        let label = UILabel()
        label.text = NSLocalizedString("No items match this filter", comment: "Empty state in picker")
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 0

        stack.addArrangedSubview(icon)
        stack.addArrangedSubview(label)
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -24)
        ])
        return container
    }()

    private lazy var manageAccessBanner: UIView = {
        let banner = UIView()
        banner.backgroundColor = .secondarySystemBackground
        banner.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        let label = UILabel()
        label.text = NSLocalizedString("You've granted access to a limited set of photos.", comment: "Limited access banner")
        label.font = .preferredFont(forTextStyle: .footnote)
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let button = UIButton(type: .system)
        button.setTitle(NSLocalizedString("Manage", comment: "Manage limited photo access"), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote).withWeight(.semibold)
        button.addTarget(self, action: #selector(manageLimitedAccessTapped), for: .touchUpInside)
        button.setContentHuggingPriority(.required, for: .horizontal)

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(button)
        banner.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: banner.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -8),
            stack.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -16)
        ])
        return banner
    }()

    enum FilterType {
        case allItems
        case favorites
        case photos
        case videos
        case screenshots

        var title: String {
            switch self {
            case .allItems: return NSLocalizedString("All Items", comment: "")
            case .favorites: return NSLocalizedString("Favorites", comment: "")
            case .photos: return NSLocalizedString("Photos", comment: "")
            case .videos: return NSLocalizedString("Videos", comment: "")
            case .screenshots: return NSLocalizedString("Screenshots", comment: "")
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
        didSet { loadAssets() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        loadAssets()
        hapticGenerator.prepare()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.updateLayoutForSize(size)
        })
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
        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        updateSelectionCount()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        filterButton = UIButton(type: .system)
        let filterImage = UIImage(systemName: "line.3.horizontal.decrease.circle")
        filterButton.setImage(filterImage, for: .normal)
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.menu = createFilterMenu()

        let selectionStackView = UIStackView(frame: CGRect(x: 0, y: 0, width: 150, height: 52))
        selectionStackView.axis = .vertical
        selectionStackView.alignment = .center
        selectionStackView.distribution = .fillEqually

        let photosLabel = UILabel()
        photosLabel.font = .systemFont(ofSize: 15)
        photosLabel.textAlignment = .center

        let videosLabel = UILabel()
        videosLabel.font = .systemFont(ofSize: 15)
        videosLabel.textAlignment = .center

        selectionStackView.addArrangedSubview(photosLabel)
        selectionStackView.addArrangedSubview(videosLabel)

        selectionLabel = photosLabel
        let labelItem = UIBarButtonItem(customView: selectionStackView)

        let selectionButton = UIButton(type: .system)
        selectionButton.setTitle(NSLocalizedString("Select All", comment: ""), for: .normal)
        selectionButton.titleLabel?.adjustsFontSizeToFitWidth = false
        selectionButton.frame = CGRect(x: 0, y: 0, width: 140, height: 44)
        selectionButton.addTarget(self, action: #selector(selectionButtonTapped), for: .touchUpInside)

        let filterBarButton = UIBarButtonItem(customView: filterButton)
        let selectionBarButton = UIBarButtonItem(customView: selectionButton)
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let topSpaceItem = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
        topSpaceItem.width = 4

        toolbarItems = [topSpaceItem, filterBarButton, flexSpace, labelItem, flexSpace, selectionBarButton]

        navigationController?.setToolbarHidden(false, animated: false)
        navigationController?.toolbar.backgroundColor = .systemBackground

        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1

        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.prefetchDataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.alwaysBounceVertical = true
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        collectionView.translatesAutoresizingMaskIntoConstraints = false

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Done", comment: ""),
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: NSLocalizedString("Cancel", comment: ""),
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )

        view.addSubview(collectionView)
        collectionViewTopConstraint = collectionView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        NSLayoutConstraint.activate([
            collectionViewTopConstraint,
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .limited {
            installManageAccessBanner()
        }

        updateLayoutForSize(view.bounds.size)
    }

    private func installManageAccessBanner() {
        view.addSubview(manageAccessBanner)
        collectionViewTopConstraint.isActive = false
        NSLayoutConstraint.activate([
            manageAccessBanner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            manageAccessBanner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            manageAccessBanner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: manageAccessBanner.bottomAnchor)
        ])
    }

    @objc private func manageLimitedAccessTapped() {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: self)
    }

    private func createFilterMenu() -> UIMenu {
        let filters: [FilterType] = [.allItems, .favorites, .photos, .videos, .screenshots]
        let actions = filters.map { filter in
            UIAction(title: filter.title, state: currentFilter == filter ? .on : .off) { [weak self] _ in
                self?.currentFilter = filter
                self?.filterButton.menu = self?.createFilterMenu()
            }
        }
        return UIMenu(title: "", options: .displayInline, children: actions)
    }

    private func updateLayoutForSize(_ size: CGSize) {
        guard let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout else { return }
        let isLandscape = size.width > size.height
        let columns: CGFloat = isLandscape ? 6 : 4
        let spacing: CGFloat = 1
        let totalSpacing = (columns - 1) * spacing
        let itemWidth = floor((size.width - totalSpacing) / columns)
        layout.itemSize = CGSize(width: itemWidth, height: itemWidth)
        layout.invalidateLayout()
    }

    private func loadAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let predicate = currentFilter.predicate {
            options.predicate = predicate
        }
        assets = PHAsset.fetchAssets(with: options)
        imageManager.stopCachingImagesForAllAssets()
        collectionView.reloadData()

        if let assets = assets {
            for asset in selectedAssets {
                let index = assets.index(of: asset)
                if index != NSNotFound {
                    let indexPath = IndexPath(item: index, section: 0)
                    collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
                }
            }
        }

        updateEmptyState()
        updateSelectionLabel()
        updateDoneButtonTitle()
    }

    private func updateEmptyState() {
        let isEmpty = (assets?.count ?? 0) == 0
        collectionView.backgroundView = isEmpty ? emptyStateView : nil
    }

    @objc private func cancelTapped() {
        delegate?.imagePickerDidFinish(with: [])
    }

    @objc private func doneTapped() {
        guard let assets = assets else {
            delegate?.imagePickerDidFinish(with: selectedAssets)
            return
        }
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let currentlySelectedAssets = selectedIndexPaths.map { assets.object(at: $0.item) }
        for asset in currentlySelectedAssets where !selectedAssets.contains(asset) {
            selectedAssets.append(asset)
        }
        delegate?.imagePickerDidFinish(with: selectedAssets)
    }

    private func updateSelectionCount() {
        guard let assets = assets else { return }
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let currentlySelectedAssets = Set(selectedIndexPaths.map { assets.object(at: $0.item) })

        let visibleAssets = Set((0..<assets.count).map { assets.object(at: $0) })
        selectedAssets.removeAll { asset in
            visibleAssets.contains(asset) && !currentlySelectedAssets.contains(asset)
        }
        for asset in currentlySelectedAssets where !selectedAssets.contains(asset) {
            selectedAssets.append(asset)
        }

        updateSelectionLabel()
        updateDoneButtonTitle()

        if let selectionButton = toolbarItems?.last?.customView as? UIButton {
            let title = selectedIndexPaths.isEmpty
                ? NSLocalizedString("Select All", comment: "")
                : NSLocalizedString("Deselect All", comment: "")
            selectionButton.setTitle(title, for: .normal)
        }
    }

    private func updateDoneButtonTitle() {
        let count = selectedAssets.count
        let title = count == 0
            ? NSLocalizedString("Done", comment: "")
            : String(format: NSLocalizedString("Done (%lld)", comment: "Done with selection count"), count)
        navigationItem.rightBarButtonItem?.title = title
    }

    private func updateSelectionLabel() {
        let selectedPhotos = selectedAssets.filter { $0.mediaType == .image }.count
        let selectedVideos = selectedAssets.filter { $0.mediaType == .video }.count

        if let stackView = selectionLabel.superview as? UIStackView,
           let photosLabel = stackView.arrangedSubviews[0] as? UILabel,
           let videosLabel = stackView.arrangedSubviews[1] as? UILabel {

            if selectedPhotos > 0 || selectedVideos > 0 {
                photosLabel.text = String(format: NSLocalizedString("%lld photos", comment: ""), selectedPhotos)
                videosLabel.text = String(format: NSLocalizedString("%lld videos", comment: ""), selectedVideos)
            } else {
                photosLabel.text = NSLocalizedString("No media", comment: "")
                videosLabel.text = NSLocalizedString("selected", comment: "")
            }
        }
    }

    @objc private func selectionButtonTapped() {
        if collectionView.indexPathsForSelectedItems?.isEmpty ?? true {
            selectAllTapped()
        } else {
            deselectAllTapped()
        }
    }

    @objc private func selectAllTapped() {
        let totalSections = collectionView.numberOfSections
        for section in 0..<totalSections {
            let totalItems = collectionView.numberOfItems(inSection: section)
            for item in 0..<totalItems {
                let indexPath = IndexPath(item: item, section: section)
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        updateSelectionCount()
    }

    @objc private func deselectAllTapped() {
        collectionView.indexPathsForSelectedItems?.forEach { indexPath in
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        updateSelectionCount()
    }
}

extension CustomImagePickerController: UICollectionViewDelegate, UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return assets?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ImageCell", for: indexPath) as! ImageCell
        if let asset = assets?.object(at: indexPath.item) {
            cell.configure(with: asset, imageManager: imageManager, targetSize: thumbnailSize)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        updateSelectionCount()
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        hapticGenerator.selectionChanged()
        hapticGenerator.prepare()
        updateSelectionCount()
    }
}

extension CustomImagePickerController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard let assets = assets else { return }
        let toPrefetch = indexPaths.compactMap { ip -> PHAsset? in
            guard ip.item < assets.count else { return nil }
            return assets.object(at: ip.item)
        }
        imageManager.startCachingImages(for: toPrefetch, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        guard let assets = assets else { return }
        let toCancel = indexPaths.compactMap { ip -> PHAsset? in
            guard ip.item < assets.count else { return nil }
            return assets.object(at: ip.item)
        }
        imageManager.stopCachingImages(for: toCancel, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
    }
}

final class ImageCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let checkmarkView = UIImageView()
    private let videoIndicatorView = UIView()
    private let durationLabel = UILabel()
    private weak var imageManager: PHCachingImageManager?
    private var requestID: PHImageRequestID?

    override var isSelected: Bool {
        didSet {
            checkmarkView.isHidden = !isSelected
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
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        videoIndicatorView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        videoIndicatorView.isHidden = true
        contentView.addSubview(videoIndicatorView)

        durationLabel.textColor = .white
        durationLabel.font = .systemFont(ofSize: 12, weight: .medium)
        durationLabel.textAlignment = .right
        videoIndicatorView.addSubview(durationLabel)

        let checkmarkSize: CGFloat = 28
        checkmarkView.frame = CGRect(x: contentView.bounds.width - checkmarkSize - 4,
                                     y: contentView.bounds.height - checkmarkSize - 4,
                                     width: checkmarkSize,
                                     height: checkmarkSize)
        checkmarkView.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]

        var config = UIImage.SymbolConfiguration(pointSize: checkmarkSize - 8, weight: .medium)
        config = config.applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
        let checkmark = UIImage(systemName: "checkmark.circle.fill", withConfiguration: config)?
            .withRenderingMode(.alwaysOriginal)
        checkmarkView.image = checkmark
        checkmarkView.isHidden = true
        checkmarkView.backgroundColor = .white
        checkmarkView.layer.cornerRadius = checkmarkSize / 2
        checkmarkView.clipsToBounds = true

        contentView.addSubview(checkmarkView)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height: CGFloat = 24
        videoIndicatorView.frame = CGRect(x: 0, y: bounds.height - height,
                                          width: bounds.width, height: height)
        durationLabel.frame = videoIndicatorView.bounds.insetBy(dx: 8, dy: 0)
    }

    func configure(with asset: PHAsset, imageManager: PHCachingImageManager, targetSize: CGSize) {
        imageView.image = nil
        checkmarkView.isHidden = !isSelected
        videoIndicatorView.isHidden = true

        if let requestID = requestID {
            imageManager.cancelImageRequest(requestID)
        }
        self.imageManager = imageManager

        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true

        requestID = imageManager.requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { [weak self] image, _ in
            self?.imageView.image = image
        }

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
            imageManager?.cancelImageRequest(requestID)
        }
        imageView.image = nil
        checkmarkView.isHidden = true
        videoIndicatorView.isHidden = true
    }
}

extension CustomImagePickerController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == panGesture else { return true }
        let velocity = panGesture.velocity(in: collectionView)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}

private extension UIFont {
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let descriptor = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

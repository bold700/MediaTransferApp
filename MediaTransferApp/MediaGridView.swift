import SwiftUI
import Photos
import UIKit

struct MediaGridView: UIViewRepresentable {
    @ObservedObject var library: PhotoLibrary
    var transferring: Bool = false
    let columns: Int = 4
    let spacing: CGFloat = 1
    let topInset: CGFloat
    let bottomInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(library: library, columns: columns, spacing: spacing)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = spacing
        layout.minimumLineSpacing = spacing

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .systemBackground
        cv.alwaysBounceVertical = true
        cv.allowsMultipleSelection = true
        cv.contentInsetAdjustmentBehavior = .never
        cv.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
        cv.scrollIndicatorInsets = cv.contentInset
        cv.showsVerticalScrollIndicator = false

        cv.register(MediaCell.self, forCellWithReuseIdentifier: MediaCell.reuseId)
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        cv.prefetchDataSource = context.coordinator

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.maximumNumberOfTouches = 1
        cv.addGestureRecognizer(pan)
        context.coordinator.collectionView = cv
        context.coordinator.panGesture = pan

        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        context.coordinator.update(library: library, topInset: topInset, bottomInset: bottomInset)
        cv.allowsSelection = !transferring
        context.coordinator.panGesture?.isEnabled = !transferring
    }

    // MARK: - Coordinator
    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate,
                             UICollectionViewDelegateFlowLayout,
                             UICollectionViewDataSourcePrefetching, UIGestureRecognizerDelegate {
        weak var collectionView: UICollectionView?
        weak var panGesture: UIPanGestureRecognizer?
        var library: PhotoLibrary
        let columns: Int
        let spacing: CGFloat
        private var lastAssetsId: ObjectIdentifier?
        private var lastSelectionCount: Int = -1
        private var lastTopInset: CGFloat = 0
        private var lastBottomInset: CGFloat = 0

        // Pan-select state
        private var dragMode: Bool? = nil
        private var lastPannedIndex: Int? = nil
        private let haptic = UISelectionFeedbackGenerator()

        init(library: PhotoLibrary, columns: Int, spacing: CGFloat) {
            self.library = library
            self.columns = columns
            self.spacing = spacing
            super.init()
        }

        func update(library: PhotoLibrary, topInset: CGFloat, bottomInset: CGFloat) {
            self.library = library
            guard let cv = collectionView else { return }

            if topInset != lastTopInset || bottomInset != lastBottomInset {
                let wasAtTop = cv.contentOffset.y <= -cv.contentInset.top + 1
                cv.contentInset = UIEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0)
                cv.scrollIndicatorInsets = cv.contentInset
                if wasAtTop {
                    cv.contentOffset = CGPoint(x: 0, y: -topInset)
                }
                lastTopInset = topInset
                lastBottomInset = bottomInset
            }

            let currentId = library.assets.map { ObjectIdentifier($0) }
            if currentId != lastAssetsId {
                lastAssetsId = currentId
                cv.reloadData()
                cv.setContentOffset(CGPoint(x: 0, y: -topInset), animated: false)
                applySelection(in: cv)
            } else if library.selectedIdentifiers.count != lastSelectionCount {
                applySelection(in: cv)
            }
            lastSelectionCount = library.selectedIdentifiers.count
        }

        // Recompute cell size every time — guarantees correct sizing even before
        // the collection view has been laid out for the first time.
        func collectionView(_ cv: UICollectionView,
                            layout: UICollectionViewLayout,
                            sizeForItemAt indexPath: IndexPath) -> CGSize {
            let width = max(cv.bounds.width, 1)
            let totalSpacing = CGFloat(columns - 1) * spacing
            let cellSize = floor((width - totalSpacing) / CGFloat(columns))
            return CGSize(width: cellSize, height: cellSize)
        }

        private func applySelection(in cv: UICollectionView) {
            guard let assets = library.assets else { return }
            let selected = Set(library.selectedIdentifiers)
            for indexPath in cv.indexPathsForVisibleItems {
                guard indexPath.item < assets.count,
                      let cell = cv.cellForItem(at: indexPath) as? MediaCell else { continue }
                let asset = assets.object(at: indexPath.item)
                cell.setSelectedDecoration(selected.contains(asset.localIdentifier), animated: false)
            }
        }

        // MARK: DataSource
        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            library.assets?.count ?? 0
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(withReuseIdentifier: MediaCell.reuseId, for: indexPath) as! MediaCell
            guard let assets = library.assets, indexPath.item < assets.count else { return cell }
            let asset = assets.object(at: indexPath.item)
            let isSel = library.selectedIdentifiers.contains(asset.localIdentifier)
            cell.configure(with: asset, imageManager: library.imageManager, isSelected: isSel)
            return cell
        }

        // MARK: Delegate
        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            cv.deselectItem(at: indexPath, animated: false)
            guard let assets = library.assets, indexPath.item < assets.count else { return }
            let asset = assets.object(at: indexPath.item)
            haptic.selectionChanged()
            haptic.prepare()
            library.toggle(asset)
            if let cell = cv.cellForItem(at: indexPath) as? MediaCell {
                cell.setSelectedDecoration(library.isSelected(asset), animated: true)
            }
        }

        // MARK: Prefetching
        func collectionView(_ cv: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
            guard let assets = library.assets else { return }
            let toPrefetch = indexPaths.compactMap { ip -> PHAsset? in
                guard ip.item < assets.count else { return nil }
                return assets.object(at: ip.item)
            }
            library.imageManager.startCachingImages(
                for: toPrefetch,
                targetSize: library.thumbnailSize,
                contentMode: .aspectFill,
                options: nil
            )
        }

        func collectionView(_ cv: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
            guard let assets = library.assets else { return }
            let toCancel = indexPaths.compactMap { ip -> PHAsset? in
                guard ip.item < assets.count else { return nil }
                return assets.object(at: ip.item)
            }
            library.imageManager.stopCachingImages(
                for: toCancel,
                targetSize: library.thumbnailSize,
                contentMode: .aspectFill,
                options: nil
            )
        }

        // MARK: Pan-select
        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let cv = collectionView else { return }
            let location = gr.location(in: cv)
            switch gr.state {
            case .began:
                if let indexPath = cv.indexPathForItem(at: location) {
                    lastPannedIndex = indexPath.item
                    apply(at: indexPath)
                }
            case .changed:
                if let indexPath = cv.indexPathForItem(at: location),
                   indexPath.item != lastPannedIndex {
                    lastPannedIndex = indexPath.item
                    apply(at: indexPath)
                }
            case .ended, .cancelled, .failed:
                lastPannedIndex = nil
                dragMode = nil
            default:
                break
            }
        }

        private func apply(at indexPath: IndexPath) {
            guard let assets = library.assets, indexPath.item < assets.count else { return }
            let asset = assets.object(at: indexPath.item)
            let isSel = library.isSelected(asset)
            if dragMode == nil {
                dragMode = !isSel
            }
            let shouldSelect = dragMode ?? true
            if shouldSelect != isSel {
                library.toggle(asset)
                haptic.selectionChanged()
                haptic.prepare()
                if let cell = collectionView?.cellForItem(at: indexPath) as? MediaCell {
                    cell.setSelectedDecoration(shouldSelect, animated: true)
                }
            }
        }

        // MARK: Gesture delegate
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            return true
        }

        // Only start when horizontal motion dominates — verticaal blijft scrollen
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let translation = pan.translation(in: pan.view)
            return abs(translation.x) > abs(translation.y)
        }
    }
}

// MARK: - Cell
final class MediaCell: UICollectionViewCell {
    static let reuseId = "MediaCell"

    private let imageView = UIImageView()
    private let dim = UIView()
    private let checkmark = UIImageView()
    private let videoBar = UIView()
    private let durationLabel = UILabel()
    private var requestID: PHImageRequestID?
    private weak var imageManager: PHCachingImageManager?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.frame = contentView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.backgroundColor = .secondarySystemBackground
        contentView.addSubview(imageView)

        dim.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.18)
        dim.frame = contentView.bounds
        dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isHidden = true
        contentView.addSubview(dim)

        videoBar.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        videoBar.isHidden = true
        contentView.addSubview(videoBar)

        durationLabel.textColor = .white
        durationLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        durationLabel.textAlignment = .right
        videoBar.addSubview(durationLabel)

        let size: CGFloat = 22
        checkmark.frame = CGRect(x: 4, y: 4, width: size, height: size)
        checkmark.autoresizingMask = []
        let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: .bold)
            .applying(UIImage.SymbolConfiguration(paletteColors: [.white, .systemBlue]))
        checkmark.image = UIImage(systemName: "checkmark.circle.fill", withConfiguration: cfg)?
            .withRenderingMode(.alwaysOriginal)
        checkmark.layer.shadowColor = UIColor.black.cgColor
        checkmark.layer.shadowOpacity = 0.25
        checkmark.layer.shadowRadius = 2
        checkmark.layer.shadowOffset = CGSize(width: 0, height: 1)
        checkmark.isHidden = true
        contentView.addSubview(checkmark)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let h: CGFloat = 20
        videoBar.frame = CGRect(x: 0, y: bounds.height - h, width: bounds.width, height: h)
        durationLabel.frame = videoBar.bounds.insetBy(dx: 6, dy: 0)
    }

    func configure(with asset: PHAsset, imageManager: PHCachingImageManager, isSelected: Bool) {
        if let id = requestID { self.imageManager?.cancelImageRequest(id) }
        self.imageManager = imageManager
        imageView.image = nil
        setSelectedDecoration(isSelected, animated: false)

        if asset.mediaType == .video {
            videoBar.isHidden = false
            let s = Int(asset.duration)
            durationLabel.text = String(format: "%d:%02d", s / 60, s % 60)
        } else {
            videoBar.isHidden = true
        }

        let scale = UIScreen.main.scale
        let target = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        opts.resizeMode = .fast
        requestID = imageManager.requestImage(for: asset, targetSize: target,
                                              contentMode: .aspectFill, options: opts) { [weak self] image, _ in
            if let image { self?.imageView.image = image }
        }
    }

    func setSelectedDecoration(_ selected: Bool, animated: Bool) {
        let wasHidden = checkmark.isHidden
        dim.isHidden = !selected
        checkmark.isHidden = !selected
        if selected && wasHidden && animated {
            checkmark.transform = CGAffineTransform(scaleX: 0.3, y: 0.3)
            UIView.animate(withDuration: 0.15) { self.checkmark.transform = .identity }
        } else {
            checkmark.transform = .identity
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let id = requestID { imageManager?.cancelImageRequest(id) }
        requestID = nil
        imageView.image = nil
        dim.isHidden = true
        checkmark.isHidden = true
        videoBar.isHidden = true
    }
}

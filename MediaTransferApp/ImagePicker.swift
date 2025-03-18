import SwiftUI
import Photos
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    typealias UIViewControllerType = UINavigationController
    
    @Binding var selectedAssets: [PHAsset]
    @Environment(\.presentationMode) var presentationMode
    
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
    
    class Coordinator: NSObject, CustomImagePickerControllerDelegate {
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

class CustomImagePickerController: UIViewController {
    weak var delegate: CustomImagePickerControllerDelegate?
    var selectedAssets: [PHAsset] = []
    private var collectionView: UICollectionView!
    private var assets: PHFetchResult<PHAsset>!
    private var panGesture: UIPanGestureRecognizer!
    private var selectionLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadAssets()
    }
    
    private func setupUI() {
        view.backgroundColor = .systemBackground
        
        // Maak een layout voor de collection view
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 1
        layout.minimumLineSpacing = 1
        
        // Bereken de cell grootte
        let screenWidth = UIScreen.main.bounds.width
        let numberOfItemsPerRow: CGFloat = 5
        let spacing: CGFloat = 1
        let totalSpacing = (numberOfItemsPerRow - 1) * spacing
        let width = floor((screenWidth - totalSpacing) / numberOfItemsPerRow)
        layout.itemSize = CGSize(width: width, height: width)
        
        // Maak de collection view
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: layout)
        collectionView.backgroundColor = .systemBackground
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsMultipleSelection = true
        collectionView.register(ImageCell.self, forCellWithReuseIdentifier: "ImageCell")
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)
        
        // Voeg knoppen toe aan de navigatiebalk
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Annuleren",
            style: .plain,
            target: self,
            action: #selector(cancelTapped)
        )
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Gereed",
            style: .done,
            target: self,
            action: #selector(doneTapped)
        )
        
        // Voeg de toolbar toe met Selecteer alles en Deselecteer knoppen
        let selectAllButton = UIBarButtonItem(
            title: "Selecteer alles",
            style: .plain,
            target: self,
            action: #selector(selectAllTapped)
        )
        
        let deselectButton = UIBarButtonItem(
            title: "Deselecteer",
            style: .plain,
            target: self,
            action: #selector(deselectAllTapped)
        )
        
        // Maak het label voor het aantal geselecteerde items
        selectionLabel = UILabel()
        selectionLabel.textAlignment = .center
        selectionLabel.font = .systemFont(ofSize: 17)
        selectionLabel.text = "Geen foto's geselecteerd"
        let labelItem = UIBarButtonItem(customView: selectionLabel)
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        toolbarItems = [selectAllButton, flexSpace, labelItem, flexSpace, deselectButton]
        navigationController?.setToolbarHidden(false, animated: false)
    }
    
    private func loadAssets() {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Haal alle assets op (foto's en video's)
        assets = PHAsset.fetchAssets(with: fetchOptions)
        collectionView.reloadData()
        
        // Selecteer eerder geselecteerde items
        for asset in selectedAssets {
            let index = assets.index(of: asset)
            if index != NSNotFound {
                let indexPath = IndexPath(item: index, section: 0)
                collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
            }
        }
        
        // Update het label met het totaal aantal items
        updateSelectionCount()
    }
    
    @objc private func cancelTapped() {
        delegate?.imagePickerDidFinish(with: [])
    }
    
    @objc private func doneTapped() {
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let selectedAssets = selectedIndexPaths.map { assets.object(at: $0.item) }
        delegate?.imagePickerDidFinish(with: selectedAssets)
    }
    
    @objc private func selectAllTapped() {
        guard let assets = assets else { return }
        for i in 0..<assets.count {
            let indexPath = IndexPath(item: i, section: 0)
            collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        }
        updateSelectionCount()
    }
    
    @objc private func deselectAllTapped() {
        guard let assets = assets else { return }
        for i in 0..<assets.count {
            let indexPath = IndexPath(item: i, section: 0)
            collectionView.deselectItem(at: indexPath, animated: false)
        }
        updateSelectionCount()
    }
    
    @objc private func handlePanGesture(_ gesture: UIPanGestureRecognizer) {
        // Implementeer de logica voor het afhandelen van de pan gesture
    }
    
    func updateSelectionCount() {
        guard let collectionView = collectionView,
              let selectionLabel = selectionLabel,
              let assets = assets else { return }
        
        let selectedCount = collectionView.indexPathsForSelectedItems?.count ?? 0
        let totalCount = assets.count
        
        // Tel het aantal foto's en video's
        let selectedIndexPaths = collectionView.indexPathsForSelectedItems ?? []
        let selectedPhotos = selectedIndexPaths.filter { assets.object(at: $0.item).mediaType == .image }.count
        let selectedVideos = selectedIndexPaths.filter { assets.object(at: $0.item).mediaType == .video }.count
        
        if selectedCount > 0 {
            selectionLabel.text = "\(selectedPhotos) foto's, \(selectedVideos) video's"
        } else {
            selectionLabel.text = "Geen media geselecteerd"
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
import Foundation
import Photos
import UIKit

extension FileManager {
    func copyFile(at sourceURL: URL, to destinationURL: URL, progress: @escaping (Double) -> Void) throws {
        let fileSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as! Int64
        let input = try FileHandle(forReadingFrom: sourceURL)
        let output = try FileHandle(forWritingTo: destinationURL)
        
        let chunkSize = 1024 * 1024 // 1MB chunks
        var bytesProcessed: Int64 = 0
        
        while true {
            autoreleasepool {
                if let data = try? input.read(upToCount: chunkSize) {
                    if data.count > 0 {
                        try? output.write(contentsOf: data)
                        bytesProcessed += Int64(data.count)
                        let progressValue = Double(bytesProcessed) / Double(fileSize)
                        DispatchQueue.main.async {
                            progress(progressValue)
                        }
                    }
                }
            }
            
            if bytesProcessed >= fileSize {
                break
            }
        }
        
        try input.close()
        try output.close()
    }
    
    func copyAsset(_ asset: PHAsset, to destinationURL: URL, completion: @escaping (Result<URL, Error>) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: options
        ) { image, info in
            guard let image = image,
                  let data = image.jpegData(compressionQuality: 1.0) else {
                completion(.failure(NSError(domain: "MediaTransferApp", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("error_loading_image", comment: "Error when image cannot be loaded")])))
                return
            }
            
            let fileName = UUID().uuidString + ".jpg"
            let destinationFileURL = destinationURL.appendingPathComponent(fileName)
            
            do {
                try data.write(to: destinationFileURL)
                completion(.success(destinationFileURL))
            } catch {
                completion(.failure(error))
            }
        }
    }
    
    func copyAssets(_ assets: [PHAsset], to destinationURL: URL, progress: @escaping (Double) -> Void, completion: @escaping (Result<Void, Error>) -> Void) {
        let group = DispatchGroup()
        var errors: [Error] = []
        let totalAssets = Double(assets.count)
        var completedAssets: Double = 0
        
        for asset in assets {
            group.enter()
            
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isSynchronous = false
            
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .default,
                options: options
            ) { image, info in
                guard let image = image,
                      let data = image.jpegData(compressionQuality: 1.0) else {
                    errors.append(NSError(domain: "MediaTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("error_loading_image", comment: "Error when image cannot be loaded")]))
                    group.leave()
                    return
                }
                
                let fileName = "\(asset.localIdentifier.replacingOccurrences(of: "/", with: "-")).jpg"
                let fileURL = destinationURL.appendingPathComponent(fileName)
                
                do {
                    try data.write(to: fileURL)
                    completedAssets += 1
                    let progressValue = completedAssets / totalAssets
                    DispatchQueue.main.async {
                        progress(progressValue)
                    }
                } catch {
                    errors.append(error)
                }
                
                group.leave()
            }
        }
        
        group.notify(queue: .main) {
            if errors.isEmpty {
                completion(.success(()))
            } else {
                completion(.failure(errors[0])) // Only returning the first error
            }
        }
    }
    
    private func requestImage(for asset: PHAsset, completion: @escaping (Result<Data, Error>) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current
        
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .default,
            options: options
        ) { image, info in
            guard let image = image else {
                completion(.failure(NSError(domain: "MediaTransfer", code: -1, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("error_loading_image", comment: "Error when image cannot be loaded")])))
                return
            }
            
            guard let data = image.jpegData(compressionQuality: 1.0) else {
                completion(.failure(NSError(domain: "MediaTransfer", code: -2, userInfo: [NSLocalizedDescriptionKey: NSLocalizedString("error_converting_jpeg", comment: "Error when image cannot be converted to JPEG")])))
                return
            }
            
            completion(.success(data))
        }
    }
} 
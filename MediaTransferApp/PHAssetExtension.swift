import Photos

extension PHAsset {
    func getFileURL() -> URL? {
        var fileURL: URL?
        let semaphore = DispatchSemaphore(value: 0)
        
        let options = PHContentEditingInputRequestOptions()
        options.isNetworkAccessAllowed = true
        options.canHandleAdjustmentData = { _ in true }
        
        requestContentEditingInput(with: options) { input, info in
            fileURL = input?.fullSizeImageURL
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 30)
        return fileURL
    }
} 
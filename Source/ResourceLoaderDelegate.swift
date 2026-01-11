//
//  ResourceLoaderDelegate.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation
import UIKit

/// Responsible for downloading media data and providing the requested data parts.
final class ResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate, URLSessionDelegate, URLSessionDataDelegate, URLSessionTaskDelegate {
    typealias PendingRequestId = Int

    private let lock = NSLock()

    private var bufferData = Data()
    private var fullDownloadWriteOffset = 0
    private var fullDownloadExpectedStart = 0
    private var fullDownloadRetryCount = 0
    private let maxFullDownloadRetries = 3
    private let retryDelayBase: TimeInterval = 0.5
    private var isRetryingFullDownload = false
    private var contentInfoRetryCount = 0
    private let maxContentInfoRetries = 3
    private var configuration: CachingPlayerItemConfiguration { owner?.configuration ?? .default }

    private lazy var fileHandle = MediaFileHandle(filePath: saveFilePath)

    private var session: URLSession?
    private let operationQueue = {
        let queue = OperationQueue()
        queue.name = "CachingPlayerItemOperationQueue"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private var pendingContentInfoRequest: PendingContentInfoRequest? {
        didSet { oldValue?.cancelTask() }
    }
    private var contentInfoResponse: URLResponse?
    private var pendingContentInfoLoadingRequests: [AVAssetResourceLoadingRequest] = []
    private var pendingDataRequests: [PendingRequestId: PendingDataRequest] = [:]
    private var fullMediaFileDownloadTask: URLSessionDataTask?
    private(set) var isDownloadComplete = false

    private let url: URL
    private let saveFilePath: String
    private weak var owner: CachingPlayerItem?

    // MARK: Init

    init(url: URL, saveFilePath: String, owner: CachingPlayerItem?) {
        self.url = url
        self.saveFilePath = saveFilePath
        self.owner = owner
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleAppWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: AVAssetResourceLoaderDelegate

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if session == nil {
            startFileDownload(with: url)
        }

        assert(session != nil, "Session must be set before proceeding.")
        guard let session else { return false }

        if let _ = loadingRequest.contentInformationRequest {
            if let response = contentInfoResponse {
                fillInContentInformationRequest(for: loadingRequest, response: response)
                loadingRequest.finishLoading()
                return true
            }

            addOperationOnQueue { [weak self] in
                guard let self else { return }

                pendingContentInfoLoadingRequests.append(loadingRequest)

                guard pendingContentInfoRequest == nil else { return }

                let request = PendingContentInfoRequest(url: url, session: session, loadingRequest: loadingRequest, customHeaders: owner?.urlRequestHeaders)
                pendingContentInfoRequest = request
                request.startTask()
            }
            return true
        } else if let _ = loadingRequest.dataRequest {
            let request = PendingDataRequest(url: url, session: session, loadingRequest: loadingRequest, customHeaders: owner?.urlRequestHeaders)
            request.delegate = self
            request.startTask()
            addOperationOnQueue { [weak self] in self?.pendingDataRequests[request.id] = request }
            return true
        } else {
            return false
        }
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }
            guard let key = pendingDataRequests.first(where: { $1.loadingRequest == loadingRequest })?.key else { return }

            pendingDataRequests[key]?.cancelTask()
            pendingDataRequests.removeValue(forKey: key)
        }
    }

    // MARK: URLSessionDelegate

    func urlSession(_ session: URLSession,
                    dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard fullMediaFileDownloadTask?.taskIdentifier == dataTask.taskIdentifier else {
            completionHandler(.allow)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.allow)
            return
        }

        let statusCode = httpResponse.statusCode
        let expectedStart = fullDownloadExpectedStart
        let contentRangeStart = parseContentRangeStart(from: httpResponse)
        let start = contentRangeStart ?? -1

        if expectedStart > 0 {
            let isValidRangeResponse = statusCode == 206 && start == expectedStart
            guard isValidRangeResponse else {
                resetFullDownloadState()
                dataTask.cancel()
                startFileDownload(with: url)
                completionHandler(.cancel)
                return
            }
        } else if statusCode == 206 && start != 0 {
            resetFullDownloadState()
            dataTask.cancel()
            startFileDownload(with: url)
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            pendingDataRequests[dataTask.taskIdentifier]?.respond(withRemoteData: data)
        }

        if fullMediaFileDownloadTask?.taskIdentifier == dataTask.taskIdentifier {
            bufferData.append(data)
            writeBufferDataToFileIfNeeded()

            guard let response = contentInfoResponse ?? dataTask.response else { return }

            DispatchQueue.main.async {
                self.owner?.delegate?.playerItem?(self.owner!,
                                                  didDownloadBytesSoFar: self.fileHandle.fileSize + self.bufferData.count,
                                                  outOf: Int(response.processedInfoData.expectedContentLength))
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            let taskId = task.taskIdentifier
            
            if let error {
                guard (error as? URLError)?.code != .cancelled else { return }

                if pendingContentInfoRequest?.id == taskId {
                    if shouldRetry(error: error),
                       contentInfoRetryCount < maxContentInfoRetries,
                       pendingContentInfoRequest?.isCancelled == false {
                        contentInfoRetryCount += 1
                        let delay = retryDelay(for: contentInfoRetryCount)
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                            self?.addOperationOnQueue { [weak self] in
                                guard let self, let request = self.pendingContentInfoRequest, request.isCancelled == false else { return }
                                request.startTask()
                            }
                        }
                        return
                    }

                    finishLoadingPendingContentInfoRequests(error: error)
                    downloadFailed(with: error)
                } else if fullMediaFileDownloadTask?.taskIdentifier == taskId {
                    if shouldRetry(error: error), fullDownloadRetryCount < maxFullDownloadRetries {
                        writeBufferDataToFileIfNeeded(forced: true)
                        fullDownloadRetryCount += 1
                        isRetryingFullDownload = true
                        let delay = retryDelay(for: fullDownloadRetryCount)
                        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self else { return }
                            self.startFileDownload(with: self.url, resetRetryCount: false)
                        }
                        return
                    }

                    downloadFailed(with: error)
                }  else {
                    finishLoadingPendingRequest(withId: taskId, error: error)
                }

                return
            }

            if let response = task.response, pendingContentInfoRequest?.id == taskId {
                if pendingContentInfoRequest?.retryWithRangeIfNeeded(response: response) == true {
                    return
                }

                let insufficientDiskSpaceError = checkAvailableDiskSpaceIfNeeded(response: response)
                guard insufficientDiskSpaceError == nil else {
                    downloadFailed(with: insufficientDiskSpaceError!)
                    return
                }

                fillInContentInformationRequests(response: response)
                finishLoadingPendingContentInfoRequests()
                contentInfoResponse = response
                contentInfoRetryCount = 0
            } else {
                finishLoadingPendingRequest(withId: taskId)
            }

            guard fullMediaFileDownloadTask?.taskIdentifier == taskId else { return }

            if bufferData.count > 0 {
                writeBufferDataToFileIfNeeded(forced: true)
            }

            if contentInfoResponse == nil, let response = task.response {
                contentInfoResponse = response
            }

            let error = verify(response: contentInfoResponse ?? task.response)

            guard error == nil else {
                downloadFailed(with: error!)
                return
            }

            fullDownloadRetryCount = 0
            isRetryingFullDownload = false
            downloadComplete()
        }
    }

    // MARK: Internal methods

    func startFileDownload(with url: URL, resetRetryCount: Bool = true) {
        if resetRetryCount {
            fullDownloadRetryCount = 0
            isRetryingFullDownload = false
        } else {
            isRetryingFullDownload = true
        }

        writeBufferDataToFileIfNeeded(forced: true)
        let existingSize = fileHandle.fileSize
        fullDownloadWriteOffset = existingSize
        fullDownloadExpectedStart = existingSize

        fullMediaFileDownloadTask?.cancel()
        ensureSession()

        var urlRequest = URLRequest(url: url)
        owner?.urlRequestHeaders?.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }
        if existingSize > 0 {
            urlRequest.setValue("bytes=\(existingSize)-", forHTTPHeaderField: "Range")
        }

        fullMediaFileDownloadTask = session?.dataTask(with: urlRequest)
        fullMediaFileDownloadTask?.resume()
    }

    func invalidateAndCancelSession(shouldResetData: Bool = true) {
        session?.invalidateAndCancel()
        session = nil
        fullMediaFileDownloadTask = nil
        operationQueue.cancelAllOperations()

        if shouldResetData {
            lock.lock()
            bufferData = Data()
            lock.unlock()
            fullDownloadWriteOffset = 0
            fullDownloadExpectedStart = 0
            fullDownloadRetryCount = 0
            isRetryingFullDownload = false
            contentInfoRetryCount = 0
            addOperationOnQueue { [weak self] in
                guard let self else { return }

                pendingContentInfoRequest = nil
                pendingContentInfoLoadingRequests.removeAll()
                pendingDataRequests.removeAll()
            }
        }

        // We need to only remove the file if it hasn't been fully downloaded
        guard isDownloadComplete == false else { return }

        fileHandle.deleteFile()
    }

    // MARK: Private methods

    private func createURLSession() {
        guard session == nil else {
            assertionFailure("Session already created.")
            return
        }
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldUsePipelining = false
        configuration.httpMaximumConnectionsPerHost = 3
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    private func ensureSession() {
        if session == nil {
            createURLSession()
        }
    }

    private func finishLoadingPendingRequest(withId id: PendingRequestId, error: Error? = nil) {
        if pendingContentInfoRequest?.id == id {
            finishLoadingPendingContentInfoRequests(error: error)
        } else if pendingDataRequests[id] != nil {
            pendingDataRequests[id]?.finishLoading(with: error)
            pendingDataRequests.removeValue(forKey: id)
        }
    }

    private func fillInContentInformationRequest(for loadingRequest: AVAssetResourceLoadingRequest, response: URLResponse) {
        guard let contentInformationRequest = loadingRequest.contentInformationRequest else { return }

        contentInformationRequest.contentType = response.processedInfoData.mimeType
        contentInformationRequest.contentLength = response.processedInfoData.expectedContentLength
        contentInformationRequest.isByteRangeAccessSupported = response.processedInfoData.isByteRangeAccessSupported
    }

    private func fillInContentInformationRequests(response: URLResponse) {
        pendingContentInfoLoadingRequests.forEach { loadingRequest in
            fillInContentInformationRequest(for: loadingRequest, response: response)
        }
    }

    private func finishLoadingPendingContentInfoRequests(error: Error? = nil) {
        pendingContentInfoLoadingRequests.forEach { loadingRequest in
            if let error {
                loadingRequest.finishLoading(with: error)
            } else {
                loadingRequest.finishLoading()
            }
        }

        pendingContentInfoLoadingRequests.removeAll()
        pendingContentInfoRequest = nil
    }

    private func parseContentRangeStart(from response: HTTPURLResponse) -> Int? {
        let contentRange = response.allHeaderFields.first { key, _ in
            (key as? String)?.lowercased() == "content-range"
        }?.value as? String

        guard let contentRange else { return nil }
        let trimmed = contentRange.trimmingCharacters(in: .whitespacesAndNewlines)
        let rangePart = trimmed.split(separator: " ").last ?? Substring(trimmed)
        let normalizedRange = rangePart.hasPrefix("bytes=") ? rangePart.dropFirst("bytes=".count) : rangePart
        guard let startPart = normalizedRange.split(separator: "-").first else { return nil }
        return Int(String(startPart))
    }

    private func resetFullDownloadState() {
        lock.lock()
        bufferData = Data()
        lock.unlock()
        fileHandle.truncate(to: 0)
        fullDownloadWriteOffset = 0
        fullDownloadExpectedStart = 0
        fullDownloadRetryCount = 0
        isRetryingFullDownload = false
    }

    private func retryDelay(for retryCount: Int) -> TimeInterval {
        retryDelayBase * pow(2.0, Double(retryCount - 1))
    }

    private func shouldRetry(error: Error) -> Bool {
        (error as? URLError)?.code != .cancelled
    }

    private func writeBufferDataToFileIfNeeded(forced: Bool = false) {
        lock.lock()
        defer { lock.unlock() }

        guard bufferData.count >= configuration.downloadBufferLimit || forced else { return }

        guard bufferData.isEmpty == false else { return }

        fileHandle.write(data: bufferData, at: fullDownloadWriteOffset)
        fullDownloadWriteOffset += bufferData.count
        bufferData = Data()
    }

    private func downloadComplete() {
        isDownloadComplete = true

        DispatchQueue.main.async {
            self.owner?.delegate?.playerItem?(self.owner!, didFinishDownloadingFileAt: self.saveFilePath)
        }
    }

    private func verify(response: URLResponse?) -> NSError? {
        guard let response = response as? HTTPURLResponse else { return nil }

        let shouldVerifyDownloadedFileSize = configuration.shouldVerifyDownloadedFileSize
        let minimumExpectedFileSize = configuration.minimumExpectedFileSize
        var error: NSError?

        if response.statusCode >= 400 {
            error = NSError(domain: "Failed downloading asset. Reason: response status code \(response.statusCode).", code: response.statusCode, userInfo: nil)
        } else if shouldVerifyDownloadedFileSize && response.processedInfoData.expectedContentLength != -1 && response.processedInfoData.expectedContentLength != fileHandle.fileSize {
            error = NSError(domain: "Failed downloading asset. Reason: wrong file size, expected: \(response.expectedContentLength), actual: \(fileHandle.fileSize).", code: response.statusCode, userInfo: nil)
        } else if minimumExpectedFileSize > 0 && minimumExpectedFileSize > fileHandle.fileSize {
            error = NSError(domain: "Failed downloading asset. Reason: file size \(fileHandle.fileSize) is smaller than minimumExpectedFileSize", code: response.statusCode, userInfo: nil)
        }

        return error
    }

    private func checkAvailableDiskSpaceIfNeeded(response: URLResponse) -> NSError? {
        guard
            configuration.shouldCheckAvailableDiskSpaceBeforeCaching,
            let response = response as? HTTPURLResponse,
            let freeDiskSpace = fileHandle.freeDiskSpace
        else { return nil }

        if freeDiskSpace < response.processedInfoData.expectedContentLength {
            return NSError(domain: "Failed downloading asset. Reason: insufficient disk space available.", code: NSFileWriteOutOfSpaceError, userInfo: nil)
        }

        return nil
    }

    private func downloadFailed(with error: Error) {
        invalidateAndCancelSession()

        DispatchQueue.main.async {
            self.owner?.delegate?.playerItem?(self.owner!, downloadingFailedWith: error)
        }
    }

    private func addOperationOnQueue(_ block: @escaping () -> Void) {
        let blockOperation = BlockOperation()
        blockOperation.addExecutionBlock({ [unowned blockOperation] in
            guard blockOperation.isCancelled == false else { return }

            block()
        })
        operationQueue.addOperation(blockOperation)
    }

    @objc private func handleAppWillTerminate() {
        invalidateAndCancelSession(shouldResetData: false)
    }
}

// MARK: PendingDataRequestDelegate

extension ResourceLoaderDelegate: PendingDataRequestDelegate {
    func pendingDataRequest(_ request: PendingDataRequest, hasSufficientCachedDataFor offset: Int, with length: Int) -> Bool {
        if configuration.allowsUncachedSeek {
            // Request remote data temporarily if the requested data is not yet cached
            return fileHandle.fileSize >= length + offset
        } else {
            // Always request cached data
            return true
        }
    }

    func pendingDataRequest(_ request: PendingDataRequest,
                            requestCachedDataFor offset: Int,
                            with length: Int,
                            completion: @escaping ((_ continueRequesting: Bool) -> Void)) {
        addOperationOnQueue { [weak self] in
            guard let self else { return }

            let bytesCached = fileHandle.fileSize
            // Data length to be loaded into memory with maximum size of readDataLimit.
            let bytesToRespond = min(bytesCached - offset, length, configuration.readDataLimit)
            // Read data from disk and pass it to the dataRequest
            guard let data = fileHandle.readData(withOffset: offset, forLength: bytesToRespond) else {
                finishLoadingPendingRequest(withId: request.id)
                completion(false)
                return
            }

            request.respond(withCachedData: data)

            if data.count >= length {
                finishLoadingPendingRequest(withId: request.id)
                completion(false)
            } else {
                completion(true)
            }
        }
    }
}

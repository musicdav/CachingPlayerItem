//
//  PendingRequest.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation

/// Abstract class with properties required for processing `AVAssetResourceLoadingRequest`.
class PendingRequest {
    /// URLSession task identifier.
    fileprivate(set) var id = -1
    private let url: URL
    private let customHeaders: [String: String]?
    fileprivate var task: URLSessionTask?
    private var didCancelTask = false
    fileprivate unowned var session: URLSession
    let loadingRequest: AVAssetResourceLoadingRequest
    var isCancelled: Bool { loadingRequest.isCancelled || didCancelTask }

    init(url: URL, session: URLSession, loadingRequest: AVAssetResourceLoadingRequest, customHeaders: [String: String]?) {
        self.url = url
        self.session = session
        self.loadingRequest = loadingRequest
        self.customHeaders = customHeaders
    }

    /// Creates an URLRequest with the required headers for bytes range and customHeaders set.
    fileprivate func makeURLRequest() -> URLRequest {
        var request = URLRequest(url: url)

        if let dataRequest = loadingRequest.dataRequest {
            let lowerBound = Int(dataRequest.requestedOffset)
            let upperBound = lowerBound + Int(dataRequest.requestedLength) - 1
            let rangeHeader = "bytes=\(lowerBound)-\(upperBound)"
            request.setValue(rangeHeader, forHTTPHeaderField: "Range")
        }

        if let headers = customHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    fileprivate func makeSessionTask(with request: URLRequest) -> URLSessionTask {
        fatalError("Subclasses need to implement the `makeSessionTask()` method.")
    }

    /// Creates the session task with `makeSessionTask` from subclass. `id` gets assigned with the task id when invoking this method.
    func startTask() {
        let request = makeURLRequest()
        let task = makeSessionTask(with: request)
        id = task.taskIdentifier
        self.task = task
        task.resume()
    }

    func cancelTask() {
        task?.cancel()

        if !loadingRequest.isCancelled && !loadingRequest.isFinished {
            finishLoading()
        }

        didCancelTask = true
    }

    func finishLoading(with error: Error? = nil) {
        if let error {
            loadingRequest.finishLoading(with: error)
        } else {
            loadingRequest.finishLoading()
        }
    }
}

// MARK: PendingContentInfoRequest

/// Wrapper for handling `AVAssetResourceLoadingContentInformationRequest`.
class PendingContentInfoRequest: PendingRequest {
    private enum RequestKind {
        case head
        case rangeFallback
    }

    private var requestKind: RequestKind = .head
    private var didFallback = false

    private var contentInformationRequest: AVAssetResourceLoadingContentInformationRequest {
        loadingRequest.contentInformationRequest!
    }

    override func makeSessionTask(with request: URLRequest) -> URLSessionTask {
        session.dataTask(with: request)
    }

    override func startTask() {
        startTask(using: requestKind)
    }

    func retryWithRangeIfNeeded(response: URLResponse?) -> Bool {
        guard !didFallback else { return false }
        guard let response = response as? HTTPURLResponse else { return false }

        let statusCode = response.statusCode
        let needsFallback = statusCode >= 400 || response.processedInfoData.expectedContentLength == -1
        guard needsFallback else { return false }

        didFallback = true
        requestKind = .rangeFallback
        startTask(using: requestKind)
        return true
    }

    private func startTask(using kind: RequestKind) {
        var request = makeURLRequest()
        switch kind {
        case .head:
            request.httpMethod = "HEAD"
        case .rangeFallback:
            request.httpMethod = "GET"
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        }

        let task = makeSessionTask(with: request)
        id = task.taskIdentifier
        self.task = task
        task.resume()
    }

    func fillInContentInformationRequest(with response: URLResponse) {
        contentInformationRequest.contentType = response.processedInfoData.mimeType
        contentInformationRequest.contentLength = response.processedInfoData.expectedContentLength
        contentInformationRequest.isByteRangeAccessSupported = response.processedInfoData.isByteRangeAccessSupported
    }
}

// MARK: PendingDataRequest

/// Result of requesting cached data.
enum CachedDataRequestResult {
    /// All requested data has been provided, request is complete.
    case finished
    /// More data is available, continue requesting.
    case continueRequesting
    /// Not enough data available yet, wait for more data to be written to disk.
    case waitForMoreData
}

/// Cached data request delegate.
protocol PendingDataRequestDelegate: AnyObject {
    /// Requests cached data from disk. The returned `offset` and `length` are increased/reduced based on the data passed in `respond(withCachedData:)`.
    /// Returns a result indicating whether to continue, finish, or wait for more data.
    func pendingDataRequest(_ request: PendingDataRequest,
                            requestCachedDataFor offset: Int,
                            with length: Int,
                            completion: @escaping ((_ result: CachedDataRequestResult) -> Void))
}

/// Wrapper for handling  `AVAssetResourceLoadingDataRequest`.
/// This class only reads from disk cache - it never makes network requests.
/// When requested data is not yet available on disk, it waits for notification.
class PendingDataRequest: PendingRequest {
    private var dataRequest: AVAssetResourceLoadingDataRequest { loadingRequest.dataRequest! }
    private lazy var requestedLength = dataRequest.requestedLength
    private lazy var fileDataOffset = Int(dataRequest.requestedOffset)
    weak var delegate: PendingDataRequestDelegate?
    
    /// Indicates whether this request is waiting for more data to be written to disk.
    private(set) var isWaitingForData = false

    override func startTask() {
        // Always use cached data path - never make network requests
        requestCachedData()
    }

    func respond(withCachedData data: Data) {
        dataRequest.respond(with: data)
        fileDataOffset += data.count
        requestedLength -= data.count
    }
    
    /// Called when more data has been written to disk. Retries reading if this request was waiting.
    func retryWithCachedData() {
        guard isWaitingForData else { return }
        isWaitingForData = false
        requestCachedData()
    }

    /// Requests cached data recursively until finished or needs to wait.
    private func requestCachedData() {
        guard let delegate else { return }

        delegate.pendingDataRequest(
            self,
            requestCachedDataFor: fileDataOffset,
            with: requestedLength,
            completion: { [weak self] result in
                switch result {
                case .finished:
                    break // Request complete
                case .continueRequesting:
                    self?.requestCachedData()
                case .waitForMoreData:
                    self?.isWaitingForData = true
                }
        })
    }
}

//
//  CachingPlayerItem.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation

/// Convenient delegate methods for `CachingPlayerItem` status updates.
@objc public protocol CachingPlayerItemDelegate {
    // MARK: Downloading delegate methods

    /// Called when the media file is fully downloaded.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String)

    /// Called every time a new portion of data is received.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int)

    /// Called on downloading error.
    @objc optional func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error)

    // MARK: Playing delegate methods

    /// Called after initial prebuffering is finished, means we are ready to play.
    @objc optional func playerItemReadyToPlay(_ playerItem: CachingPlayerItem)

    /// Called when the player is unable to play the data/url.
    @objc optional func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?)

    /// Called when the data being downloaded did not arrive in time to continue playback.
    @objc optional func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem)
}

/// AVPlayerItem subclass that supports caching while playing.
public final class CachingPlayerItem: AVPlayerItem {
    private let cachingPlayerItemScheme = "cachingPlayerItemScheme"

    private lazy var resourceLoaderDelegate = ResourceLoaderDelegate(
        url: url,
        saveFilePath: saveFilePath,
        owner: self,
        bitrateKbps: bitrateKbps,
        durationSeconds: durationSeconds
    )
    private let url: URL
    private let initialScheme: String?
    private let saveFilePath: String
    private let customFileExtension: String?
    internal let configuration: CachingPlayerItemConfiguration
    /// HTTPHeaderFields set in avUrlAssetOptions using AVURLAssetHTTPHeaderFieldsKey
    internal var urlRequestHeaders: [String: String]?
    
    /// Bitrate in kbps for transcoded streams. Used to estimate content length when not provided by server.
    internal let bitrateKbps: Double?
    /// Duration in seconds. Used together with bitrateKbps to estimate content length.
    internal let durationSeconds: Double?

    /// Useful for keeping relevant model associated with CachingPlayerItem instance. This is a **strong** reference, be mindful not to create a **retain cycle**.
    public var passOnObject: Any?
    /// Indicates whether media content is currently being cached to disk. Returns `false` for initializers that don't support caching.
    public var isCaching: Bool {
        initialScheme != nil && !resourceLoaderDelegate.isDownloadComplete
    }
    /// `delegate` for status updates.
    public weak var delegate: CachingPlayerItemDelegate?

    // MARK: Public init

    /**
     Play and cache remote media on a local file. `saveFilePath` is **randomly** generated. Requires `url.pathExtension` to not be empty otherwise the player will fail playing.

     - parameter url: URL referencing the media file.
     */
    public convenience init(url: URL) {
        self.init(url: url, saveFilePath: Self.randomFilePath(withExtension: url.pathExtension), customFileExtension: nil, avUrlAssetOptions: nil, bitrateKbps: nil, durationSeconds: nil)
    }

    /**
     Play and cache remote media on a local file. `saveFilePath` is **randomly** generated. Requires `url.pathExtension` to not be empty otherwise the player will fail playing.

     - parameter url: URL referencing the media file.

     - parameter avUrlAssetOptions: A dictionary that contains options used to customize the initialization of the asset. For supported keys and values,

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.
     see [Initialization Options.](https://developer.apple.com/documentation/avfoundation/avurlasset/initialization_options)
     */
    public convenience init(url: URL, avUrlAssetOptions: [String: Any]? = nil, configuration: CachingPlayerItemConfiguration = .default, bitrateKbps: Double? = nil, durationSeconds: Double? = nil) {
        self.init(url: url, saveFilePath: Self.randomFilePath(withExtension: url.pathExtension), customFileExtension: nil, avUrlAssetOptions: avUrlAssetOptions, configuration: configuration, bitrateKbps: bitrateKbps, durationSeconds: durationSeconds)
    }

    /**
     Play and cache remote media on a local file. `saveFilePath` is **randomly** generated.

     - parameter url: URL referencing the media file.

     - parameter customFileExtension: Media file extension. E.g. mp4, mp3. This is required for the player to work correctly with the intended file type.

     - parameter avUrlAssetOptions: A dictionary that contains options used to customize the initialization of the asset. For supported keys and values,
     see [Initialization Options.](https://developer.apple.com/documentation/avfoundation/avurlasset/initialization_options)

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.
     */
    public convenience init(url: URL, customFileExtension: String, avUrlAssetOptions: [String: Any]? = nil, configuration: CachingPlayerItemConfiguration = .default, bitrateKbps: Double? = nil, durationSeconds: Double? = nil) {
        self.init(url: url, saveFilePath: Self.randomFilePath(withExtension: customFileExtension), customFileExtension: customFileExtension, avUrlAssetOptions: avUrlAssetOptions, configuration: configuration, bitrateKbps: bitrateKbps, durationSeconds: durationSeconds)
    }

    /**
     Play and cache remote media.

     - parameter url: URL referencing the media file.

     - parameter saveFilePath: The desired local save location. E.g. "video.mp4". **Must** be a unique file path that doesn't already exist. If a file exists at the path than it's **required** to be empty (contain no data).

     - parameter customFileExtension: Media file extension. E.g. mp4, mp3. This is required for the player to work correctly with the intended file type.

     - parameter avUrlAssetOptions: A dictionary that contains options used to customize the initialization of the asset. For supported keys and values,
     see [Initialization Options.](https://developer.apple.com/documentation/avfoundation/avurlasset/initialization_options)

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.
     */
    public init(url: URL,
                saveFilePath: String,
                customFileExtension: String?,
                avUrlAssetOptions: [String: Any]? = nil,
                configuration: CachingPlayerItemConfiguration = .default,
                bitrateKbps: Double? = nil,
                durationSeconds: Double? = nil) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme,
              var urlWithCustomScheme = url.withScheme(cachingPlayerItemScheme) else {
            fatalError("CachingPlayerItem error: Urls without a scheme are not supported")
        }

        self.url = url
        self.saveFilePath = saveFilePath
        self.initialScheme = scheme
        self.configuration = configuration
        self.bitrateKbps = bitrateKbps
        self.durationSeconds = durationSeconds

        if let ext = customFileExtension {
            urlWithCustomScheme.deletePathExtension()
            urlWithCustomScheme.appendPathExtension(ext)
            self.customFileExtension = ext
        }  else {
            self.customFileExtension = nil
            assert(url.pathExtension.isEmpty == false, "CachingPlayerItem error: url pathExtension empty, pass the extension in `customFileExtension` parameter")
        }

        if let headers = avUrlAssetOptions?["AVURLAssetHTTPHeaderFieldsKey"] as? [String: String] {
            self.urlRequestHeaders = headers
        }

        let asset = AVURLAsset(url: urlWithCustomScheme, options: avUrlAssetOptions)
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)

        asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: DispatchQueue.main)

        addObservers()
    }

    /**
     Play remote media **without** caching.

     - parameter nonCachingURL: URL referencing the media file.

     - parameter avUrlAssetOptions: A dictionary that contains options used to customize the initialization of the asset. For supported keys and values,
     see [Initialization Options.](https://developer.apple.com/documentation/avfoundation/avurlasset/initialization_options)

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.
     */
    public init(nonCachingURL url: URL, avUrlAssetOptions: [String: Any]? = nil, configuration: CachingPlayerItemConfiguration = .default) {
        self.url = url
        self.saveFilePath = ""
        self.initialScheme = nil
        self.customFileExtension = nil
        self.configuration = configuration
        self.bitrateKbps = nil
        self.durationSeconds = nil

        let asset = AVURLAsset(url: url, options: avUrlAssetOptions)
        super.init(asset: asset, automaticallyLoadedAssetKeys: nil)

        addObservers()
    }

    /**
     Play from data.

     - parameter data: Media file represented in data.

     - parameter customFileExtension: Media file extension. E.g. mp4, mp3. This is required for the player to work correctly with the intended file type.

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.

     - throws: An error in the Cocoa domain, if there is an error writing to the `URL`.
     */
    public convenience init(data: Data, customFileExtension: String, configuration: CachingPlayerItemConfiguration = .default) throws {
        let filePathURL = URL(fileURLWithPath: Self.randomFilePath(withExtension: customFileExtension))
        FileManager.default.createFile(atPath: filePathURL.path, contents: nil, attributes: nil)
        try data.write(to: filePathURL)
        self.init(filePathURL: filePathURL, configuration: configuration)
    }

    /**
     Play from file.

     - parameter filePathURL: The local file path of a media file.

     - parameter fileExtension: Media file extension. E.g. mp4, mp3. **Required**  if `filePathURL.pathExtension` is empty.

     - parameter configuration: Configuration for the caching and downloading behavior. Defaults to `.default`.
    */
    public init(filePathURL: URL, fileExtension: String? = nil, configuration: CachingPlayerItemConfiguration = .default) {
        if let fileExtension = fileExtension {
            let desiredExtension = fileExtension
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                .lowercased()
            let currentExtension = filePathURL.pathExtension.lowercased()

            if desiredExtension.isEmpty || currentExtension == desiredExtension {
                self.url = filePathURL
            } else {
                let playbackURL = filePathURL.appendingPathExtension(desiredExtension)

                let values = try? playbackURL.resourceValues(forKeys: [.isSymbolicLinkKey])
                if values?.isSymbolicLink == true {
                    try? FileManager.default.removeItem(at: playbackURL)
                }

                if !FileManager.default.fileExists(atPath: playbackURL.path) {
                    do {
                        try FileManager.default.createSymbolicLink(at: playbackURL, withDestinationURL: filePathURL)
                        self.url = playbackURL
                    } catch {
                        self.url = filePathURL
                    }
                } else {
                    self.url = filePathURL
                }
            }
        } else {
            assert(filePathURL.pathExtension.isEmpty == false,
                   "CachingPlayerItem error: filePathURL pathExtension empty, pass the extension in `fileExtension` parameter")
            self.url = filePathURL
        }

        // Not needed properties when playing media from a local file.
        self.saveFilePath = ""
        self.initialScheme = nil
        self.customFileExtension = nil
        self.configuration = configuration
        self.bitrateKbps = nil
        self.durationSeconds = nil

        super.init(asset: AVURLAsset(url: url), automaticallyLoadedAssetKeys: nil)

        addObservers()
    }

    /**
     Play media using an AVAsset. Caching is **not** supported for this method.

     - parameter asset: An instance of AVAsset.
     - parameter automaticallyLoadedAssetKeys: An NSArray of NSStrings, each representing a property key defined by AVAsset.
     */
    override public init(asset: AVAsset, automaticallyLoadedAssetKeys: [String]?) {
        self.url = URL(fileURLWithPath: "")
        self.initialScheme = nil
        self.saveFilePath = ""
        self.customFileExtension = nil
        self.configuration = .default
        self.bitrateKbps = nil
        self.durationSeconds = nil
        super.init(asset: asset, automaticallyLoadedAssetKeys: automaticallyLoadedAssetKeys)

        addObservers()
    }

    // MARK: Cache-aware factory method

    /**
     Play from cache if a complete file exists, otherwise download fresh.

     On first download, a `.meta` sidecar file is automatically created alongside the
     cached media file recording its size. On subsequent calls, this method reads the
     `.meta` file and compares it with the actual file size to determine completeness.

     - If both the media file and `.meta` exist, and the file size matches → plays from local.
     - If the file is incomplete or `.meta` is missing → **deletes** any partial file and re-downloads.

     - parameter url: Remote media URL.
     - parameter saveFilePath: A **stable, deterministic** file path for caching (e.g. based on URL hash).
     - parameter customFileExtension: Media file extension. E.g. mp3, m4a.
     - parameter avUrlAssetOptions: AVURLAsset initialization options.
     - parameter configuration: Caching/downloading configuration.
     - parameter bitrateKbps: Bitrate in kbps for transcoded streams.
     - parameter durationSeconds: Duration in seconds.
     */
    public static func withCacheCheck(
        url: URL,
        saveFilePath: String,
        customFileExtension: String? = nil,
        avUrlAssetOptions: [String: Any]? = nil,
        configuration: CachingPlayerItemConfiguration = .default,
        bitrateKbps: Double? = nil,
        durationSeconds: Double? = nil
    ) -> CachingPlayerItem {
        let fileManager = FileManager.default
        let metaPath = saveFilePath + ".meta"

        if fileManager.fileExists(atPath: saveFilePath),
           fileManager.fileExists(atPath: metaPath),
           let metaContent = try? String(contentsOfFile: metaPath, encoding: .utf8) {
            let lines = metaContent.components(separatedBy: "\n")
            if let sizeLine = lines.first,
               let expectedSize = Int64(sizeLine.trimmingCharacters(in: .whitespacesAndNewlines)),
               expectedSize > 0 {
                let fileSize = (try? fileManager.attributesOfItem(atPath: saveFilePath))?[.size] as? Int64 ?? 0

                if fileSize >= expectedSize {
                    // Determine correct file extension from cached MIME type
                    let cachedMime = lines.count > 1 ? lines[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
                    let resolvedExtension = fileExtension(fromMime: cachedMime) ?? customFileExtension

                    AppLogger.info("Cache hit: \(saveFilePath) (size: \(fileSize), expected: \(expectedSize), mime: \(cachedMime ?? "nil"), ext: \(resolvedExtension ?? "nil"))")
                    let fileURL = URL(fileURLWithPath: saveFilePath)
                    return CachingPlayerItem(
                        filePathURL: fileURL,
                        fileExtension: resolvedExtension,
                        configuration: configuration
                    )
                }
            }
        }

        // Cache miss or incomplete — delete everything and re-download
        AppLogger.info("Cache miss: \(saveFilePath), downloading from \(url)")
        try? fileManager.removeItem(atPath: saveFilePath)
        try? fileManager.removeItem(atPath: metaPath)

        // Ensure parent directory exists
        let directory = (saveFilePath as NSString).deletingLastPathComponent
        if !fileManager.fileExists(atPath: directory) {
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        }

        return CachingPlayerItem(
            url: url,
            saveFilePath: saveFilePath,
            customFileExtension: customFileExtension,
            avUrlAssetOptions: avUrlAssetOptions,
            configuration: configuration,
            bitrateKbps: bitrateKbps,
            durationSeconds: durationSeconds
        )
    }

    /// Maps HTTP MIME type to file extension for AVFoundation playback.
    private static func fileExtension(fromMime mime: String?) -> String? {
        guard let mime = mime?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !mime.isEmpty, mime != "unknown" else {
            return nil
        }

        switch mime {
        case "audio/mpeg", "audio/mp3", "audio/mpeg3", "audio/x-mpeg", "audio/x-mp3":
            return "mp3"
        case "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/aac", "audio/aacp", "audio/x-aac":
            return "m4a"
        case "audio/flac", "audio/x-flac":
            return "flac"
        case "audio/wav", "audio/x-wav", "audio/wave", "audio/vnd.wave":
            return "wav"
        case "audio/aiff", "audio/x-aiff":
            return "aiff"
        case "audio/ogg":
            return "ogg"
        case "audio/opus":
            return "opus"
        default:
            // Try extracting subtype as fallback: "audio/xyz" → "xyz"
            if mime.hasPrefix("audio/") {
                let subtype = String(mime.dropFirst("audio/".count))
                if !subtype.isEmpty, !subtype.contains("/") {
                    return subtype
                }
            }
            return nil
        }
    }

    deinit {
        removeObservers()

        // Cancel download only for caching inits
        guard initialScheme != nil else { return }

        // Otherwise the ResourceLoaderDelegate wont deallocate and will keep downloading.
        resourceLoaderDelegate.invalidateAndCancelSession(shouldResetData: false)
    }

    // MARK: Public methods

    /// Downloads the media file. Works only with the initializers intended for play and cache.
    public func download() {
        // Make sure we are not initilalized with a filePath or non-caching init.
        guard initialScheme != nil else {
            assertionFailure("CachingPlayerItem error: `download` method used on a non caching instance")
            return
        }

        resourceLoaderDelegate.startFileDownload(with: url)
    }

    /// Cancels the download of the media file and deletes the incomplete cached file. Works only with the initializers intended for play and cache.
    public func cancelDownload() {
        // Make sure we are not initilalized with a filePath or non-caching init.
        guard initialScheme != nil else {
            assertionFailure("CachingPlayerItem error: `cancelDownload` method used on a non caching instance")
            return
        }

        resourceLoaderDelegate.invalidateAndCancelSession()
    }

    // MARK: KVO

    private var playerItemContext = 0

    public override func observeValue(forKeyPath keyPath: String?,
                                      of object: Any?,
                                      change: [NSKeyValueChangeKey : Any]?,
                                      context: UnsafeMutableRawPointer?) {

        // Only handle observations for the playerItemContext
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath,
                               of: object,
                               change: change,
                               context: context)
            return
        }

        // We are only observing the status keypath
        guard keyPath == #keyPath(AVPlayerItem.status) else { return }

        let status: AVPlayerItem.Status
        if let statusNumber = change?[.newKey] as? NSNumber {
            status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
        } else {
            status = .unknown
        }

        // Switch over status value
        switch status {
        case .readyToPlay:
            // Player item is ready to play.
            AppLogger.info("CachingPlayerItem status: ready to play")
            DispatchQueue.main.async { self.delegate?.playerItemReadyToPlay?(self) }
        case .failed:
            // Player item failed. See error.
            AppLogger.error("CachingPlayerItem status: failed with error: \(String(describing: error))")
            DispatchQueue.main.async { self.delegate?.playerItemDidFailToPlay?(self, withError: self.error) }
        case .unknown:
            // Player item is not yet ready.
            AppLogger.error("CachingPlayerItem status: uknown with error: \(String(describing: error))")
        @unknown default:
            break
        }
    }

    // MARK: Private methods

    private func addObservers() {
        addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: .new, context: &playerItemContext)
        NotificationCenter.default.addObserver(self, selector: #selector(playbackStalledHandler), name: .AVPlayerItemPlaybackStalled, object: self)
    }

    private func removeObservers() {
        removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func playbackStalledHandler() {
        DispatchQueue.main.async { self.delegate?.playerItemPlaybackStalled?(self) }
    }

    /// Generates a random file path in caches directory with the provided `fileExtension`.
    private static func randomFilePath(withExtension fileExtension: String) -> String {
        guard var cachesDirectory = try? FileManager.default.url(for: .cachesDirectory,
                                                                 in: .userDomainMask,
                                                                 appropriateFor: nil,
                                                                 create: true)
        else {
            fatalError("CachingPlayerItem error: Can't access default cache directory")
        }

        cachesDirectory.appendPathComponent(UUID().uuidString)
        cachesDirectory.appendPathExtension(fileExtension)

        return cachesDirectory.path
    }
}

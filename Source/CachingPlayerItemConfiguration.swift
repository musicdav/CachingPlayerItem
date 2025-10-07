//
//  CachingPlayerItemConfiguration.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation

/// CachingPlayerItem global configuration.
public struct CachingPlayerItemConfiguration {
    /// How much data is downloaded in memory before stored on a file. Defaults to `128.KB`.
    @available(*, deprecated, renamed: "default.downloadBufferLimit")
    public static var downloadBufferLimit: Int {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: newValue,
                readDataLimit: Self.default.readDataLimit,
                shouldVerifyDownloadedFileSize: Self.default.shouldVerifyDownloadedFileSize,
                minimumExpectedFileSize: Self.default.minimumExpectedFileSize,
                shouldCheckAvailableDiskSpaceBeforeCaching: Self.default.shouldCheckAvailableDiskSpaceBeforeCaching,
                logLevel: Self.default.logLevel
            )
        }

        get {
            return Self.default.downloadBufferLimit
        }
    }

    /// How much data is allowed to be read in memory at a time. Defaults to `10.MB`.
    @available(*, deprecated, renamed: "default.readDataLimit")
    public static var readDataLimit: Int {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: Self.default.downloadBufferLimit,
                readDataLimit: newValue,
                shouldVerifyDownloadedFileSize: Self.default.shouldVerifyDownloadedFileSize,
                minimumExpectedFileSize: Self.default.minimumExpectedFileSize,
                shouldCheckAvailableDiskSpaceBeforeCaching: Self.default.shouldCheckAvailableDiskSpaceBeforeCaching,
                logLevel: Self.default.logLevel
            )
        }

        get {
            return Self.default.readDataLimit
        }
    }

    /// Flag for deciding whether an error should be thrown when URLResponse's expectedContentLength is not equal with the downloaded media file bytes count. Defaults to `false`.
    @available(*, deprecated, renamed: "default.shouldVerifyDownloadedFileSize")
    public static var shouldVerifyDownloadedFileSize: Bool {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: Self.default.downloadBufferLimit,
                readDataLimit: Self.default.readDataLimit,
                shouldVerifyDownloadedFileSize: newValue,
                minimumExpectedFileSize: Self.default.minimumExpectedFileSize,
                shouldCheckAvailableDiskSpaceBeforeCaching: Self.default.shouldCheckAvailableDiskSpaceBeforeCaching,
                logLevel: Self.default.logLevel
            )
        }

        get {
            return Self.default.shouldVerifyDownloadedFileSize
        }
    }

    /// If set greater than 0, the set value with be compared with the downloaded media size. If the size of the downloaded media is lower, an error will be thrown. Useful when `expectedContentLength` is unavailable.
    /// Default value is `0`.
    @available(*, deprecated, renamed: "default.minimumExpectedFileSize")
    public static var minimumExpectedFileSize: Int {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: Self.default.downloadBufferLimit,
                readDataLimit: Self.default.readDataLimit,
                shouldVerifyDownloadedFileSize: Self.default.shouldVerifyDownloadedFileSize,
                minimumExpectedFileSize: newValue,
                shouldCheckAvailableDiskSpaceBeforeCaching: Self.default.shouldCheckAvailableDiskSpaceBeforeCaching,
                logLevel: Self.default.logLevel
            )
        }

        get {
            return Self.default.minimumExpectedFileSize
        }
    }

    /// Flag for deciding whether an `NSFileWriteOutOfSpaceError` should be thrown when there is not enough available disk space left for caching the entire media file. Defaults to `true`.
    @available(*, deprecated, renamed: "default.shouldCheckAvailableDiskSpaceBeforeCaching")
    public static var shouldCheckAvailableDiskSpaceBeforeCaching: Bool {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: Self.default.downloadBufferLimit,
                readDataLimit: Self.default.readDataLimit,
                shouldVerifyDownloadedFileSize: Self.default.shouldVerifyDownloadedFileSize,
                minimumExpectedFileSize: Self.default.minimumExpectedFileSize,
                shouldCheckAvailableDiskSpaceBeforeCaching: newValue,
                logLevel: Self.default.logLevel
            )
        }

        get {
            return Self.default.shouldCheckAvailableDiskSpaceBeforeCaching
        }
    }

    /// Log level. Defaults to `none`.
    @available(*, deprecated, renamed: "default.logLevel")
    public static var logLevel: LogLevel {
        set {
            Self.default = CachingPlayerItemConfiguration(
                downloadBufferLimit: Self.default.downloadBufferLimit,
                readDataLimit: Self.default.readDataLimit,
                shouldVerifyDownloadedFileSize: Self.default.shouldVerifyDownloadedFileSize,
                minimumExpectedFileSize: Self.default.minimumExpectedFileSize,
                shouldCheckAvailableDiskSpaceBeforeCaching: Self.default.shouldCheckAvailableDiskSpaceBeforeCaching,
                logLevel: newValue
            )
        }

        get {
            return Self.default.logLevel
        }
    }

    /** The default configuration instance used for `CachingPlayerItem` instances.

     Default values:
     - downloadBufferLimit: 128 KB
     - readDataLimit: 10 MB
     - shouldVerifyDownloadedFileSize: false
     - minimumExpectedFileSize: 0
     - shouldCheckAvailableDiskSpaceBeforeCaching: true
     - logLevel: .none
    */
    public static var `default` = CachingPlayerItemConfiguration()

    /// How much data is downloaded in memory before stored on a file.
    public let downloadBufferLimit: Int
    /// How much data is allowed to be read in memory at a time.
    public let readDataLimit: Int
    /// Flag for deciding whether an error should be thrown when URLResponse's expectedContentLength is not equal with the downloaded media file bytes count.
    public let shouldVerifyDownloadedFileSize: Bool
    /// If set greater than 0, the set value with be compared with the downloaded media size. If the size of the downloaded media is lower, an error will be thrown. Useful when `expectedContentLength` is unavailable.
    public let minimumExpectedFileSize: Int
    /// Flag for deciding whether an `NSFileWriteOutOfSpaceError` should be thrown when there is not enough available disk space left for caching the entire media file.
    public let shouldCheckAvailableDiskSpaceBeforeCaching: Bool
    /// Log level.
    public let logLevel: LogLevel

    /**
     Creates a new configuration instance.

     - Parameter downloadBufferLimit: How much data is downloaded in memory before stored on a file. Defaults to 128 KB.
     - Parameter readDataLimit: How much data is allowed to be read in memory at a time. Defaults to 10 MB.
     - Parameter shouldVerifyDownloadedFileSize: Flag for deciding whether an error should be thrown when URLResponse's expectedContentLength is not equal with the downloaded media file bytes count. Defaults to `false`.
     - Parameter minimumExpectedFileSize: If set greater than 0, the set value will be compared with the downloaded media size. If the size of the downloaded media is lower, an error will be thrown. Useful when `expectedContentLength` is unavailable. Defaults to 0.
     - Parameter shouldCheckAvailableDiskSpaceBeforeCaching: Flag for deciding whether an `NSFileWriteOutOfSpaceError` should be thrown when there is not enough available disk space left for caching the entire media file. Defaults to `true`.
     - Parameter logLevel: Log level. Defaults to `.none`.
     */
    public init(
        downloadBufferLimit: Int = 128 * 1024, // 128KB
        readDataLimit: Int = 10 * 1024 * 1024, // 10MB
        shouldVerifyDownloadedFileSize: Bool = false,
        minimumExpectedFileSize: Int = 0,
        shouldCheckAvailableDiskSpaceBeforeCaching: Bool = true,
        logLevel: LogLevel = .none
    ) {
        self.downloadBufferLimit = downloadBufferLimit
        self.readDataLimit = readDataLimit
        self.shouldVerifyDownloadedFileSize = shouldVerifyDownloadedFileSize
        self.minimumExpectedFileSize = minimumExpectedFileSize
        self.shouldCheckAvailableDiskSpaceBeforeCaching = shouldCheckAvailableDiskSpaceBeforeCaching
        self.logLevel = logLevel
    }
}

fileprivate extension Int {
    var KB: Int { return self * 1024 }
    var MB: Int { return self * 1024 * 1024 }
}

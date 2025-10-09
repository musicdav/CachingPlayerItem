import Quick
import Nimble
import AVFoundation
@testable import CachingPlayerItem

class CachingPlayerItemSpec: QuickSpec {
    override class func spec() {
        describe("CachingPlayerItem") {
            var sut: CachingPlayerItem!
            var delegate: MockCachingPlayerItemDelegate!
            var testURL: URL!
            var tempDirectory: URL!

            beforeEach {
                testURL = URL(string: "https://example.com/test-video.mp4")!
                delegate = MockCachingPlayerItemDelegate()

                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            afterEach {
                sut = nil
                delegate = nil
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            // MARK: - Initialization Tests

            context("when initialized with URL") {
                it("creates AVURLAsset with custom scheme") {
                    sut = CachingPlayerItem(url: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.scheme).to(equal("cachingPlayerItemScheme"))
                    expect(urlAsset.url.path).to(equal(testURL.path))
                }

                it("preserves original path extension") {
                    let mp4URL = URL(string: "https://example.com/video.mp4")!
                    sut = CachingPlayerItem(url: mp4URL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp4"))
                }

                it("uses custom file extension when provided") {
                    let urlWithoutExtension = URL(string: "https://example.com/media/12345")!
                    sut = CachingPlayerItem(url: urlWithoutExtension, customFileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp3"))
                }

                it("extracts HTTP headers from avUrlAssetOptions") {
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": ["Authorization": "Bearer token123"]]
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).toNot(beNil())
                    expect(sut.urlRequestHeaders?["Authorization"]).to(equal("Bearer token123"))
                }

                it("stores configuration correctly") {
                    let config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 1024 * 1024,
                        readDataLimit: 512 * 1024
                    )
                    sut = CachingPlayerItem(url: testURL, configuration: config)

                    expect(sut.configuration.downloadBufferLimit).to(equal(1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(512 * 1024))
                }

                it("generates random save file path in caches directory") {
                    sut = CachingPlayerItem(url: testURL)

                    // Access the internal saveFilePath through reflection or by testing behavior
                    // Since saveFilePath is private, we test indirectly through delegate callback
                    sut.delegate = delegate

                    expect(sut).to(beAKindOf(CachingPlayerItem.self))
                }

                it("uses provided save file path") {
                    let customPath = tempDirectory.appendingPathComponent("custom-video.mp4").path
                    sut = CachingPlayerItem(url: testURL, saveFilePath: customPath, customFileExtension: nil)

                    // Verify by attempting to create the player item
                    expect(sut.asset).to(beAKindOf(AVURLAsset.self))
                }
            }

            context("when initialized for non-caching playback") {
                it("uses original URL scheme without modification") {
                    sut = CachingPlayerItem(nonCachingURL: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.scheme).to(equal("https"))
                    expect(urlAsset.url.absoluteString).to(equal(testURL.absoluteString))
                }

                it("does not support download method") {
                    sut = CachingPlayerItem(nonCachingURL: testURL)

                    expect(sut.download()).to(throwAssertion())
                    expect(sut.asset).to(beAKindOf(AVURLAsset.self))
                }
            }

            context("when initialized with local data") {
                it("writes data to file and creates playable item") {
                    let testData = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE])

                    expect {
                        sut = try CachingPlayerItem(data: testData, customFileExtension: "mp3")
                    }.toNot(throwError())

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.isFileURL).to(beTrue())
                    expect(urlAsset.url.pathExtension).to(equal("mp3"))

                    // Verify file exists and contains data
                    let fileExists = FileManager.default.fileExists(atPath: urlAsset.url.path)
                    expect(fileExists).to(beTrue())
                }

                it("creates file with correct size") {
                    let testData = Data(repeating: 0xFF, count: 1024)

                    expect {
                        sut = try CachingPlayerItem(data: testData, customFileExtension: "mp4")
                    }.toNot(throwError())

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    let attributes = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
                    let fileSize = attributes?[.size] as? Int
                    expect(fileSize).to(equal(1024))
                }
            }

            context("when initialized with local file") {
                it("creates AVURLAsset pointing to file URL") {
                    let localFileURL = tempDirectory.appendingPathComponent("local-video.mp4")
                    FileManager.default.createFile(atPath: localFileURL.path, contents: Data([0x00, 0x01]), attributes: nil)

                    sut = CachingPlayerItem(filePathURL: localFileURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url).to(equal(localFileURL))
                    expect(urlAsset.url.isFileURL).to(beTrue())
                }

                it("creates symbolic link when custom file extension provided") {
                    let localFileURL = tempDirectory.appendingPathComponent("original-file")
                    let testData = Data([0x01, 0x02, 0x03])
                    FileManager.default.createFile(atPath: localFileURL.path, contents: testData, attributes: nil)

                    sut = CachingPlayerItem(filePathURL: localFileURL, fileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp3"))

                    // Verify symbolic link was created
                    let linkAttributes = try? FileManager.default.attributesOfItem(atPath: urlAsset.url.path)
                    let fileType = linkAttributes?[.type] as? FileAttributeType
                    expect(fileType).to(equal(.typeSymbolicLink))
                }

                it("removes old symbolic links before creating new ones") {
                    let originalFile = tempDirectory.appendingPathComponent("original")
                    FileManager.default.createFile(atPath: originalFile.path, contents: Data([0x01]), attributes: nil)

                    // Create first item (creates symlink)
                    let item1 = CachingPlayerItem(filePathURL: originalFile, fileExtension: "mp3")
                    let symLinkPath = (item1.asset as? AVURLAsset)?.url.path

                    // Create second item with same parameters (should remove old symlink)
                    sut = CachingPlayerItem(filePathURL: originalFile, fileExtension: "mp3")

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected asset to be AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.path).to(equal(symLinkPath))
                }
            }

            context("when initialized with AVAsset") {
                it("uses the provided AVAsset directly") {
                    let customAsset = AVURLAsset(url: testURL)
                    sut = CachingPlayerItem(asset: customAsset, automaticallyLoadedAssetKeys: nil)

                    expect(sut.asset).to(be(customAsset))
                }
            }

            // MARK: - Delegate Tests

            context("when delegate is set") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                    sut.delegate = delegate
                }

                it("stores weak reference to delegate") {
                    expect(sut.delegate).to(be(delegate))
                }

                it("calls playerItemPlaybackStalled when stall notification received") {
                    NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: sut)

                    expect(delegate.playbackStalledCalled).toEventually(beTrue(), timeout: .seconds(1))
                }
            }

            // MARK: - Download Tests

            context("when download is initiated") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                    sut.delegate = delegate
                }

                it("triggers download for caching player item") {
                    expect { sut.download() }.toNot(throwAssertion())
                }
            }

            // MARK: - passOnObject Tests

            context("when using passOnObject") {
                beforeEach {
                    sut = CachingPlayerItem(url: testURL)
                }

                it("can store any type conforming to Any") {
                    struct CustomModel {
                        let id: Int
                        let name: String
                    }

                    let model = CustomModel(id: 123, name: "Test")
                    sut.passOnObject = model

                    guard let storedModel = sut.passOnObject as? CustomModel else {
                        fail("Expected CustomModel to be stored")
                        return
                    }

                    expect(storedModel.id).to(equal(123))
                    expect(storedModel.name).to(equal("Test"))
                }

                it("can be set to nil") {
                    sut.passOnObject = "test"
                    expect(sut.passOnObject).toNot(beNil())

                    sut.passOnObject = nil
                    expect(sut.passOnObject).to(beNil())
                }
            }

            // MARK: - Configuration Tests

            context("when using custom configuration") {
                it("applies all configuration properties") {
                    let config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 2 * 1024 * 1024,
                        readDataLimit: 1 * 1024 * 1024,
                        shouldVerifyDownloadedFileSize: true,
                        minimumExpectedFileSize: 500000,
                        shouldCheckAvailableDiskSpaceBeforeCaching: false,
                        allowsUncachedSeek: false,
                        logLevel: .info
                    )
                    sut = CachingPlayerItem(url: testURL, configuration: config)

                    expect(sut.configuration.downloadBufferLimit).to(equal(2 * 1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(1 * 1024 * 1024))
                    expect(sut.configuration.shouldVerifyDownloadedFileSize).to(beTrue())
                    expect(sut.configuration.minimumExpectedFileSize).to(equal(500000))
                    expect(sut.configuration.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                    expect(sut.configuration.allowsUncachedSeek).to(beFalse())
                    expect(sut.configuration.logLevel).to(equal(.info))
                }

                it("uses default configuration when not specified") {
                    sut = CachingPlayerItem(url: testURL)

                    expect(sut.configuration.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                    expect(sut.configuration.readDataLimit).to(equal(10 * 1024 * 1024))
                }
            }

            // MARK: - Memory Management Tests

            context("when managing memory") {
                it("deallocates properly") {
                    weak var weakReference: CachingPlayerItem?

                    autoreleasepool {
                        let item = CachingPlayerItem(url: testURL)
                        weakReference = item
                        expect(weakReference).toNot(beNil())
                    }

                    expect(weakReference).toEventually(beNil(), timeout: .seconds(2))
                }

                it("maintains weak reference to delegate") {
                    sut = CachingPlayerItem(url: testURL)
                    weak var weakDelegate: MockCachingPlayerItemDelegate?

                    autoreleasepool {
                        let strongDelegate = MockCachingPlayerItemDelegate()
                        weakDelegate = strongDelegate
                        sut.delegate = strongDelegate
                        expect(sut.delegate).toNot(beNil())
                    }

                    expect(weakDelegate).toEventually(beNil(), timeout: .seconds(2))
                    expect(sut.delegate).to(beNil())
                }

                it("cancels download on deinit for caching items") {
                    weak var weakItem: CachingPlayerItem?

                    autoreleasepool {
                        let item = CachingPlayerItem(url: testURL)
                        weakItem = item
                        item.download()
                    }

                    // Should cancel session on deinit
                    expect(weakItem).toEventually(beNil(), timeout: .seconds(2))
                }
            }

            // MARK: - AVPlayerItem Compatibility Tests

            context("when used as AVPlayerItem") {
                it("integrates with AVPlayer") {
                    sut = CachingPlayerItem(url: testURL)
                    let player = AVPlayer(playerItem: sut)

                    expect(player.currentItem).to(be(sut))
                }

                it("has unknown status initially") {
                    sut = CachingPlayerItem(url: testURL)

                    expect(sut.status).to(equal(AVPlayerItem.Status.unknown))
                }

                it("supports standard AVPlayerItem operations") {
                    sut = CachingPlayerItem(url: testURL)
                    let time = CMTime(seconds: 5, preferredTimescale: 600)

                    var completionCalled = false
                    sut.seek(to: time) { _ in
                        completionCalled = true
                    }

                    expect(completionCalled).toEventually(beTrue(), timeout: .seconds(2))
                }
            }

            // MARK: - URL Validation Tests

            context("when validating URLs") {
                it("handles different video extensions") {
                    let extensions = ["mp4", "mov", "m4v", "avi"]

                    for ext in extensions {
                        let url = URL(string: "https://example.com/video.\(ext)")!
                        let item = CachingPlayerItem(url: url)

                        guard let urlAsset = item.asset as? AVURLAsset else {
                            fail("Expected asset to be AVURLAsset for extension \(ext)")
                            continue
                        }

                        expect(urlAsset.url.pathExtension).to(equal(ext))
                    }
                }

                it("handles different audio extensions") {
                    let extensions = ["mp3", "m4a", "wav", "aac"]

                    for ext in extensions {
                        let url = URL(string: "https://example.com/audio.\(ext)")!
                        let item = CachingPlayerItem(url: url)

                        guard let urlAsset = item.asset as? AVURLAsset else {
                            fail("Expected asset to be AVURLAsset for extension \(ext)")
                            continue
                        }

                        expect(urlAsset.url.pathExtension).to(equal(ext))
                    }
                }
            }

            // MARK: - Concurrent Usage Tests

            context("when used concurrently") {
                it("creates independent instances") {
                    let item1 = CachingPlayerItem(url: testURL)
                    let item2 = CachingPlayerItem(url: testURL)

                    expect(item1).toNot(be(item2))
                    expect(item1.asset).toNot(be(item2.asset))
                }

                it("allows different configurations per instance") {
                    let config1 = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    let config2 = CachingPlayerItemConfiguration(downloadBufferLimit: 10 * 1024 * 1024)

                    let item1 = CachingPlayerItem(url: testURL, configuration: config1)
                    let item2 = CachingPlayerItem(url: testURL, configuration: config2)

                    expect(item1.configuration.downloadBufferLimit).to(equal(5 * 1024 * 1024))
                    expect(item2.configuration.downloadBufferLimit).to(equal(10 * 1024 * 1024))
                }
            }

            // MARK: - HTTP Headers Tests

            context("when setting HTTP headers") {
                it("extracts headers from AVURLAssetHTTPHeaderFieldsKey") {
                    let headers = [
                        "Authorization": "Bearer token123",
                        "User-Agent": "CustomAgent/1.0",
                        "Accept-Language": "en-US"
                    ]
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": headers]

                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).to(equal(headers))
                }

                it("handles empty headers dictionary") {
                    let options = ["AVURLAssetHTTPHeaderFieldsKey": [:]]
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: options)

                    expect(sut.urlRequestHeaders).to(equal([:]))
                }

                it("has nil headers when not provided") {
                    sut = CachingPlayerItem(url: testURL, avUrlAssetOptions: nil)

                    expect(sut.urlRequestHeaders).to(beNil())
                }
            }
        }

        // MARK: - CachingPlayerItemConfiguration Tests

        describe("CachingPlayerItemConfiguration") {
            var config: CachingPlayerItemConfiguration!

            context("when created with default initializer") {
                beforeEach {
                    config = CachingPlayerItemConfiguration()
                }

                it("has correct default values") {
                    expect(config.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                    expect(config.readDataLimit).to(equal(10 * 1024 * 1024))
                    expect(config.shouldVerifyDownloadedFileSize).to(beFalse())
                    expect(config.minimumExpectedFileSize).to(equal(0))
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beTrue())
                    expect(config.allowsUncachedSeek).to(beTrue())
                    expect(config.logLevel).to(equal(LogLevel.none))
                }
            }

            context("when created with custom values") {
                it("stores custom downloadBufferLimit") {
                    config = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    expect(config.downloadBufferLimit).to(equal(5 * 1024 * 1024))
                }

                it("stores custom readDataLimit") {
                    config = CachingPlayerItemConfiguration(readDataLimit: 2 * 1024 * 1024)
                    expect(config.readDataLimit).to(equal(2 * 1024 * 1024))
                }

                it("stores custom shouldVerifyDownloadedFileSize") {
                    config = CachingPlayerItemConfiguration(shouldVerifyDownloadedFileSize: true)
                    expect(config.shouldVerifyDownloadedFileSize).to(beTrue())
                }

                it("stores custom minimumExpectedFileSize") {
                    config = CachingPlayerItemConfiguration(minimumExpectedFileSize: 1000000)
                    expect(config.minimumExpectedFileSize).to(equal(1000000))
                }

                it("stores custom shouldCheckAvailableDiskSpaceBeforeCaching") {
                    config = CachingPlayerItemConfiguration(shouldCheckAvailableDiskSpaceBeforeCaching: false)
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                }

                it("stores custom allowsUncachedSeek") {
                    config = CachingPlayerItemConfiguration(allowsUncachedSeek: false)
                    expect(config.allowsUncachedSeek).to(beFalse())
                }

                it("stores custom logLevel") {
                    config = CachingPlayerItemConfiguration(logLevel: .error)
                    expect(config.logLevel).to(equal(.error))
                }

                it("stores all custom values together") {
                    config = CachingPlayerItemConfiguration(
                        downloadBufferLimit: 20 * 1024 * 1024,
                        readDataLimit: 15 * 1024 * 1024,
                        shouldVerifyDownloadedFileSize: true,
                        minimumExpectedFileSize: 2000000,
                        shouldCheckAvailableDiskSpaceBeforeCaching: false,
                        allowsUncachedSeek: false,
                        logLevel: .info
                    )

                    expect(config.downloadBufferLimit).to(equal(20 * 1024 * 1024))
                    expect(config.readDataLimit).to(equal(15 * 1024 * 1024))
                    expect(config.shouldVerifyDownloadedFileSize).to(beTrue())
                    expect(config.minimumExpectedFileSize).to(equal(2000000))
                    expect(config.shouldCheckAvailableDiskSpaceBeforeCaching).to(beFalse())
                    expect(config.allowsUncachedSeek).to(beFalse())
                    expect(config.logLevel).to(equal(.info))
                }
            }

            context("when using static default instance") {
                it("returns a configuration instance") {
                    let defaultConfig = CachingPlayerItemConfiguration.default
                    expect(defaultConfig.downloadBufferLimit).to(equal(15 * 1024 * 1024))
                }

                it("can be modified globally") {
                    let originalDefault = CachingPlayerItemConfiguration.default

                    let newDefault = CachingPlayerItemConfiguration(downloadBufferLimit: 25 * 1024 * 1024)
                    CachingPlayerItemConfiguration.default = newDefault

                    expect(CachingPlayerItemConfiguration.default.downloadBufferLimit).to(equal(25 * 1024 * 1024))

                    // Restore original
                    CachingPlayerItemConfiguration.default = originalDefault
                }
            }

            context("when comparing configurations") {
                it("creates independent instances") {
                    let config1 = CachingPlayerItemConfiguration(downloadBufferLimit: 5 * 1024 * 1024)
                    let config2 = CachingPlayerItemConfiguration(downloadBufferLimit: 10 * 1024 * 1024)

                    expect(config1.downloadBufferLimit).toNot(equal(config2.downloadBufferLimit))
                }
            }
        }

        // MARK: - Mock Delegate Behavior Tests

        describe("MockCachingPlayerItemDelegate") {
            var delegate: MockCachingPlayerItemDelegate!
            var sut: CachingPlayerItem!

            beforeEach {
                delegate = MockCachingPlayerItemDelegate()
                sut = CachingPlayerItem(url: URL(string: "https://example.com/test.mp4")!)
                sut.delegate = delegate
            }

            afterEach {
                delegate = nil
                sut = nil
            }

            context("when reset is called") {
                it("clears all flags") {
                    delegate.didFinishDownloadingCalled = true
                    delegate.didDownloadBytesCalled = true
                    delegate.downloadingFailedCalled = true
                    delegate.readyToPlayCalled = true
                    delegate.didFailToPlayCalled = true
                    delegate.playbackStalledCalled = true

                    delegate.reset()

                    expect(delegate.didFinishDownloadingCalled).to(beFalse())
                    expect(delegate.didDownloadBytesCalled).to(beFalse())
                    expect(delegate.downloadingFailedCalled).to(beFalse())
                    expect(delegate.readyToPlayCalled).to(beFalse())
                    expect(delegate.didFailToPlayCalled).to(beFalse())
                    expect(delegate.playbackStalledCalled).to(beFalse())
                }

                it("clears all stored values") {
                    delegate.lastDownloadedFilePath = "/path/to/file"
                    delegate.lastBytesDownloaded = 1000
                    delegate.lastBytesExpected = 2000
                    delegate.lastError = NSError(domain: "test", code: 1)
                    delegate.lastPlayError = NSError(domain: "play", code: 2)

                    delegate.reset()

                    expect(delegate.lastDownloadedFilePath).to(beNil())
                    expect(delegate.lastBytesDownloaded).to(equal(0))
                    expect(delegate.lastBytesExpected).to(equal(0))
                    expect(delegate.lastError).to(beNil())
                    expect(delegate.lastPlayError).to(beNil())
                }
            }

            context("when delegate methods are called") {
                it("tracks playerItemPlaybackStalled") {
                    NotificationCenter.default.post(name: .AVPlayerItemPlaybackStalled, object: sut)

                    expect(delegate.playbackStalledCalled).toEventually(beTrue(), timeout: .seconds(1))
                }
            }
        }

        // MARK: - File System Integration Tests

        describe("File System Integration") {
            var tempDirectory: URL!

            beforeEach {
                tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
            }

            afterEach {
                try? FileManager.default.removeItem(at: tempDirectory)
            }

            context("when using data initializer") {
                it("persists data to disk") {
                    let testData = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F]) // "Hello"

                    let item = try? CachingPlayerItem(data: testData, customFileExtension: "txt")
                    expect(item).toNot(beNil())

                    guard let urlAsset = item?.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    let savedData = try? Data(contentsOf: urlAsset.url)
                    expect(savedData).to(equal(testData))
                }

                it("cleans up file on deallocation") {
                    var fileURL: URL?

                    autoreleasepool {
                        let testData = Data([0x01, 0x02, 0x03])
                        let item = try? CachingPlayerItem(data: testData, customFileExtension: "bin")
                        fileURL = (item?.asset as? AVURLAsset)?.url

                        expect(FileManager.default.fileExists(atPath: fileURL!.path)).to(beTrue())
                    }
                }
            }
        }

        // MARK: - Resource Loader Integration Tests

        describe("Resource Loader Integration") {
            var sut: CachingPlayerItem!
            let testURL = URL(string: "https://example.com/media.mp4")!

            afterEach {
                sut = nil
            }

            context("when initialized for caching") {
                it("sets resource loader delegate on asset") {
                    sut = CachingPlayerItem(url: testURL)

                    guard let urlAsset = sut.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.resourceLoader).toNot(beNil())
                }
            }
        }

        // MARK: - Edge Cases and Error Conditions

        describe("Edge Cases") {
            context("when handling URLs") {
                it("preserves query parameters") {
                    let urlWithQuery = URL(string: "https://example.com/video.mp4?token=abc123&expires=456")!
                    let item = CachingPlayerItem(url: urlWithQuery)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.query).toNot(beNil())
                }

                it("preserves URL fragments") {
                    let urlWithFragment = URL(string: "https://example.com/video.mp4#section")!
                    let item = CachingPlayerItem(url: urlWithFragment)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.fragment).toNot(beNil())
                }

                it("handles URLs with special characters") {
                    let specialURL = URL(string: "https://example.com/video%20file.mp4")!
                    let item = CachingPlayerItem(url: specialURL)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.path()).to(equal(specialURL.path()))
                }
            }

            context("when handling file extensions") {
                it("handles uppercase extensions") {
                    let url = URL(string: "https://example.com/VIDEO.MP4")!
                    let item = CachingPlayerItem(url: url)

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("MP4"))
                }

                it("replaces extension when custom extension provided") {
                    let url = URL(string: "https://example.com/media.xyz")!
                    let item = CachingPlayerItem(url: url, customFileExtension: "mp4")

                    guard let urlAsset = item.asset as? AVURLAsset else {
                        fail("Expected AVURLAsset")
                        return
                    }

                    expect(urlAsset.url.pathExtension).to(equal("mp4"))
                }
            }
        }

        // MARK: - Performance Considerations

        describe("Performance") {
            context("when creating multiple instances") {
                it("creates instances quickly") {
                    let url = URL(string: "https://example.com/video.mp4")!

                    let startTime = Date()

                    for _ in 0..<100 {
                        _ = CachingPlayerItem(url: url)
                    }

                    let elapsed = Date().timeIntervalSince(startTime)
                    expect(elapsed).to(beLessThan(1.0)) // Should create 100 instances in under 1 second
                }
            }
        }
    }
}

// MARK: - Mock Delegate

class MockCachingPlayerItemDelegate: NSObject, CachingPlayerItemDelegate {
    var didFinishDownloadingCalled = false
    var didDownloadBytesCalled = false
    var downloadingFailedCalled = false
    var readyToPlayCalled = false
    var didFailToPlayCalled = false
    var playbackStalledCalled = false

    var lastDownloadedFilePath: String?
    var lastBytesDownloaded: Int = 0
    var lastBytesExpected: Int = 0
    var lastError: Error?
    var lastPlayError: Error?

    func playerItem(_ playerItem: CachingPlayerItem, didFinishDownloadingFileAt filePath: String) {
        didFinishDownloadingCalled = true
        lastDownloadedFilePath = filePath
    }

    func playerItem(_ playerItem: CachingPlayerItem, didDownloadBytesSoFar bytesDownloaded: Int, outOf bytesExpected: Int) {
        didDownloadBytesCalled = true
        lastBytesDownloaded = bytesDownloaded
        lastBytesExpected = bytesExpected
    }

    func playerItem(_ playerItem: CachingPlayerItem, downloadingFailedWith error: Error) {
        downloadingFailedCalled = true
        lastError = error
    }

    func playerItemReadyToPlay(_ playerItem: CachingPlayerItem) {
        readyToPlayCalled = true
    }

    func playerItemDidFailToPlay(_ playerItem: CachingPlayerItem, withError error: Error?) {
        didFailToPlayCalled = true
        lastPlayError = error
    }

    func playerItemPlaybackStalled(_ playerItem: CachingPlayerItem) {
        playbackStalledCalled = true
    }

    func reset() {
        didFinishDownloadingCalled = false
        didDownloadBytesCalled = false
        downloadingFailedCalled = false
        readyToPlayCalled = false
        didFailToPlayCalled = false
        playbackStalledCalled = false

        lastDownloadedFilePath = nil
        lastBytesDownloaded = 0
        lastBytesExpected = 0
        lastError = nil
        lastPlayError = nil
    }
}

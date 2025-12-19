//
//  URLResponseExtension.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10/24/20.
//

import Foundation
import AVFoundation

extension URLResponse {
    struct ProcessedInfoData {
        let response: URLResponse

        var mimeType: String {
            // 1. 获取并清理 MIME Type
            guard let mime = response.mimeType?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) else {
                // 如果没有 Content-Type，默认回退到 mp4
                return AVFileType.mp4.rawValue
            }

            // 2. 精确映射表：MIME -> UTI
            // 注意：这里优先返回 AVFileType.*.rawValue 以确保最大兼容性
            switch mime {
                
            // MARK: - FLAC (无损)
            case "audio/flac", "audio/x-flac":
                return "org.xiph.flac" // iOS 11+ 支持
                
            // MARK: - MP3
            case "audio/mpeg", "audio/mp3", "audio/mpg", "audio/x-mpeg", "audio/x-mp3":
                return AVFileType.mp3.rawValue // public.mp3
                
            // MARK: - M4A / AAC (常用容器)
            case "audio/mp4", "audio/m4a", "audio/x-m4a":
                return AVFileType.m4a.rawValue // com.apple.m4a-audio
                
            // MARK: - WAV (无损)
            case "audio/wav", "audio/x-wav", "audio/wave":
                return AVFileType.wav.rawValue // com.microsoft.waveform-audio
                
            // MARK: - AAC (Raw ADTS)
            // 注意：AVFileType 没有 .aac 常量，需直接返回 UTI
            case "audio/aac", "audio/aacp", "audio/x-aac":
                return "public.aac-audio"
                
            // MARK: - AIFF (Apple 无损)
            case "audio/aiff", "audio/x-aiff":
                return AVFileType.aiff.rawValue // public.aiff-audio
                
            // MARK: - AC3 (Dolby Digital)
            case "audio/ac3":
                return AVFileType.ac3.rawValue // public.ac3-audio
                
            // MARK: - CAF (Core Audio Format)
            case "audio/x-caf":
                return AVFileType.caf.rawValue
                
            default:
                // 3. 模糊匹配兜底策略 (保留原有逻辑作为最后的保障)
                if mime.contains("mp4") || mime.contains("audio/mp4") {
                    return AVFileType.mp4.rawValue
                } else if mime.contains("mp3") || mime.contains("mpeg") {
                    return AVFileType.mp3.rawValue
                } else if mime.contains("wav") {
                    return AVFileType.wav.rawValue
                } else if mime.contains("flac") {
                    return "org.xiph.flac"
                }
                
                // 实在无法识别，默认返回 mp4 (AVURLAsset 对 mp4 容器容错率较高)
                return AVFileType.mp4.rawValue
            }
        }

        var expectedContentLength: Int64 {
            guard let response = response as? HTTPURLResponse else {
                return response.expectedContentLength
            }

            let contentRangeKeys: [String] = [
                "Content-Range",
                "content-range",
                "Content-range",
                "content-Range",
            ]

            var rangeString: String?

            for key in contentRangeKeys {
                if let value = response.allHeaderFields[key] as? String {
                    rangeString = value
                    break
                }
            }

            if let rangeString = rangeString,
               let bytesString = rangeString.split(separator: "/").map({String($0)}).last,
               let bytes = Int64(bytesString) {
                return bytes
            }

            return response.expectedContentLength
        }

        var isByteRangeAccessSupported: Bool {
            guard let response = response as? HTTPURLResponse else {
                return false
            }

            let rangeAccessKeys: [String] = [
                "Accept-Ranges",
                "accept-ranges",
                "Accept-ranges",
                "accept-Ranges",
            ]

            for key in rangeAccessKeys {
                if let value = response.allHeaderFields[key] as? String,
                   value == "bytes" {
                    return true
                }
            }

            return false
        }
    }

    var processedInfoData: ProcessedInfoData { .init(response: self) }
}

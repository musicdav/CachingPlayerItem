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
            case "audio/mpeg", "audio/mpeg3", "audio/mp3", "audio/mpg", "audio/x-mpeg", "audio/x-mpeg3", "audio/x-mp3", "audio/x-mpg":
                return AVFileType.mp3.rawValue // public.mp3
                
            // MARK: - M4A / AAC (常用容器)
            case "audio/mp4", "audio/m4a", "audio/x-m4a":
                return AVFileType.m4a.rawValue // com.apple.m4a-audio
            case "audio/x-m4b":
                return "public.mpeg-4-audio"
            case "audio/x-m4p":
                return "com.apple.protected-mpeg-4-audio"
            case "audio/x-m4r":
                return "com.apple.mpeg-4-ringtone"
                
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

            // MARK: - AU / AIFF-C (Legacy Apple Audio)
            case "audio/basic":
                return "public.au-audio"
            case "audio/x-aifc":
                return "public.aifc-audio"
                
            // MARK: - AC3 (Dolby Digital)
            case "audio/ac3":
                return AVFileType.ac3.rawValue // public.ac3-audio

            // MARK: - Enhanced AC3
            case "audio/enhanced-ac3":
                return "public.enhanced-ac3-audio"
                
            // MARK: - CAF (Core Audio Format)
            case "audio/x-caf":
                return AVFileType.caf.rawValue

            // MARK: - MP2 / MPA
            case "audio/mpa":
                return "public.mp2"

            // MARK: - USAC
            case "audio/usac":
                return "public.mpeg-4-audio"

            // MARK: - 3GPP / AMR
            case "audio/3gpp":
                return "public.3gpp"
            case "audio/3gpp2":
                return "public.3gpp2"
            case "audio/amr", "audio/amr-wb":
                return "org.3gpp.adaptive-multi-rate-audio"

            // MARK: - OGG
            case "audio/ogg":
                return "org.xiph.ogg-audio"

            // MARK: - QuickTime Audio
            case "audio/x-quicktime":
                return "com.apple.quicktime-audio"

            // MARK: - WAV (vendor variants)
            case "audio/vnd.wave":
                return AVFileType.wav.rawValue // com.microsoft.waveform-audio

            // MARK: - Playlist formats (audio-related)
            case "audio/scpls", "audio/x-scpls":
                return "public.pls-playlist"
            case "audio/mpegurl", "audio/x-mpegurl", "application/vnd.apple.mpegurl", "application/x-mpegurl":
                return "public.m3u-playlist"
                
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

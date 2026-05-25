import Foundation
import AppKit
import AVFoundation
import CoreImage

class SubtitleGenerator {
    
    // MARK: - API Structs
    
    struct SarvamResponse: Decodable {
        let transcript: String?
        let languageCode: String?
        let modelVersion: String?
        let timestamps: SarvamTimestamps?
        
        enum CodingKeys: String, CodingKey {
            case transcript
            case languageCode = "language_code"
            case modelVersion = "model_version"
            case timestamps
        }
    }

    struct SarvamTimestamps: Decodable {
        let words: [String]?
        let startTimeSeconds: [Double]?
        let endTimeSeconds: [Double]?
        
        enum CodingKeys: String, CodingKey {
            case words
            case startTimeSeconds = "start_time_seconds"
            case endTimeSeconds = "end_time_seconds"
        }
    }

    struct SarvamTimestamp {
        let word: String
        let startTimeSeconds: Double
        let endTimeSeconds: Double
    }
    
    struct SRTSegment {
        let index: Int
        let startTime: Double
        let endTime: Double
        let text: String
        
        var srtFormat: String {
            let startStr = formatTime(startTime)
            let endStr = formatTime(endTime)
            return "\(index)\n\(startStr) --> \(endStr)\n\(text)\n\n"
        }
        
        private func formatTime(_ seconds: Double) -> String {
            let totalMs = Int((seconds * 1000).rounded())
            let ms = totalMs % 1000
            let totalSecs = totalMs / 1000
            let secs = totalSecs % 60
            let totalMins = totalSecs / 60
            let mins = totalMins % 60
            let hours = totalMins / 60
            
            return String(format: "%02d:%02d:%02d,%03d", hours, mins, secs, ms)
        }
    }

    // MARK: - Public Upload & Format Methods
    
    /// Sends the audio file to Sarvam API for transcription
    static func transcribeAudio(fileURL: URL, apiKey: String) async throws -> SarvamResponse {
        let url = URL(string: "https://api.sarvam.ai/speech-to-text")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "api-subscription-key")
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let body = try createMultipartBody(fileURL: fileURL, boundary: boundary)
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SubtitleGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let serverError = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw NSError(domain: "SubtitleGenerator", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Server error (\(httpResponse.statusCode)): \(serverError)"])
        }
        
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(SarvamResponse.self, from: data)
        } catch {
            let jsonString = String(data: data, encoding: .utf8) ?? "Unable to read raw JSON response"
            throw NSError(domain: "SubtitleGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "Decoding error: \(error.localizedDescription). Response: \(jsonString)"])
        }
    }
    
    /// Generates individual segments from response timing info
    static func generateSRTSegments(from response: SarvamResponse, style: SubtitleStyle) -> [SRTSegment] {
        // Reconstruct flat timestamp array from parallel arrays returned by the API
        var reconstructedTimestamps: [SarvamTimestamp] = []
        if let ts = response.timestamps,
           let words = ts.words,
           let starts = ts.startTimeSeconds,
           let ends = ts.endTimeSeconds {
            let count = min(words.count, min(starts.count, ends.count))
            for i in 0..<count {
                reconstructedTimestamps.append(
                    SarvamTimestamp(
                        word: words[i],
                        startTimeSeconds: starts[i],
                        endTimeSeconds: ends[i]
                    )
                )
            }
        }
        
        guard !reconstructedTimestamps.isEmpty else {
            // Fallback: entire transcript as a single block if no timestamps are present
            if let transcript = response.transcript, !transcript.isEmpty {
                return [SRTSegment(index: 1, startTime: 0.0, endTime: 5.0, text: transcript)]
            }
            return []
        }
        
        var segments: [SRTSegment] = []
        
        switch style {
        case .wordByWord:
            for (i, wordInfo) in reconstructedTimestamps.enumerated() {
                let segment = SRTSegment(
                    index: i + 1,
                    startTime: wordInfo.startTimeSeconds,
                    endTime: wordInfo.endTimeSeconds,
                    text: wordInfo.word
                )
                segments.append(segment)
            }
            
        case .grouped:
            var currentIndex = 1
            var groupWords: [String] = []
            var groupStart: Double? = nil
            var groupEnd: Double = 0.0
            
            let maxWordsPerLine = 7
            let maxDuration = 3.0 // seconds
            let maxSilenceGap = 1.2 // seconds
            
            for wordInfo in reconstructedTimestamps {
                let wordStart = wordInfo.startTimeSeconds
                let wordEnd = wordInfo.endTimeSeconds
                let word = wordInfo.word
                
                if groupStart == nil {
                    groupStart = wordStart
                }
                
                let shouldFlush: Bool
                if groupWords.isEmpty {
                    shouldFlush = false
                } else {
                    let silenceGap = wordStart - groupEnd
                    let currentDuration = wordEnd - (groupStart ?? wordStart)
                    
                    shouldFlush = (silenceGap > maxSilenceGap) ||
                                   (currentDuration > maxDuration) ||
                                   (groupWords.count >= maxWordsPerLine)
                }
                
                if shouldFlush {
                    let text = groupWords.joined(separator: " ")
                    let segment = SRTSegment(
                        index: currentIndex,
                        startTime: groupStart ?? 0.0,
                        endTime: groupEnd,
                        text: text
                    )
                    segments.append(segment)
                    
                    currentIndex += 1
                    groupWords = [word]
                    groupStart = wordStart
                    groupEnd = wordEnd
                } else {
                    groupWords.append(word)
                    groupEnd = wordEnd
                }
            }
            
            if !groupWords.isEmpty {
                let text = groupWords.joined(separator: " ")
                let segment = SRTSegment(
                    index: currentIndex,
                    startTime: groupStart ?? 0.0,
                    endTime: groupEnd,
                    text: text
                )
                segments.append(segment)
            }
        }
        
        return segments
    }
    
    /// Converts Sarvam response into a standard SRT subtitle string
    static func generateSRT(from response: SarvamResponse, style: SubtitleStyle) -> String {
        let segments = generateSRTSegments(from: response, style: style)
        return segments.map { $0.srtFormat }.joined()
    }
    
    // MARK: - Post-Processing Subtitle Burn-In
    
    /// Bakes parsed subtitles directly onto the video frames of the recorded file
    static func burnSubtitles(videoURL: URL, segments: [SRTSegment]) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw NSError(domain: "SubtitleGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
        }
        
        let naturalSize = try await videoTrack.load(.naturalSize)
        
        let tempOutputURL = videoURL.deletingPathExtension().appendingPathExtension("burnedTemp.mov")
        try? FileManager.default.removeItem(at: tempOutputURL)
        
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "SubtitleGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAssetExportSession"])
        }
        
        exportSession.outputURL = tempOutputURL
        exportSession.outputFileType = .mov
        
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let sourceImage = request.sourceImage
            let time = request.compositionTime.seconds
            
            if let activeSegment = segments.first(where: { time >= $0.startTime && time <= $0.endTime }) {
                if let textImage = drawSubtitleImage(text: activeSegment.text, canvasSize: sourceImage.extent.size) {
                    let outputImage = textImage.composited(over: sourceImage)
                    request.finish(with: outputImage, context: nil)
                    return
                }
            }
            request.finish(with: sourceImage, context: nil)
        }
        
        videoComposition.renderSize = naturalSize
        exportSession.videoComposition = videoComposition
        
        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
        
        guard exportSession.status == .completed else {
            let error = exportSession.error ?? NSError(domain: "SubtitleGenerator", code: 0, userInfo: [NSLocalizedDescriptionKey: "Video caption export failed"])
            throw error
        }
        
        // Replace original video file with the burned version
        try FileManager.default.removeItem(at: videoURL)
        try FileManager.default.moveItem(at: tempOutputURL, to: videoURL)
        
        return videoURL
    }
    
    /// Renders text with line wrapping and a rounded black bounding box into a small overlay image
    private static func drawSubtitleImage(text: String, canvasSize: CGSize) -> CIImage? {
        let padding: CGFloat = 12.0
        let maxTextWidth = canvasSize.width * 0.8
        let fontSize = max(24.0, canvasSize.height * 0.038)
        
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        
        let constraintSize = CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude)
        let textRect = text.boundingRect(with: constraintSize, options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
        
        let boxWidth = textRect.width + padding * 2
        let boxHeight = textRect.height + padding * 2
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(boxWidth),
                  height: Int(boxHeight),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        
        NSGraphicsContext.saveGraphicsState()
        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.current = nsContext
        
        // Draw black background pill/box
        let boxRect = CGRect(x: 0, y: 0, width: boxWidth, height: boxHeight)
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 8, yRadius: 8)
        NSColor.black.withAlphaComponent(0.6).setFill()
        path.fill()
        
        // Render text Centered
        let textDrawRect = CGRect(
            x: padding,
            y: padding,
            width: textRect.width,
            height: textRect.height
        )
        text.draw(in: textDrawRect, withAttributes: attributes)
        
        NSGraphicsContext.restoreGraphicsState()
        
        guard let cgImage = context.makeImage() else { return nil }
        var textImage = CIImage(cgImage: cgImage)
        
        // Place it centered horizontally and 8% from the bottom of the video canvas
        let xOffset = (canvasSize.width - boxWidth) / 2
        let yOffset = canvasSize.height * 0.08
        textImage = textImage.transformed(by: CGAffineTransform(translationX: xOffset, y: yOffset))
        
        return textImage
    }
    
    // MARK: - Private Multipart Helper
    
    private static func createMultipartBody(fileURL: URL, boundary: String) throws -> Data {
        var data = Data()
        
        // model parameter
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        data.append("saaras:v3\r\n".data(using: .utf8)!)
        
        // with_timestamps parameter
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"with_timestamps\"\r\n\r\n".data(using: .utf8)!)
        data.append("true\r\n".data(using: .utf8)!)
        
        // file parameter
        let fileData = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        data.append("--\(boundary)\r\n".data(using: .utf8)!)
        data.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        data.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        data.append(fileData)
        data.append("\r\n".data(using: .utf8)!)
        
        // End of form
        data.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return data
    }
}

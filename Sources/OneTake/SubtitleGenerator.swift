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
    
    struct WordTiming {
        let word: String
        let startTime: Double
        let endTime: Double
    }
    
    struct SRTSegment {
        let index: Int
        let startTime: Double
        let endTime: Double
        let text: String
        var words: [WordTiming] = []
        
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
    
    // MARK: - Tokenize and Interpolate helper
    
    /// Splits composite phrase-level timestamps from the API response into word-level ones by distributing duration proportionally to character count.
    static func tokenizeAndInterpolate(timestamps: [SarvamTimestamp]) -> [SarvamTimestamp] {
        var result: [SarvamTimestamp] = []
        for ts in timestamps {
            let words = ts.word.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            if words.count <= 1 {
                result.append(ts)
            } else {
                let totalChars = words.reduce(0) { $0 + $1.count }
                guard totalChars > 0 else { continue }
                
                let duration = ts.endTimeSeconds - ts.startTimeSeconds
                var currentStart = ts.startTimeSeconds
                
                for word in words {
                    let wordDuration = duration * (Double(word.count) / Double(totalChars))
                    let currentEnd = currentStart + wordDuration
                    result.append(
                        SarvamTimestamp(
                            word: word,
                            startTimeSeconds: currentStart,
                            endTimeSeconds: currentEnd
                        )
                    )
                    currentStart = currentEnd
                }
            }
        }
        return result
    }
    
    /// Generates individual segments from response timing info
    static func generateSRTSegments(from response: SarvamResponse, style: SubtitleStyle, duration: Double? = nil) -> [SRTSegment] {
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
        
        // Proactively expand/tokenize word blocks that may contain multiple words (e.g. from Sarvam API)
        reconstructedTimestamps = tokenizeAndInterpolate(timestamps: reconstructedTimestamps)
        
        guard !reconstructedTimestamps.isEmpty else {
            // Fallback: entire transcript as a single block if no timestamps are present
            if let transcript = response.transcript, !transcript.isEmpty {
                let end = min(duration ?? 5.0, 5.0)
                return [SRTSegment(index: 1, startTime: 0.0, endTime: end, text: transcript, words: [])]
            }
            return []
        }
        
        var segments: [SRTSegment] = []
        
        var currentIndex = 1
        var groupWords: [WordTiming] = []
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
                let text = groupWords.map { $0.word }.joined(separator: " ")
                let segment = SRTSegment(
                    index: currentIndex,
                    startTime: groupStart ?? 0.0,
                    endTime: groupEnd,
                    text: text,
                    words: groupWords
                )
                segments.append(segment)
                
                currentIndex += 1
                groupWords = [WordTiming(word: word, startTime: wordStart, endTime: wordEnd)]
                groupStart = wordStart
                groupEnd = wordEnd
            } else {
                groupWords.append(WordTiming(word: word, startTime: wordStart, endTime: wordEnd))
                groupEnd = wordEnd
            }
        }
        
        if !groupWords.isEmpty {
            let text = groupWords.map { $0.word }.joined(separator: " ")
            let segment = SRTSegment(
                index: currentIndex,
                startTime: groupStart ?? 0.0,
                endTime: groupEnd,
                text: text,
                words: groupWords
            )
            segments.append(segment)
        }
        
        return segments
    }
    
    /// Converts Sarvam response into a standard SRT subtitle string
    static func generateSRT(from response: SarvamResponse, style: SubtitleStyle, duration: Double? = nil) -> String {
        let segments = generateSRTSegments(from: response, style: style, duration: duration)
        return segments.map { $0.srtFormat }.joined()
    }
    
    // MARK: - Post-Processing Subtitle Burn-In
    
    /// Bakes parsed subtitles directly onto the video frames of the recorded file
    static func burnSubtitles(
        videoURL: URL,
        segments: [SRTSegment],
        style: SubtitleStyle,
        fontSize: SubtitleFontSize = .medium,
        textColor: SubtitleTextColor = .white,
        bgOpacity: Double = 0.6
    ) async throws -> URL {
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
        
        // Thread-safe image cache for rendered subtitles
        let cacheLock = NSLock()
        var imageCache: [String: CIImage] = [:]
        
        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let sourceImage = request.sourceImage
            let time = request.compositionTime.seconds
            let canvasSize = sourceImage.extent.size
            
            if let activeSegment = segments.first(where: { time >= $0.startTime && time <= $0.endTime }) {
                let isWordByWord = (style == .wordByWord)
                var activeWordIndex: Int? = nil
                if isWordByWord {
                    activeWordIndex = activeSegment.words.firstIndex(where: { time >= $0.startTime && time <= $0.endTime })
                }
                
                let activeIdxStr = activeWordIndex != nil ? "\(activeWordIndex!)" : "nil"
                let cacheKey = "\(activeSegment.text)_\(activeIdxStr)_\(canvasSize.width)x\(canvasSize.height)"
                
                cacheLock.lock()
                let cachedImage = imageCache[cacheKey]
                cacheLock.unlock()
                
                if let cachedImage = cachedImage {
                    let outputImage = cachedImage.composited(over: sourceImage)
                    request.finish(with: outputImage, context: nil)
                    return
                }
                
                if let textImage = drawSubtitleImage(
                    text: activeSegment.text,
                    words: activeSegment.words,
                    isWordByWord: isWordByWord,
                    activeWordIndex: activeWordIndex,
                    canvasSize: canvasSize,
                    fontSize: fontSize,
                    textColor: textColor,
                    bgOpacity: bgOpacity
                ) {
                    cacheLock.lock()
                    imageCache[cacheKey] = textImage
                    cacheLock.unlock()
                    
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
    private static func drawSubtitleImage(
        text: String,
        words: [WordTiming],
        isWordByWord: Bool,
        activeWordIndex: Int?,
        canvasSize: CGSize,
        fontSize: SubtitleFontSize,
        textColor: SubtitleTextColor,
        bgOpacity: Double
    ) -> CIImage? {
        let padding: CGFloat = 12.0
        let maxTextWidth = canvasSize.width * 0.8
        let actualFontSize = fontSize.size(for: canvasSize.height)
        
        let font = NSFont.systemFont(ofSize: actualFontSize, weight: .semibold)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping
        
        // Build Attributed String
        let attributedString = NSMutableAttributedString()
        let highlightColor = textColor.color
        let mutedColor = NSColor.white.withAlphaComponent(0.4)
        
        if words.isEmpty {
            attributedString.append(NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: highlightColor,
                .paragraphStyle: paragraphStyle
            ]))
        } else {
            for (idx, w) in words.enumerated() {
                if idx > 0 {
                    attributedString.append(NSAttributedString(string: " ", attributes: [
                        .font: font,
                        .foregroundColor: mutedColor,
                        .paragraphStyle: paragraphStyle
                    ]))
                }
                
                let isHighlighted: Bool
                if let activeIdx = activeWordIndex {
                    isHighlighted = (idx == activeIdx)
                } else {
                    isHighlighted = !isWordByWord
                }
                
                let color = isHighlighted ? highlightColor : mutedColor
                attributedString.append(NSAttributedString(string: w.word, attributes: [
                    .font: font,
                    .foregroundColor: color,
                    .paragraphStyle: paragraphStyle
                ]))
            }
        }
        
        let constraintSize = CGSize(width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude)
        let textRect = attributedString.boundingRect(with: constraintSize, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        
        let textWidth = ceil(textRect.width)
        let textHeight = ceil(textRect.height)
        
        let boxWidth = textWidth + padding * 2
        let boxHeight = textHeight + padding * 2
        
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
        NSColor.black.withAlphaComponent(bgOpacity).setFill()
        path.fill()
        
        // Render text Centered
        let textDrawRect = CGRect(
            x: padding,
            y: padding,
            width: textWidth,
            height: textHeight
        )
        attributedString.draw(in: textDrawRect)
        
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

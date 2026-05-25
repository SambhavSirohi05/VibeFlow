import Foundation

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
    
    /// Converts Sarvam timestamps into a standard SRT subtitle string
    static func generateSRT(from response: SarvamResponse, style: SubtitleStyle) -> String {
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
                let segment = SRTSegment(index: 1, startTime: 0.0, endTime: 5.0, text: transcript)
                return segment.srtFormat
            }
            return ""
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
        
        return segments.map { $0.srtFormat }.joined()
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

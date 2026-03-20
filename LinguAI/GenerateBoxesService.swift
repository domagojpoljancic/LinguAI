//
//  GenerateBoxesService.swift
//  LinguAI
//
//  API client and models for POST /generate-boxes. Matches backend contract exactly.
//

import Foundation

// MARK: - Configuration

enum GenerateBoxesAPI {
    /// Base URL for the LinguAI LangGraph API.
    /// Default `http://localhost:2024` works for Simulator (localhost = host Mac). For a physical device or production, set the custom key `LINGUAI_API_BASE_URL` in the app target’s Info (Custom iOS Target Properties) to your server URL.
    static var baseURL: URL {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "LINGUAI_API_BASE_URL") as? String,
              let url = URL(string: urlString),
              !urlString.isEmpty else {
            return URL(string: "http://localhost:2024")!
        }
        return url
    }

    static func generateBoxesURL() -> URL {
        baseURL.appending(path: "generate-boxes")
    }

    /// Stable customer ID for idempotency (same device = same customer). Persisted in UserDefaults.
    static var customerId: String {
        let key = "LinguAI.generateBoxes.customerId"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }
}

// MARK: - Request models (match backend schemas)

struct WordInBoxRequest: Codable {
    let `default`: String
    let target: String

    enum CodingKeys: String, CodingKey {
        case `default`, target
    }
}

struct ExistingBoxRequest: Codable {
    let boxId: String
    let boxName: String
    let completionPercent: Double
    let words: [WordInBoxRequest]

    enum CodingKeys: String, CodingKey {
        case boxId, boxName, completionPercent, words
    }
}

struct GenerateBoxesRequest: Codable {
    let requestId: String
    let customerId: String
    let prompt: String
    let defaultLanguage: String
    let targetLanguage: String
    let existingBoxes: [ExistingBoxRequest]
}

// MARK: - Response models (match backend schemas)

struct WordPairResponse: Codable {
    let `default`: String
    let target: String

    enum CodingKeys: String, CodingKey {
        case `default`, target
    }
}

struct GeneratedBoxResponse: Codable {
    let boxId: String
    let boxName: String
    let words: [WordPairResponse]
}

struct GenerateBoxesResponse: Codable {
    let requestId: String
    let defaultLanguage: String
    let targetLanguage: String
    let status: String
    let userMessage: String?
    let boxes: [GeneratedBoxResponse]
    let level: String?
    let levelSource: String?
    let topic: String?
    let topicSource: String?
    let topicConfidence: Double?
    let topicReason: String?
    let topicKeywords: [String]?
    let situationLabel: String?
    let reachedBoxCreation: Bool
}

// MARK: - Status constants (match backend)

enum GenerateBoxesStatus {
    static let generatedPlaceholder = "generated_placeholder"
    static let irrelevantRequest = "irrelevant_request"
    static let insufficientConfidence = "insufficient_confidence"
    static let generationEmpty = "generation_empty"
}

// MARK: - Service

enum GenerateBoxesServiceError: Error {
    case invalidURL
    case httpError(statusCode: Int)
    case idempotencyConflict(detail: String)
    case decodingError(Error)
    case networkError(Error)
}

/// 409 response body from backend when (customerId, requestId) was already used with a different payload.
private struct IdempotencyConflictBody: Codable {
    let detail: String
}

// MARK: - Request/response logging

/// Writes all generate-boxes requests and responses to a single log file in Caches for debugging.
private enum GenerateBoxesAPILog {
    private static let queue = DispatchQueue(label: "com.linguai.generateBoxesAPILog")
    private static let logFileName = "generate_boxes_api.log"

    static func log(
        request: GenerateBoxesRequest,
        requestBodyData: Data?,
        responseData: Data?,
        statusCode: Int?,
        error: Error?
    ) {
        queue.async {
            let entry = formatEntry(
                request: request,
                requestBodyData: requestBodyData,
                responseData: responseData,
                statusCode: statusCode,
                error: error
            )
            guard let url = logFileURL(), let data = entry.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private static func logFileURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(logFileName)
    }

    private static func formatEntry(
        request: GenerateBoxesRequest,
        requestBodyData: Data?,
        responseData: Data?,
        statusCode: Int?,
        error: Error?
    ) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = iso.string(from: Date())
        var lines: [String] = [
            "----------",
            "[\(ts)] POST \(GenerateBoxesAPI.generateBoxesURL().absoluteString)",
            "REQUEST requestId=\(request.requestId) promptLength=\(request.prompt.count) existingBoxes=\(request.existingBoxes.count)",
        ]
        if let body = requestBodyData, let str = String(data: body, encoding: .utf8) {
            lines.append(str)
        }
        if let err = error {
            lines.append("RESPONSE error=\(err.localizedDescription)")
        } else if let code = statusCode {
            lines.append("RESPONSE statusCode=\(code)")
            if let data = responseData, let str = String(data: data, encoding: .utf8) {
                lines.append(str)
            }
        }
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

/// Calls POST /generate-boxes and returns the decoded response or throws.
func callGenerateBoxes(
    request: GenerateBoxesRequest,
    session: URLSession = .shared
) async throws -> GenerateBoxesResponse {
    let url = GenerateBoxesAPI.generateBoxesURL()
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .useDefaultKeys
    let bodyData = try encoder.encode(request)
    urlRequest.httpBody = bodyData

    var statusCode: Int?
    var resultError: Error?

    do {
        let (data, response) = try await session.data(for: urlRequest)
        statusCode = (response as? HTTPURLResponse)?.statusCode

        guard let http = response as? HTTPURLResponse else {
            resultError = GenerateBoxesServiceError.httpError(statusCode: 0)
            GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: data, statusCode: statusCode, error: resultError)
            throw resultError!
        }

        if http.statusCode == 409 {
            let detail = (try? JSONDecoder().decode(IdempotencyConflictBody.self, from: data).detail) ?? "Idempotency conflict."
            resultError = GenerateBoxesServiceError.idempotencyConflict(detail: detail)
            GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: data, statusCode: 409, error: resultError)
            throw resultError!
        }

        guard (200...299).contains(http.statusCode) else {
            resultError = GenerateBoxesServiceError.httpError(statusCode: http.statusCode)
            GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: data, statusCode: http.statusCode, error: resultError)
            throw resultError!
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        do {
            let decoded = try decoder.decode(GenerateBoxesResponse.self, from: data)
            GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: data, statusCode: http.statusCode, error: nil)
            return decoded
        } catch {
            resultError = GenerateBoxesServiceError.decodingError(error)
            GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: data, statusCode: http.statusCode, error: resultError)
            throw resultError!
        }
    } catch {
        resultError = error
        GenerateBoxesAPILog.log(request: request, requestBodyData: bodyData, responseData: nil, statusCode: nil, error: error)
        throw error
    }
}

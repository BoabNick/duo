//
//  SpinConnectorClient.swift
//  DUOPAY
//
//  Integration layer for the "Foodteria SPIn Connector" — a small backend
//  (https://github.com/.../allprodemo) that bridges this app to a Dejavoo
//  Z-series terminal over SPIn Cloud. DUOPAY talks to the connector's
//  /v1/* REST API; the connector talks to the terminal.
//
//  This file is dependency-free (Foundation only) so it can be dropped into
//  the project on its own. SpinPOSConnector.swift builds the app-facing
//  connector on top of it.
//

import Foundation

// MARK: - Configuration

/// Persisted connector settings, backed by UserDefaults so the same keys can
/// be read here and bound directly with @AppStorage in SwiftUI.
enum SpinConnectorConfig {
    static let baseURLKey = "spin_connector_base_url"
    static let registerIDKey = "spin_connector_register_id"
    static let apiKeyKey = "spin_connector_api_key"
    static let enabledKey = "spin_connector_enabled"

    /// e.g. "https://connector.example.com" or "http://192.168.1.50:3000" (no trailing slash needed)
    static var baseURL: String {
        UserDefaults.standard.string(forKey: baseURLKey) ?? ""
    }

    /// SPIn RegisterId from the Dejavoo/iPOSpays portal, OR the connector's
    /// internal register id — register.repository.ts resolves either one.
    static var registerID: String {
        UserDefaults.standard.string(forKey: registerIDKey) ?? ""
    }

    /// Optional. Only required if the connector was started with CONNECTOR_API_KEY set.
    static var apiKey: String {
        UserDefaults.standard.string(forKey: apiKeyKey) ?? ""
    }

    /// Master switch — when off, DUOPAY falls back to its existing POS connector.
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    static var isConfigured: Bool {
        !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !registerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Enums

enum SpinPaymentStatus: String, Codable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case declined = "DECLINED"
    case timeout = "TIMEOUT"
    case voided = "VOIDED"
    case refunded = "REFUNDED"
    case error = "ERROR"

    var isSuccessful: Bool { self == .approved }

    var displayColor: String {
        switch self {
        case .approved: return "green"
        case .declined, .error: return "red"
        case .timeout: return "orange"
        case .voided, .refunded: return "gray"
        case .pending: return "blue"
        }
    }
}

/// Mirrors SaleRequest.paymentType from packages/shared-types.
enum SpinPaymentType: String, CaseIterable {
    case credit = "Credit"
    case debit = "Debit"
    case ebtFood = "EBT_Food"
    case ebtCash = "EBT_Cash"
    case userChoice = "userChoice"
    case gift = "Gift"
}

// MARK: - Wire models (mirror packages/shared-types/src/index.ts)

struct SpinParsedResponse: Codable {
    let refId: String?
    let registerId: String?
    let authCode: String?
    let pnRef: String?
    let transNum: String?
    let resultCode: String?
    let message: String?
    let respMsg: String?
    let paymentType: String?
    let voided: Bool?
    let transType: String?
    let serialNumber: String?
    let extData: String?
    let hostResponseCode: String?
    let hostResponseMessage: String?
    let batchNum: String?
    let approved: Bool
    let timedOut: Bool
    let raw: String?

    /// Best available human-readable message from the terminal/host.
    var displayMessage: String? {
        message ?? respMsg ?? hostResponseMessage
    }
}

/// Mirrors PaymentRecord — the shape returned by /v1/payments/* endpoints.
struct SpinPaymentRecord: Codable, Identifiable {
    let id: String
    let registerId: String
    let foodteriaOrderId: String
    let refId: String
    let amount: String
    let tipAmount: String
    let status: SpinPaymentStatus
    let paymentType: String
    let transType: String
    let authCode: String?
    let batchId: String?
    let errorMessage: String?
    let spinResponse: SpinParsedResponse?
    let createdAt: String
    let updatedAt: String

    var amountValue: Double { Double(amount) ?? 0 }
    var tipValue: Double { Double(tipAmount) ?? 0 }
    var totalValue: Double { amountValue + tipValue }
}

/// Mirrors the JSON body returned by POST /v1/batches/close
struct SpinBatchCloseResult: Codable {
    let registerId: String
    let spinRegisterId: String?
    let approved: Bool
    let message: String?
    let batchNum: String?
    let raw: String?
}

/// Mirrors the JSON body returned by POST /v1/registers/:id/test-connection
struct SpinRegisterConnectionResult: Codable {
    let registerId: String
    let spinRegisterId: String?
    let authKeyConfigured: Bool
    let tpn: String?
    let connected: Bool
    let response: SpinParsedResponse?
}

/// Error shape from middleware/error-handler.ts: { "error": "...", "code": "..." }
private struct SpinAPIErrorBody: Decodable {
    let error: String
    let code: String?
}

// MARK: - Request bodies

struct SpinSaleRequest: Encodable {
    var registerId: String
    var foodteriaOrderId: String
    var amount: String
    var tip: String?
    var paymentType: String = SpinPaymentType.credit.rawValue
    var idempotencyKey: String?
    var tag1: String?
    var tag2: String?
    var tag3: String?
    var performedBy: String?
}

struct SpinRefundRequest: Encodable {
    var amount: String
    var reason: String?
}

struct SpinTipAdjustRequest: Encodable {
    var tip: String
}

struct SpinBatchCloseRequest: Encodable {
    var registerId: String
    var paymentType: String = "Credit"
}

// MARK: - Errors

enum SpinConnectorError: LocalizedError {
    case notConfigured
    case invalidURL
    case server(status: Int, message: String, code: String?)
    case decoding(Error)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "SPIn connector isn't configured. Set the connector URL and register ID in SPIn Integration settings."
        case .invalidURL:
            return "The SPIn connector URL is invalid."
        case .server(let status, let message, let code):
            if let code { return "\(message) (\(code), HTTP \(status))" }
            return "\(message) (HTTP \(status))"
        case .decoding:
            return "Couldn't read the response from the SPIn connector."
        case .network(let err):
            return err.localizedDescription
        }
    }
}

// MARK: - Client

/// Thin async/await wrapper around the connector's /v1 REST API.
final class FoodteriaSpinClient {
    static let shared = FoodteriaSpinClient()

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: Payments — POST /v1/payments/sale

    func sale(_ body: SpinSaleRequest) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/sale", method: "POST", body: body)
    }

    func getPayment(id: String) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/\(id)")
    }

    func voidPayment(id: String) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/\(id)/void", method: "POST")
    }

    func refund(id: String, body: SpinRefundRequest) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/\(id)/refund", method: "POST", body: body)
    }

    func tipAdjust(id: String, body: SpinTipAdjustRequest) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/\(id)/tip-adjust", method: "POST", body: body)
    }

    func checkStatus(id: String) async throws -> SpinPaymentRecord {
        try await send(path: "/v1/payments/\(id)/status")
    }

    // MARK: Registers — POST /v1/registers/:id/test-connection

    func testConnection() async throws -> SpinRegisterConnectionResult {
        let register = SpinConnectorConfig.registerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !register.isEmpty else { throw SpinConnectorError.notConfigured }
        return try await send(
            path: "/v1/registers/\(register)/test-connection",
            method: "POST"
        )
    }

    // MARK: Batches — POST /v1/batches/close

    func closeBatch(paymentType: String = "Credit") async throws -> SpinBatchCloseResult {
        let register = SpinConnectorConfig.registerID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !register.isEmpty else { throw SpinConnectorError.notConfigured }
        let body = SpinBatchCloseRequest(registerId: register, paymentType: paymentType)
        return try await send(path: "/v1/batches/close", method: "POST", body: body)
    }

    // MARK: - Core request plumbing

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        let (data, http) = try await rawRequest(path: path, method: method, bodyData: nil)
        return try decodeOrThrow(data: data, response: http)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body
    ) async throws -> Response {
        let bodyData: Data
        do {
            bodyData = try encoder.encode(body)
        } catch {
            throw SpinConnectorError.decoding(error)
        }
        let (data, http) = try await rawRequest(path: path, method: method, bodyData: bodyData)
        return try decodeOrThrow(data: data, response: http)
    }

    private func rawRequest(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> (Data, HTTPURLResponse) {
        guard let base = normalizedBaseURL else { throw SpinConnectorError.notConfigured }
        guard let url = URL(string: base + path) else { throw SpinConnectorError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let apiKey = SpinConnectorConfig.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SpinConnectorError.network(URLError(.badServerResponse))
            }
            return (data, http)
        } catch let error as SpinConnectorError {
            throw error
        } catch {
            throw SpinConnectorError.network(error)
        }
    }

    /// 200/201 decode normally. 402 is special-cased because POST /v1/payments/sale
    /// returns 402 for a *successfully processed but declined* sale — the body is
    /// still a valid PaymentRecord, not an error envelope.
    private func decodeOrThrow<Response: Decodable>(
        data: Data,
        response: HTTPURLResponse
    ) throws -> Response {
        if (200...299).contains(response.statusCode) || response.statusCode == 402 {
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw SpinConnectorError.decoding(error)
            }
        }

        if let body = try? decoder.decode(SpinAPIErrorBody.self, from: data) {
            throw SpinConnectorError.server(status: response.statusCode, message: body.error, code: body.code)
        }

        let message = String(data: data, encoding: .utf8) ?? "HTTP \(response.statusCode)"
        throw SpinConnectorError.server(status: response.statusCode, message: message, code: nil)
    }

    private var normalizedBaseURL: String? {
        let raw = SpinConnectorConfig.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }
}

// MARK: - Helpers

enum SpinAmount {
    /// SPIn wants amounts as decimal strings with a '.' separator, e.g. "25.50",
    /// regardless of device locale.
    static func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

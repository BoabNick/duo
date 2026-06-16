//
//  SpinPOSConnector.swift
//  DUOPAY
//
//  Adapts the Foodteria SPIn Connector (SpinConnectorClient.swift) to DUOPAY's
//  POSConnector protocol so a Dejavoo terminal can be used as a payment
//  method alongside Square / Stripe, plus exposes the richer sale / refund /
//  void / batch-close calls for the checkout, transactions, and back-office
//  flows.
//
//  Assumed existing protocol (from ContentView.swift's `payViaPOS`):
//
//      protocol POSConnector {
//          func processPayment(amount: Double) async -> Bool
//      }
//
//  If your actual POSConnector signature differs, only the conformance
//  extension at the bottom needs to change — everything else here is
//  self-contained.
//

import Foundation
import Combine

@MainActor
final class SpinPOSConnector: ObservableObject, POSConnector {

    // MARK: Published state for UI binding

    @Published private(set) var isProcessing = false
    @Published private(set) var lastPayment: SpinPaymentRecord?
    @Published private(set) var lastError: String?

    private let client: FoodteriaSpinClient

    init(client: FoodteriaSpinClient = .shared) {
        self.client = client
    }

    // MARK: - Rich API used by the checkout / transactions / back office UI

    /// Charges a card sale through the configured Dejavoo terminal.
    ///
    /// - orderId: a stable identifier for this sale (e.g. DUOPAY's internal
    ///   transaction id). Used as `foodteriaOrderId` and as part of the
    ///   idempotency key the connector uses to dedupe retried requests.
    @discardableResult
    func chargeSale(
        amount: Double,
        tip: Double = 0,
        orderId: String,
        paymentType: SpinPaymentType = .credit,
        performedBy: String? = nil
    ) async -> Result<SpinPaymentRecord, SpinConnectorError> {
        guard SpinConnectorConfig.isConfigured else {
            let error = SpinConnectorError.notConfigured
            lastError = error.localizedDescription
            return .failure(error)
        }

        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let request = SpinSaleRequest(
            registerId: SpinConnectorConfig.registerID.trimmingCharacters(in: .whitespacesAndNewlines),
            foodteriaOrderId: orderId,
            amount: SpinAmount.format(amount),
            tip: tip > 0 ? SpinAmount.format(tip) : nil,
            paymentType: paymentType.rawValue,
            idempotencyKey: Self.idempotencyKey(for: orderId),
            performedBy: performedBy ?? "DUOPAY"
        )

        do {
            let record = try await client.sale(request)
            lastPayment = record
            if !record.status.isSuccessful {
                lastError = record.errorMessage
                    ?? record.spinResponse?.displayMessage
                    ?? "Payment \(record.status.rawValue.lowercased())"
            }
            return .success(record)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Voids an approved payment (same-day reversal, before batch close).
    @discardableResult
    func voidPayment(paymentId: String) async -> Result<SpinPaymentRecord, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let record = try await client.voidPayment(id: paymentId)
            lastPayment = record
            if record.status != .voided {
                lastError = record.errorMessage ?? record.spinResponse?.displayMessage
            }
            return .success(record)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Refunds a previously settled payment. Used by DUOPAY's Refund flow.
    @discardableResult
    func refundPayment(
        paymentId: String,
        amount: Double,
        reason: String? = nil
    ) async -> Result<SpinPaymentRecord, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let record = try await client.refund(
                id: paymentId,
                body: SpinRefundRequest(amount: SpinAmount.format(amount), reason: reason)
            )
            lastPayment = record
            if record.status != .refunded {
                lastError = record.errorMessage ?? record.spinResponse?.displayMessage
            }
            return .success(record)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Adjusts the tip on an approved payment (e.g. after a printed-receipt tip entry).
    @discardableResult
    func adjustTip(paymentId: String, tip: Double) async -> Result<SpinPaymentRecord, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let record = try await client.tipAdjust(
                id: paymentId,
                body: SpinTipAdjustRequest(tip: SpinAmount.format(tip))
            )
            lastPayment = record
            return .success(record)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Re-queries the terminal/host for the current status of a payment
    /// (useful after a TIMEOUT, or to confirm a sale before printing a receipt).
    @discardableResult
    func checkStatus(paymentId: String) async -> Result<SpinPaymentRecord, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let record = try await client.checkStatus(id: paymentId)
            lastPayment = record
            return .success(record)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Verifies the configured register can reach the terminal/host.
    @discardableResult
    func testConnection() async -> Result<SpinRegisterConnectionResult, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let result = try await client.testConnection()
            if !result.connected {
                lastError = result.response?.displayMessage ?? "Terminal not reachable"
            }
            return .success(result)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Closes the current batch on the terminal — pairs with DUOPAY's batch tracking.
    @discardableResult
    func closeBatch(paymentType: String = "Credit") async -> Result<SpinBatchCloseResult, SpinConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let result = try await client.closeBatch(paymentType: paymentType)
            if !result.approved {
                lastError = result.message ?? "Batch close failed"
            }
            return .success(result)
        } catch {
            return .failure(fail(error))
        }
    }

    // MARK: - Helpers

    private func fail(_ error: Error) -> SpinConnectorError {
        let connectorError = (error as? SpinConnectorError) ?? .network(error)
        lastError = connectorError.localizedDescription
        return connectorError
    }

    /// One idempotency key per call. SPIn caches the result for 24h, so a
    /// second tap with the *same* orderId (e.g. a retry) reuses this key —
    /// pass a per-attempt suffix in `orderId` if you want every tap to be a
    /// distinct charge attempt.
    private static func idempotencyKey(for orderId: String) -> String {
        let cleaned = orderId.replacingOccurrences(of: " ", with: "-")
        return "duopay-\(cleaned)"
    }
}

// MARK: - POSConnector conformance

extension SpinPOSConnector {
    /// Charges the full amount as a single Credit sale with no tip, and
    /// reports simple success/failure — matches the existing
    /// `posConnector.processPayment(amount:)` call in `payViaPOS`.
    func processPayment(amount: Double) async -> Bool {
        let orderId = "duopay-\(Int(Date().timeIntervalSince1970 * 1000))"
        switch await chargeSale(amount: amount, orderId: orderId) {
        case .success(let record):
            return record.status.isSuccessful
        case .failure:
            return false
        }
    }
}

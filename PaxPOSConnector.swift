//
//  PaxPOSConnector.swift
//  DUOPAY
//
//  Adapts the PAX A-series terminal client (PaxConnectorClient.swift) to
//  DUOPAY's POSConnector protocol, exposing sale / void / refund / batch-close
//  for the checkout, transactions, and back-office flows.
//
//  PAX terminals communicate over Ethernet (TCP/IP) on a configurable local
//  network port (typically 10001, ISO 8583 protocol). This connector wraps that
//  into DUOPAY's async/await interface with proper error handling and state.
//

import Foundation
import Combine

@MainActor
final class PaxPOSConnector: ObservableObject, POSConnector {

    @Published private(set) var isProcessing = false
    @Published private(set) var lastTransaction: PaxTransactionResponse?
    @Published private(set) var lastError: String?

    private let client: PaxTerminalClient

    init(client: PaxTerminalClient = .shared) {
        self.client = client
    }

    // MARK: - Rich API for checkout / transactions / back office

    /// Charges a card sale through the connected PAX A-series terminal.
    ///
    /// - orderId: Stable reference for this sale (e.g. DUOPAY's transaction ID)
    /// - cardholderName: Optional name displayed on terminal (for receipts)
    @discardableResult
    func chargeSale(
        amount: Double,
        tip: Double = 0,
        orderId: String,
        cardholderName: String? = nil,
        timeout: TimeInterval = 30
    ) async -> Result<PaxTransactionResponse, PaxConnectorError> {
        guard PaxConnectorConfig.isConfigured else {
            let error = PaxConnectorError.notConfigured
            lastError = error.localizedDescription
            return .failure(error)
        }

        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        let request = PaxTransactionRequest(
            amount: Decimal(Int(amount * 100)), // convert to cents
            tip: Decimal(Int(tip * 100)),
            orderId: orderId,
            cardholderName: cardholderName,
            timeout: timeout
        )

        do {
            let transaction = try await client.sale(request: request)
            lastTransaction = transaction
            if !transaction.approved {
                lastError = transaction.displayMessage
            }
            return .success(transaction)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Voids a previous sale (same-day reversal, terminal permitting).
    @discardableResult
    func voidTransaction(
        referenceNumber: String,
        orderId: String,
        timeout: TimeInterval = 30
    ) async -> Result<PaxTransactionResponse, PaxConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let transaction = try await client.void(referenceNumber: referenceNumber, orderId: orderId, timeout: timeout)
            lastTransaction = transaction
            if !transaction.approved {
                lastError = transaction.displayMessage
            }
            return .success(transaction)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Refunds a previous sale.
    @discardableResult
    func refundTransaction(
        amount: Double,
        orderId: String,
        timeout: TimeInterval = 30
    ) async -> Result<PaxTransactionResponse, PaxConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let transaction = try await client.refund(
                amount: Decimal(Int(amount * 100)),
                orderId: orderId,
                timeout: timeout
            )
            lastTransaction = transaction
            if !transaction.approved {
                lastError = transaction.displayMessage
            }
            return .success(transaction)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Closes the batch on the terminal (end-of-day settlement).
    @discardableResult
    func closeBatch(timeout: TimeInterval = 60) async -> Result<PaxBatchCloseResponse, PaxConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let batch = try await client.batchClose(timeout: timeout)
            if !batch.approved {
                lastError = batch.message ?? "Batch close failed"
            }
            return .success(batch)
        } catch {
            return .failure(fail(error))
        }
    }

    /// Pings the terminal to verify connectivity.
    @discardableResult
    func testConnection(timeout: TimeInterval = 5) async -> Result<Bool, PaxConnectorError> {
        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        do {
            let reachable = try await client.ping(timeout: timeout)
            return .success(reachable)
        } catch {
            return .failure(fail(error))
        }
    }

    // MARK: - Helpers

    private func fail(_ error: Error) -> PaxConnectorError {
        let connectorError = (error as? PaxConnectorError) ?? .sendFailed(error)
        lastError = connectorError.localizedDescription
        return connectorError
    }
}

// MARK: - POSConnector conformance

extension PaxPOSConnector {
    /// Simple payment interface — charges the amount with no tip.
    func processPayment(amount: Double) async -> Bool {
        let orderId = "duopay-\(Int(Date().timeIntervalSince1970 * 1000))"
        switch await chargeSale(amount: amount, orderId: orderId) {
        case .success(let transaction):
            return transaction.approved
        case .failure:
            return false
        }
    }
}

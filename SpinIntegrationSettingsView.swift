//
//  SpinIntegrationSettingsView.swift
//  DUOPAY
//
//  Configuration + diagnostics screen for the Foodteria SPIn Connector
//  integration. Lets the merchant point DUOPAY at their connector instance,
//  verify the Dejavoo terminal is reachable, run a test sale, and close the
//  terminal batch — without leaving the app.
//
//  Wire-up (see ContentView.swift):
//
//      @StateObject private var spinConnector = SpinPOSConnector()
//      ...
//      .sheet(isPresented: $showingSpinSettings) {
//          SpinIntegrationSettingsView(connector: spinConnector)
//      }
//

import SwiftUI

struct SpinIntegrationSettingsView: View {
    @AppStorage("selected_language") private var selectedLanguage = "fr"

    @AppStorage(SpinConnectorConfig.enabledKey) private var isEnabled: Bool = false
    @AppStorage(SpinConnectorConfig.baseURLKey) private var baseURL: String = ""
    @AppStorage(SpinConnectorConfig.registerIDKey) private var registerID: String = ""
    @AppStorage(SpinConnectorConfig.apiKeyKey) private var apiKey: String = ""

    @ObservedObject var connector: SpinPOSConnector
    @Environment(\.dismiss) private var dismiss

    @State private var testAmountText: String = "1.00"
    @State private var connectionResult: SpinRegisterConnectionResult?
    @State private var batchResult: SpinBatchCloseResult?
    @State private var isTestingConnection = false
    @State private var isClosingBatch = false

    // Per-action error messages. Kept local (rather than reading the shared
    // connector.lastError directly) so a failure in one section doesn't bleed
    // its message into the others.
    @State private var connectionError: String?
    @State private var saleError: String?
    @State private var batchError: String?

    private var configured: Bool {
        !baseURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !registerID.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationView {
            Form {
                connectorSection
                connectionTestSection
                testSaleSection
                batchSection
                aboutSection
            }
            .navigationTitle(t("SPIn Integration", "Intégration SPIn"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("Done", "Terminé")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var connectorSection: some View {
        Section(header: Text(t("Connector", "Connecteur"))) {
            Toggle(
                t("Use SPIn terminal for card payments", "Utiliser le terminal SPIn pour les cartes"),
                isOn: $isEnabled
            )

            TextField(t("Connector URL", "URL du connecteur"), text: $baseURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            TextField(t("Register ID", "ID du terminal"), text: $registerID)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

            SecureField(t("API key (optional)", "Clé API (optionnelle)"), text: $apiKey)

            if !configured {
                Text(t(
                    "Enter the connector URL and register ID to enable SPIn payments.",
                    "Entrez l'URL du connecteur et l'ID du terminal pour activer les paiements SPIn."
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var connectionTestSection: some View {
        Section(header: Text(t("Connection test", "Test de connexion"))) {
            Button {
                Task { await runTestConnection() }
            } label: {
                HStack {
                    if isTestingConnection {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text(t("Test connection", "Tester la connexion"))
                }
            }
            .disabled(!configured || isTestingConnection)

            if let result = connectionResult {
                HStack {
                    Circle()
                        .fill(result.connected ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(result.connected
                         ? t("Terminal reachable", "Terminal accessible")
                         : t("Not reachable", "Inaccessible"))
                        .font(.subheadline)
                }

                if let tpn = result.tpn, !tpn.isEmpty {
                    detailRow(t("TPN", "TPN"), tpn)
                }
                if let msg = result.response?.displayMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = connectionError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var testSaleSection: some View {
        Section(header: Text(t("Test sale", "Vente de test"))) {
            HStack {
                Text("CA$")
                    .foregroundColor(.secondary)
                TextField("0.00", text: $testAmountText)
                    .keyboardType(.decimalPad)
            }

            Button {
                Task { await runTestSale() }
            } label: {
                HStack {
                    if connector.isProcessing {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text(t("Run test sale", "Lancer une vente de test"))
                }
            }
            .disabled(!isEnabled || !configured || connector.isProcessing)

            if let payment = connector.lastPayment {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(t("Status", "Statut"))
                        Spacer()
                        statusBadge(payment.status)
                    }
                    if let auth = payment.authCode {
                        detailRow(t("Auth code", "Code d'autorisation"), auth, monospaced: true)
                    }
                    detailRow(t("Reference", "Référence"), payment.refId, monospaced: true)
                    detailRow(t("Payment ID", "ID paiement"), payment.id, monospaced: true)
                }
                .font(.system(size: 13))
            }

            if let error = saleError {
                Text(error).font(.caption).foregroundColor(.red)
            }

            if !isEnabled {
                Text(t(
                    "Turn on \"Use SPIn terminal\" above to run a live test sale.",
                    "Activez « Utiliser le terminal SPIn » ci-dessus pour lancer une vente de test."
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var batchSection: some View {
        Section(header: Text(t("Batch", "Lot"))) {
            Button {
                Task { await runCloseBatch() }
            } label: {
                HStack {
                    if isClosingBatch {
                        ProgressView().padding(.trailing, 4)
                    }
                    Text(t("Close batch now", "Fermer le lot maintenant"))
                }
            }
            .disabled(!isEnabled || !configured || isClosingBatch)

            if let batch = batchResult {
                HStack {
                    Circle()
                        .fill(batch.approved ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(batch.approved
                         ? t("Batch closed", "Lot fermé")
                         : t("Batch close failed", "Échec de la fermeture du lot"))
                        .font(.subheadline)
                }
                if let num = batch.batchNum {
                    detailRow(t("Batch #", "Lot n°"), num)
                }
                if let msg = batch.message {
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
            }

            if let error = batchError {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var aboutSection: some View {
        Section(footer: Text(t(
            "DUOPAY connects to a Foodteria SPIn connector, which talks to your Dejavoo terminal over SPIn Cloud. Register ID can be the SPIn RegisterId from the Dejavoo/iPOSpays portal, or the connector's internal register ID.",
            "DUOPAY se connecte à un connecteur Foodteria SPIn, qui communique avec votre terminal Dejavoo via SPIn Cloud. L'ID du terminal peut être le RegisterId SPIn (portail Dejavoo/iPOSpays) ou l'ID interne du connecteur."
        ))) {
            EmptyView()
        }
    }

    // MARK: - Subviews

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func statusBadge(_ status: SpinPaymentStatus) -> some View {
        Text(status.rawValue)
            .font(.system(size: 10, weight: .black))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor(status).opacity(0.15))
            .foregroundColor(statusColor(status))
            .cornerRadius(4)
    }

    private func statusColor(_ status: SpinPaymentStatus) -> Color {
        switch status {
        case .approved: return .green
        case .declined, .error: return .red
        case .timeout: return .orange
        case .voided, .refunded: return .gray
        case .pending: return .blue
        }
    }

    // MARK: - Actions

    private func runTestConnection() async {
        isTestingConnection = true
        connectionError = nil
        connectionResult = nil
        defer { isTestingConnection = false }
        switch await connector.testConnection() {
        case .success(let result):
            connectionResult = result
        case .failure(let error):
            connectionError = error.localizedDescription
        }
    }

    private func runTestSale() async {
        let normalized = testAmountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else {
            saleError = t(
                "Enter a valid amount greater than zero.",
                "Entrez un montant valide supérieur à zéro."
            )
            return
        }
        saleError = nil
        let orderId = "DUOPAY-TEST-\(Int(Date().timeIntervalSince1970))"
        switch await connector.chargeSale(amount: amount, orderId: orderId, performedBy: "DUOPAY Settings") {
        case .success:
            // A processed-but-declined sale still returns .success; its message
            // lives in connector.lastError.
            saleError = connector.lastError
        case .failure(let error):
            saleError = error.localizedDescription
        }
    }

    private func runCloseBatch() async {
        isClosingBatch = true
        batchError = nil
        batchResult = nil
        defer { isClosingBatch = false }
        switch await connector.closeBatch() {
        case .success(let result):
            batchResult = result
        case .failure(let error):
            batchError = error.localizedDescription
        }
    }

    // MARK: - Localization

    private func t(_ en: String, _ fr: String) -> String {
        selectedLanguage == "fr" ? fr : en
    }
}

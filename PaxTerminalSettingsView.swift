//
//  PaxTerminalSettingsView.swift
//  DUOPAY
//
//  Configuration + diagnostics screen for PAX A-series terminals connected
//  over Ethernet (local network). Lets the merchant set the terminal's IP
//  address and port, test connectivity, verify the terminal is reachable,
//  and run diagnostic operations — all without leaving the app.
//
//  Wire-up (see ContentView.swift):
//
//      @StateObject private var paxConnector = PaxPOSConnector()
//      ...
//      .sheet(isPresented: $showingPaxSettings) {
//          PaxTerminalSettingsView(connector: paxConnector)
//      }
//

import SwiftUI

struct PaxTerminalSettingsView: View {
    @AppStorage("selected_language") private var selectedLanguage = "fr"

    @AppStorage(PaxConnectorConfig.ipAddressKey) private var ipAddress: String = ""
    @AppStorage(PaxConnectorConfig.portKey) private var portText: String = "10001"
    @AppStorage(PaxConnectorConfig.enabledKey) private var isEnabled: Bool = false

    @ObservedObject var connector: PaxPOSConnector
    @Environment(\.dismiss) private var dismiss

    @State private var testAmountText: String = "1.00"
    @State private var connectionStatus: (reachable: Bool, message: String)? = nil
    @State private var batchResult: PaxBatchCloseResponse? = nil
    @State private var isTestingConnection = false
    @State private var isClosingBatch = false

    private var configured: Bool {
        !ipAddress.trimmingCharacters(in: .whitespaces).isEmpty
            && UInt16(portText) != nil
    }

    var body: some View {
        NavigationView {
            Form {
                terminalSection
                connectionTestSection
                testSaleSection
                batchSection
                aboutSection
            }
            .navigationTitle(t("PAX Terminal", "Terminal PAX"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("Done", "Terminé")) { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var terminalSection: some View {
        Section(header: Text(t("Terminal Settings", "Paramètres du terminal"))) {
            Toggle(
                t("Use PAX A-series terminal for card payments", "Utiliser le terminal PAX pour les cartes"),
                isOn: $isEnabled
            )

            TextField(t("Terminal IP address", "Adresse IP du terminal"), text: $ipAddress)
                .keyboardType(.decimalPad)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .placeholder(when: ipAddress.isEmpty) {
                    Text("192.168.1.100").foregroundColor(.gray)
                }

            HStack {
                Text(t("Port", "Port")).foregroundColor(.secondary)
                Spacer()
                TextField("10001", text: $portText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            if !configured {
                Text(t(
                    "Enter the terminal's IP address and port to enable PAX payments.",
                    "Entrez l'adresse IP et le port du terminal pour activer les paiements PAX."
                ))
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    private var connectionTestSection: some View {
        Section(header: Text(t("Connection", "Connexion"))) {
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

            if let status = connectionStatus {
                HStack {
                    Circle()
                        .fill(status.reachable ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                    Text(status.reachable
                         ? t("Terminal reachable", "Terminal accessible")
                         : t("Terminal not reachable", "Terminal inaccessible"))
                        .font(.subheadline)
                }
                if !status.message.isEmpty {
                    Text(status.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let error = connector.lastError, connectionStatus == nil {
                Text(error).font(.caption).foregroundColor(.red)
            }
        }
    }

    private var testSaleSection: some View {
        Section(header: Text(t("Test Sale", "Vente de test"))) {
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

            if let transaction = connector.lastTransaction {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(t("Status", "Statut"))
                        Spacer()
                        statusBadge(transaction.approved)
                    }
                    if let auth = transaction.authCode {
                        detailRow(t("Auth code", "Code d'autorisation"), auth, monospaced: true)
                    }
                    if let ref = transaction.referenceNumber {
                        detailRow(t("Reference", "Référence"), ref, monospaced: true)
                    }
                    if let txnId = transaction.transactionId {
                        detailRow(t("Transaction ID", "ID transaction"), txnId, monospaced: true)
                    }
                    if let pan = transaction.maskedPan {
                        detailRow(t("Card", "Carte"), pan, monospaced: true)
                    }
                }
                .font(.system(size: 13))
            }

            if let error = connector.lastError {
                Text(error).font(.caption).foregroundColor(.red)
            }

            if !isEnabled {
                Text(t(
                    "Turn on \"Use PAX A-series terminal\" above to run a test sale.",
                    "Activez « Utiliser le terminal PAX » ci-dessus pour lancer une vente de test."
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
                if let num = batch.batchNumber {
                    detailRow(t("Batch #", "Lot n°"), num)
                }
                detailRow(t("Transaction count", "Nombre de transactions"), "\(batch.transactionCount)")
                if let msg = batch.message {
                    Text(msg).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    private var aboutSection: some View {
        Section(footer: Text(t(
            "DUOPAY connects directly to PAX A-series terminals (A80, A920, etc.) over Ethernet using the ISO 8583 protocol on port 10001 (default). The terminal must be on the same local network as the iPad.",
            "DUOPAY se connecte directement aux terminaux PAX A-series (A80, A920, etc.) via Ethernet en utilisant le protocole ISO 8583 sur le port 10001 (par défaut). Le terminal doit être sur le même réseau local que l'iPad."
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

    private func statusBadge(_ approved: Bool) -> some View {
        Text(approved ? "APPROVED" : "DECLINED")
            .font(.system(size: 10, weight: .black))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((approved ? Color.green : Color.red).opacity(0.15))
            .foregroundColor(approved ? Color.green : Color.red)
            .cornerRadius(4)
    }

    // MARK: - Actions

    private func runTestConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        if case .success(let reachable) = await connector.testConnection() {
            connectionStatus = (reachable: reachable, message: reachable ? "Connected" : "Unreachable")
        }
    }

    private func runTestSale() async {
        let normalized = testAmountText.replacingOccurrences(of: ",", with: ".")
        guard let amount = Double(normalized), amount > 0 else { return }
        let orderId = "DUOPAY-TEST-\(Int(Date().timeIntervalSince1970))"
        await connector.chargeSale(amount: amount, orderId: orderId, cardholderName: "Test")
    }

    private func runCloseBatch() async {
        isClosingBatch = true
        defer { isClosingBatch = false }
        if case .success(let batch) = await connector.closeBatch() {
            batchResult = batch
        }
    }

    // MARK: - Localization

    private func t(_ en: String, _ fr: String) -> String {
        selectedLanguage == "fr" ? fr : en
    }
}

// MARK: - Placeholder modifier

extension View {
    func placeholder<Content: View>(when shouldShow: Bool, alignment: Alignment = .leading, @ViewBuilder placeholder: () -> Content) -> some View {
        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

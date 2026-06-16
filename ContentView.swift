import SwiftUI
import PassKit

struct ContentView: View {
    @AppStorage("selected_language") private var selectedLanguage = "fr"
    @State private var showingSettings = false
    @State private var showingAdminMenu = false
    @State private var showingFreebieCelebration = false
    @State private var showingSuperAdmin = false
    @State private var showingLoyalty = false
    @State private var showingBackOffice = false
    @State private var showingBackOfficePIN = false
    @State private var enteredBOPIN = ""
    @State private var showingManualEntry = false
    @State private var showingTransactions = false
    @State private var showingSpinSettings = false

    @State private var showingPunchClock = false
    @State private var showingCheckoutSheet = false
    @State private var showDeadStockOnly = false
    
    @StateObject private var inventoryService = InventoryService()
    @StateObject private var punchService = PunchService()
    @StateObject private var menuService = MenuService()
    @StateObject private var transactionService = TransactionService()
    @StateObject private var loyaltyService = LoyaltyService()
    @ObservedObject var connectivity = TerminalConnectivity.shared
    @ObservedObject var superAdmin = SuperAdminService.shared
    
    @State private var cart: [CartItem] = []
    @State private var showingReceipt = false
    @State private var applePayMessage: String? = nil
    @State private var showingApplePayAlert = false
    @State private var receiptFontSize: Double = 14
    @State private var receiptScale: Double = 1.0
    private let paymentHandler = PaymentHandler()
    @State private var posConnector: POSConnector = SquareConnector()
    @StateObject private var stripeConnector = StripeConnector()
    @StateObject private var spinConnector = SpinPOSConnector()

    // Sidebar Animation State
    @State private var isSidebarOpen = false

    var subtotal: Double {
        cart.reduce(0) { $0 + $1.subtotal }
    }
    
    var totalTPS: Double {
        cart.reduce(0) { $0 + $1.tpsAmount }
    }
    
    var totalTVQ: Double {
        cart.reduce(0) { $0 + $1.tvqAmount }
    }

    var total: Double {
        let baseTotal = subtotal + totalTPS + totalTVQ
        let discount = baseTotal * (loyaltyService.currentCustomer?.tier.discount ?? 0.0)
        return baseTotal - discount
    }

    /// Sidebar label for the SPIn integration entry. Falls back to inline
    /// FR/EN strings rather than L.string(...) so it works even before the
    /// "spin_integration" key is added to the app's localization tables.
    private var spinSidebarLabel: String {
        selectedLanguage == "fr" ? "Intégration SPIn" : "SPIn Integration"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background color for the 3D effect
            Color.black.edgesIgnoringSafeArea(.all)
            
            // 1. SIDEBAR LAYER (Visible on top of the shrunken content)
            if isSidebarOpen {
                VStack(spacing: 25) {
                    Text("DUOPAY")
                        .font(.system(.title2, design: .rounded))
                        .fontWeight(.black)
                        .padding(.top, 60)
                        .padding(.bottom, 20)
                    
                    SidebarButton(icon: "cart.fill", label: L.string("app_title"), color: .blue) {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            isSidebarOpen = false
                        }
                    }
                    
                    SidebarButton(icon: "clock.arrow.circlepath", label: L.string("past_transactions"), color: .primary) {
                        showingTransactions = true
                    }
                    
                    SidebarButton(icon: "crown.fill", label: L.string("super_admin"), color: .orange) {
                        showingSuperAdmin = true
                    }
                    
                    SidebarButton(icon: "lock.shield.fill", label: L.string("back_office"), color: .primary) {
                        showingBackOfficePIN = true
                    }
                    
                    SidebarButton(icon: "timer", label: L.string("punch_clock"), color: .primary) {
                        showingPunchClock = true
                    }
                    
                    SidebarButton(icon: "person.2.fill", label: L.string("manage_loyalty"), color: .primary) {
                        showingLoyalty = true
                    }
                    
                    SidebarButton(icon: "keyboard", label: L.string("manual_entry"), color: .primary) {
                        showingManualEntry = true
                    }
                    
                    SidebarButton(icon: "pencil.and.outline", label: L.string("edit_menu"), color: .primary) {
                        showingAdminMenu = true
                    }
                    
                    SidebarButton(icon: "wave.3.right.circle.fill", label: spinSidebarLabel, color: SpinConnectorConfig.isEnabled ? .blue : .primary) {
                        showingSpinSettings = true
                    }
                    
                    Spacer()
                    
                    SidebarButton(icon: "trash", label: L.string("clear_cart"), color: .red) {
                        cart.removeAll()
                        withAnimation { isSidebarOpen = false }
                    }
                    
                    SidebarButton(icon: "gear", label: L.string("settings"), color: .primary) {
                        showingSettings = true
                    }
                    .padding(.bottom, 40)
                }
                .frame(width: 140)
                .background(.ultraThinMaterial)
                .transition(.move(edge: .leading))
                .edgesIgnoringSafeArea(.all)
                .zIndex(2)
            }

            // 2. MAIN CONTENT LAYER
            SquareCheckoutView(
                products: $menuService.products,
                cart: $cart,
                categories: $menuService.categories,
                showDeadStockOnly: $showDeadStockOnly,
                inventoryService: inventoryService,
                loyaltyService: loyaltyService,
                total: total,
                totalTPS: totalTPS,
                totalTVQ: totalTVQ,
                subtotal: subtotal,
                onCharge: { showingCheckoutSheet = true },
                leadingHeaderContent: AnyView(
                    Button(action: {
                        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                            isSidebarOpen.toggle()
                        }
                    }) {
                        Image(systemName: "line.3.horizontal")
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                ),
                trailingHeaderContent: AnyView(
                    Button(action: { showingReceipt = true }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title3)
                            .foregroundColor(.black)
                    }
                )
            )
            .offset(x: isSidebarOpen ? 140 : 0)
            .scaleEffect(isSidebarOpen ? 0.9 : 1.0)
            .opacity(isSidebarOpen ? 0.8 : 1.0)
            .cornerRadius(isSidebarOpen ? 30 : 0)
            .shadow(color: .black.opacity(isSidebarOpen ? 0.3 : 0), radius: 40, x: -20, y: 0)
            .overlay(
                Group {
                    if isSidebarOpen {
                        Color.black.opacity(0.01)
                            .onTapGesture {
                                withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                                    isSidebarOpen = false
                                }
                            }
                    }
                }
            )
            .zIndex(1)
        }
        .onTapGesture {
            if SuperAdminService.shared.isImpersonating {
                SuperAdminService.shared.logAction("Screen Tapped")
            }
        }
        .trainingModeVisuals()
        .overlay(
            ZStack {
                if superAdmin.isImpersonating {
                    // 120Hz GLOWING RED BORDER
                    TimelineView(.animation) { timeline in
                        RoundedRectangle(cornerRadius: isSidebarOpen ? 30 : 0)
                            .stroke(Color.red, lineWidth: 4)
                            .shadow(color: .red, radius: 10 + 5 * sin(timeline.date.timeIntervalSince1970 * 10))
                            .opacity(0.8 + 0.2 * sin(timeline.date.timeIntervalSince1970 * 10))
                    }
                    .edgesIgnoringSafeArea(.all)
                    .allowsHitTesting(false)
                    
                    // TOP EXIT BANNER
                    VStack {
                        HStack {
                            Image(systemName: "eye.trianglebadge.exclamationmark.fill")
                            Text(String(format: L.string("ghost_mode_active"), superAdmin.impersonatedMerchantName))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                            Spacer()
                            Button(action: { superAdmin.stopImpersonating() }) {
                                Text(L.string("exit_ghost_mode"))
                                    .font(.system(size: 10, weight: .black))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .foregroundColor(.red)
                                    .cornerRadius(20)
                            }
                        }
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        Spacer()
                    }
                }
            }
        )
        .sheet(isPresented: $showingSuperAdmin) {
            SuperAdminDashboardView()
        }
        .sheet(isPresented: $showingCheckoutSheet) {
            CheckoutPaymentView(subtotal: subtotal, cart: $cart, transactions: $transactionService.transactions, applePayAction: startApplePay, posAction: payViaPOS, completePayment: completePayment)
        }
        .sheet(isPresented: $showingReceipt) {
            ReceiptView(cart: cart, total: total, totalTPS: totalTPS, totalTVQ: totalTVQ, subtotal: subtotal, fontSize: receiptFontSize, scale: receiptScale)
        }
        .sheet(isPresented: $showingTransactions) {
            TransactionsView(transactions: transactionService.transactions)
        }
        .sheet(isPresented: $showingPunchClock) {
            PunchView(punchService: punchService)
        }
        .sheet(isPresented: $showingLoyalty) {
            LoyaltyManagementView(loyaltyService: loyaltyService)
        }
        .sheet(isPresented: $showingManualEntry) {
            ManualEntryView(cart: $cart)
        }
        .sheet(isPresented: $showingAdminMenu) {
            AdminMenuView(products: $menuService.products, categories: $menuService.categories)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(receiptFontSize: $receiptFontSize, receiptScale: $receiptScale, products: $menuService.products, categories: $menuService.categories, inventoryService: inventoryService)
        }
        .sheet(isPresented: $showingSpinSettings) {
            SpinIntegrationSettingsView(connector: spinConnector)
        }
        .alert(isPresented: $showingApplePayAlert) {
            Alert(title: Text("Apple Pay"), message: Text(applePayMessage ?? ""), dismissButton: .default(Text("OK")))
        }
        .alert(L.string("enter_pin"), isPresented: $showingBackOfficePIN) {
            SecureField("PIN", text: $enteredBOPIN)
            Button("OK") {
                if BackOfficeService().verifyPIN(enteredBOPIN) {
                    showingBackOffice = true
                }
                enteredBOPIN = ""
            }
            Button(L.string("cancel"), role: .cancel) { enteredBOPIN = "" }
        }
        .fullScreenCover(isPresented: $showingBackOffice) {
            BackOfficeView(transactionService: transactionService, punchService: punchService)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("QuickCashPayment"))) { _ in
            completePayment(method: "Cash", tip: 0)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FreebieEarned"))) { _ in
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            withAnimation(.spring()) {
                showingFreebieCelebration = true
            }
        }
        .overlay(
            Group {
                if showingFreebieCelebration {
                    ZStack {
                        Color.black.opacity(0.6).edgesIgnoringSafeArea(.all)
                        VStack(spacing: 20) {
                            Image(systemName: "star.circle.fill")
                                .font(.system(size: 100))
                                .foregroundColor(.yellow)
                            Text("Free Item Earned!")
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            Text("The next item is on the house!")
                                .foregroundColor(.white.opacity(0.8))
                            Button("DONE") {
                                withAnimation {
                                    showingFreebieCelebration = false
                                }
                            }
                            .font(.headline)
                            .padding(.horizontal, 40)
                            .padding(.vertical, 15)
                            .background(Color.yellow)
                            .foregroundColor(.black)
                            .cornerRadius(15)
                        }
                    }
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(100)
                }
            }
        )
    }

    func startApplePay(amount: Double) {
        paymentHandler.startPayment(total: amount) { success in
            if success {
                applePayMessage = "Apple Pay succeeded"
            } else {
                applePayMessage = "Apple Pay failed"
            }
            showingApplePayAlert = true
        }
    }

    func payViaPOS(amount: Double) {
        Task {
            // SPIn/Dejavoo path: when configured + enabled, charge the terminal
            // through the Foodteria SPIn connector instead of posConnector.
            if SpinConnectorConfig.isEnabled && SpinConnectorConfig.isConfigured {
                let orderId = "DUOPAY-\(transactionService.transactions.count + 1)-\(Int(Date().timeIntervalSince1970))"
                switch await spinConnector.chargeSale(amount: amount, orderId: orderId) {
                case .success(let record):
                    if record.status.isSuccessful {
                        completePayment(method: "Card (SPIn)", tip: record.tipValue)
                    }
                    // Declined / timeout / error: spinConnector.lastError has details
                    // for the UI; cart is left intact so the cashier can retry.
                case .failure:
                    break
                }
                return
            }

            let success = await posConnector.processPayment(amount: amount)
            if success {
                // POS success handling
            }
        }
    }

    func completePayment(method: String, tip: Double) {
        guard !cart.isEmpty else { return }
        for item in cart {
            inventoryService.recordSale(for: item.product.id)
        }
        let isOnline = connectivity.isWifi || connectivity.isWired
        let finalTotal = total + tip
        let newTransaction = Transaction(date: Date(), items: cart, total: finalTotal, tip: tip, isSynced: isOnline)
        transactionService.addTransaction(newTransaction)
        
        // Handle Loyalty
        if let customer = loyaltyService.currentCustomer {
            if customer.stamps >= 8 {
                loyaltyService.redeemFreebie()
            }
            loyaltyService.addStamp()
            
            // Check if they just hit 8 for celebration next time or now
            if loyaltyService.currentCustomer?.stamps == 8 {
                NotificationCenter.default.post(name: NSNotification.Name("FreebieEarned"), object: nil)
            }
        }
        
        cart.removeAll()
        NotificationCenter.default.post(name: NSNotification.Name("PaymentSuccess"), object: nil)
    }
}

struct SidebarButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TransactionsView: View {
    @AppStorage("selected_language") private var selectedLanguage = "fr"
    let transactions: [Transaction]
    @Environment(\.dismiss) var dismiss
    @State private var searchText = ""
    @State private var selectedDate: Date? = nil

    var filteredTransactions: [Transaction] {
        transactions.filter { transaction in
            let matchesSearch = searchText.isEmpty || 
                String(format: "%.2f", transaction.total).contains(searchText) ||
                transaction.items.contains(where: { $0.product.name.localizedCaseInsensitiveContains(searchText) })
            
            let matchesDate = selectedDate == nil || Calendar.current.isDate(transaction.date, inSameDayAs: selectedDate!)
            
            return matchesSearch && matchesDate
        }
    }
    
    var groupedTransactions: [(Date, [Transaction])] {
        let grouped = Dictionary(grouping: filteredTransactions) { transaction in
            Calendar.current.startOfDay(for: transaction.date)
        }
        return grouped.sorted { $0.key > $1.key }
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L.string("search") + " (\(L.string("cost")), \(L.string("items"))...)", text: $searchText)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    DatePicker("", selection: Binding(
                        get: { selectedDate ?? Date() },
                        set: { selectedDate = $0 }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    
                    if selectedDate != nil {
                        Button(action: { selectedDate = nil }) {
                            Image(systemName: "calendar.badge.minus")
                                .foregroundColor(.red)
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)

                List {
                    ForEach(groupedTransactions, id: \.0) { date, items in
                        Section(header: Text(date, style: .date).bold()) {
                            ForEach(items) { transaction in
                                NavigationLink(destination: TransactionDetailView(transaction: transaction)) {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            HStack {
                                                Text(transaction.date, style: .time)
                                                    .foregroundColor(.secondary)
                                                Spacer()
                                                Text("CA$\(transaction.total, specifier: "%.2f")")
                                                    .bold()
                                            }
                                            Text("\(transaction.items.count) \(L.string("items"))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        Menu {
                                            Button(action: { reprint(transaction, type: .merchant) }) {
                                                Label(L.string("merchant_copy"), systemImage: "person.badge.key")
                                            }
                                            Button(action: { reprint(transaction, type: .customer) }) {
                                                Label(L.string("customer_copy"), systemImage: "person")
                                            }
                                        } label: {
                                            Image(systemName: "printer")
                                                .foregroundColor(.blue)
                                                .padding(8)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(L.string("past_transactions"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L.string("done")) { dismiss() }
                }
            }
        }
    }
    
    enum ReceiptType {
        case merchant, customer
    }
    
    func reprint(_ transaction: Transaction, type: ReceiptType) {
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        print("Reprinting \(type) copy for transaction \(transaction.id)")
        // Actual print logic would go here
    }
}

struct SuperAdminDashboardView: View {
    @ObservedObject var adminService = SuperAdminService.shared
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Loyalty Analytics (Fleetwide)").font(.caption.bold())) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Customer Retention")
                            Spacer()
                            Text("\(String(format: "%.1f", adminService.retentionRate))x Higher")
                                .bold()
                                .foregroundColor(.green)
                        }
                        
                        Divider()
                        
                        Text("Top Redemptions").font(.caption.bold()).foregroundColor(.secondary)
                        HStack(spacing: 20) {
                            ForEach(adminService.redemptionStats.sorted(by: { $0.value > $1.value }).prefix(3), id: \.key) { key, value in
                                VStack {
                                    Text("\(value)").bold()
                                    Text(key).font(.system(size: 8)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                Section(header: Text(L.string("merchant_registry")).font(.caption.bold())) {
                    ForEach(adminService.merchants) { merchant in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(merchant.name).bold()
                                Text(merchant.location).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                HStack {
                                    Circle().fill(statusColor(merchant.status)).frame(width: 8, height: 8)
                                    Text("\(merchant.terminalCount) Terminals").font(.caption)
                                }
                                Button(L.string("impersonate")) {
                                    adminService.impersonate(merchant: merchant)
                                    dismiss()
                                }
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                        }
                        .padding(.vertical, 5)
                    }
                }
            }
            .navigationTitle(L.string("super_admin"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L.string("done")) { dismiss() }
                }
            }
        }
    }
    
    func statusColor(_ status: String) -> Color {
        switch status {
        case "Online": return .green
        case "Warning": return .orange
        default: return .red
        }
    }
}

struct TransactionDetailView: View {
    let transaction: Transaction
    
    var subtotal: Double {
        transaction.items.reduce(0) { $0 + $1.subtotal }
    }
    
    var totalTaxes: Double {
        transaction.items.reduce(0) { $0 + $1.tpsAmount + $1.tvqAmount }
    }
    
    var body: some View {
        List {
            Section(header: Text(L.string("options_general"))) {
                HStack {
                    Text(L.string("transaction_id"))
                    Spacer()
                    Text(transaction.id.uuidString.prefix(8))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text(L.string("date"))
                    Spacer()
                    Text(transaction.date, style: .date)
                    Text(transaction.date, style: .time)
                }
                .foregroundColor(.secondary)
            }
            
            Section(header: Text(L.string("items"))) {
                ForEach(transaction.items) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(item.quantity)x \(item.product.name)")
                                .bold()
                            Spacer()
                            Text("CA$\(item.subtotal, specifier: "%.2f")")
                        }
                        
                        if !item.selectedModifiers.isEmpty {
                            ForEach(Array(item.selectedModifiers)) { modifier in
                                Text("+ \(modifier.name)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            
            Section {
                HStack {
                    Text(L.string("subtotal"))
                    Spacer()
                    Text("CA$\(subtotal, specifier: "%.2f")")
                }
                HStack {
                    Text(L.string("taxes"))
                    Spacer()
                    Text("CA$\(totalTaxes, specifier: "%.2f")")
                }
                HStack {
                    Text("Tip")
                    Spacer()
                    Text("CA$\(transaction.tip, specifier: "%.2f")")
                }
                HStack {
                    Text(L.string("total"))
                        .font(.headline)
                    Spacer()
                    Text("CA$\(transaction.total, specifier: "%.2f")")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
        }
        .navigationTitle(L.string("receipt"))
    }
}

struct LoyaltyManagementView: View {
    @ObservedObject var loyaltyService: LoyaltyService
    @Environment(\.dismiss) var dismiss
    
    @State private var searchText = ""
    @State private var newName = ""
    @State private var newEmail = ""
    @State private var newPhone = ""
    @State private var showingAddForm = false
    
    var filteredCustomers: [Customer] {
        let all = Array(loyaltyService.customers.values)
        if searchText.isEmpty { return all.sorted(by: { $0.totalVisits > $1.totalVisits }) }
        return all.filter { 
            $0.name.localizedCaseInsensitiveContains(searchText) || 
            $0.phoneNumber.contains(searchText) ||
            $0.email.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField(L.string("search_customer"), text: $searchText)
                        .keyboardType(.phonePad)
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                List {
                    if showingAddForm {
                        Section(header: Text(L.string("add_customer"))) {
                            TextField(L.string("customer_name"), text: $newName)
                            TextField(L.string("customer_email"), text: $newEmail)
                                .keyboardType(.emailAddress)
                            TextField(L.string("customer_phone"), text: $newPhone)
                                .keyboardType(.phonePad)
                            Button(action: {
                                loyaltyService.addOrUpdateCustomer(name: newName, email: newEmail, phone: newPhone)
                                newName = ""; newEmail = ""; newPhone = ""; showingAddForm = false
                            }) {
                                Text(L.string("save")).bold().frame(maxWidth: .infinity)
                            }
                            .disabled(newName.isEmpty || newPhone.isEmpty)
                        }
                    }
                    
                    Section(header: Text(L.string("manage_loyalty"))) {
                        ForEach(filteredCustomers) { customer in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(customer.name.isEmpty ? "Unknown" : customer.name).bold()
                                    Spacer()
                                    Text(customer.tier.rawValue)
                                        .font(.system(size: 10, weight: .black))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                                Text(customer.phoneNumber).font(.caption).foregroundColor(.secondary)
                                HStack {
                                    Image(systemName: "cup.and.saucer.fill")
                                    Text("\(customer.stamps)/8 Stamps")
                                    Spacer()
                                    Text("\(customer.totalVisits) visits")
                                }
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            }
                            .onTapGesture {
                                loyaltyService.identifyCustomer(phone: customer.phoneNumber)
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(L.string("manage_loyalty"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingAddForm.toggle() }) {
                        Image(systemName: showingAddForm ? "minus.circle.fill" : "plus.circle.fill")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L.string("done")) { dismiss() }
                }
            }
        }
    }
}

struct ReceiptView: View {
    @AppStorage("selected_language") private var selectedLanguage = "fr"
    let cart: [CartItem]
    let total: Double
    let totalTPS: Double
    let totalTVQ: Double
    let subtotal: Double
    let fontSize: Double
    let scale: Double

    var body: some View {
        VStack {
            Text(L.string("receipt"))
                .font(.system(size: CGFloat(fontSize * scale * 1.6), weight: .bold))
                .padding()

            List(cart) { item in
                HStack {
                    Text(item.product.name)
                        .font(.system(size: CGFloat(fontSize * scale)))
                    Spacer()
                    Text("x\(item.quantity)")
                        .font(.system(size: CGFloat(fontSize * scale)))
                    Text("CA$\(item.subtotal, specifier: "%.2f")")
                        .font(.system(size: CGFloat(fontSize * scale)))
                }
            }

            VStack(spacing: 8) {
                Divider()
                
                HStack {
                    Text(L.currentRegion == .QC ? "Sous-total / Subtotal" : "Subtotal")
                    Spacer()
                    Text("CA$\(subtotal, specifier: "%.2f")")
                }
                .font(.system(size: CGFloat(fontSize * scale)))
                
                if L.currentRegion.hstRate > 0 {
                    HStack {
                        Text("HST (\(Int(L.currentRegion.hstRate * 100))%)")
                        Spacer()
                        let hst = cart.reduce(0) { $0 + $1.hstAmount }
                        Text("CA$\(hst, specifier: "%.2f")")
                    }
                    .font(.system(size: CGFloat(fontSize * scale)))
                } else {
                    if L.currentRegion.gstRate > 0 {
                        HStack {
                            let label = L.currentRegion == .QC ? "TPS (5%)" : "GST (5%)"
                            Text(label)
                            Spacer()
                            Text("CA$\(totalTPS, specifier: "%.2f")")
                        }
                        .font(.system(size: CGFloat(fontSize * scale)))
                    }
                    
                    if L.currentRegion.pstRate > 0 {
                        HStack {
                            let rate = Int(L.currentRegion.pstRate * 100)
                            let label = L.currentRegion == .QC ? "TVQ (9.975%)" : "\(L.currentRegion.pstName) (\(rate)%)"
                            Text(label)
                            Spacer()
                            Text("CA$\(totalTVQ, specifier: "%.2f")")
                        }
                        .font(.system(size: CGFloat(fontSize * scale)))
                    }
                }

                Divider()

                HStack {
                    Text(L.currentRegion == .QC ? "TOTAL PAYÉ / TOTAL PAID" : "TOTAL")
                        .bold()
                    Spacer()
                    Text("CA$\(total, specifier: "%.2f")")
                        .bold()
                }
                .font(.system(size: CGFloat(fontSize * scale * 1.2)))
            }
            .padding()
        }
    }
}

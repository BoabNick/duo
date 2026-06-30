'use strict';

// API base is resolved at runtime (same-origin "/api" on web, absolute URL in the
// mobile app). It is recomputed whenever the user saves a new Server URL.
let API = window.DUOPAY_CONFIG.resolveApiBase();

// ===== State =====
const state = {
  cart: [],
  taxRate: parseFloat(localStorage.getItem('taxRate') || '5'),
  terminalName: localStorage.getItem('terminalName') || 'DUOPAY-001',
  serverUrl: window.DUOPAY_CONFIG.getServerUrl(),
  spin: {
    enabled: localStorage.getItem('spin_enabled') === 'true',
    url: localStorage.getItem('spin_url') || '',
    register: localStorage.getItem('spin_register') || '',
    apiKey: localStorage.getItem('spin_api_key') || '',
  },
  pax: {
    enabled: localStorage.getItem('pax_enabled') === 'true',
    ip: localStorage.getItem('pax_ip') || '',
    port: localStorage.getItem('pax_port') || '10001',
  }
};

// ===== Products =====
const products = [
  { id: 1, name: 'Espresso',  emoji: '☕', price: 3.25 },
  { id: 2, name: 'Latte',     emoji: '🥛', price: 4.75 },
  { id: 3, name: 'Mocha',     emoji: '🍫', price: 5.00 },
  { id: 4, name: 'Croissant', emoji: '🥐', price: 3.00 },
  { id: 5, name: 'Muffin',    emoji: '🧁', price: 2.75 },
  { id: 6, name: 'Bagel',     emoji: '🥯', price: 3.50 },
];

// ===== Init =====
function init() {
  renderProducts();
  loadSettingsUI();
  updateCart();
}

// ===== Products =====
function renderProducts() {
  document.getElementById('productsGrid').innerHTML = products.map(p => `
    <button class="product-btn" onclick="addToCart(${p.id})">
      <div class="product-emoji">${p.emoji}</div>
      <div class="product-name">${p.name}</div>
      <div class="product-price">$${p.price.toFixed(2)}</div>
    </button>
  `).join('');
}

// ===== Cart =====
function addToCart(productId) {
  const product = products.find(p => p.id === productId);
  const existing = state.cart.find(c => c.id === productId);
  if (existing) existing.qty++;
  else state.cart.push({ ...product, qty: 1 });
  updateCart();
}

function changeQty(productId, delta) {
  const item = state.cart.find(c => c.id === productId);
  if (!item) return;
  item.qty += delta;
  if (item.qty <= 0) state.cart = state.cart.filter(c => c.id !== productId);
  updateCart();
}

function clearCart() {
  state.cart = [];
  updateCart();
}

function updateCart() {
  const subtotal = state.cart.reduce((sum, i) => sum + i.price * i.qty, 0);
  const tax = subtotal * (state.taxRate / 100);
  const total = subtotal + tax;

  const el = document.getElementById('cartItems');
  el.innerHTML = state.cart.length === 0
    ? '<div style="color:var(--gray);font-size:13px;padding:8px 0;">Cart is empty</div>'
    : state.cart.map(item => `
        <div class="cart-item">
          <span class="cart-item-name">${item.name}</span>
          <div class="cart-item-qty">
            <button class="qty-btn" onclick="changeQty(${item.id}, -1)">−</button>
            <span class="qty-count">${item.qty}</span>
            <button class="qty-btn" onclick="changeQty(${item.id}, 1)">+</button>
          </div>
          <span class="cart-item-price">$${(item.price * item.qty).toFixed(2)}</span>
        </div>`).join('');

  document.getElementById('subtotal').textContent = `$${subtotal.toFixed(2)}`;
  document.getElementById('tax').textContent = `$${tax.toFixed(2)}`;
  document.getElementById('total').textContent = `$${total.toFixed(2)}`;
  document.getElementById('chargeBtn').disabled = state.cart.length === 0;
}

function calculateTotal() {
  const subtotal = state.cart.reduce((sum, i) => sum + i.price * i.qty, 0);
  return subtotal * (1 + state.taxRate / 100);
}

// ===== Payment Modal =====
function showPaymentModal() {
  document.getElementById('paymentAmount').value = calculateTotal().toFixed(2);
  document.getElementById('tipAmount').value = '';
  document.getElementById('paymentStatus').innerHTML = '';
  document.getElementById('processPaymentBtn').disabled = false;
  document.getElementById('paymentModal').classList.add('show');
}

function closePaymentModal() {
  document.getElementById('paymentModal').classList.remove('show');
}

async function processPayment() {
  const method = document.getElementById('paymentMethod').value;
  const amount = parseFloat(document.getElementById('paymentAmount').value);
  const tip = parseFloat(document.getElementById('tipAmount').value) || 0;
  const statusDiv = document.getElementById('paymentStatus');
  const btn = document.getElementById('processPaymentBtn');

  btn.disabled = true;
  statusDiv.innerHTML = '<div class="alert info"><span class="spinner"></span> Processing…</div>';

  try {
    let approved = false;

    if (method === 'spin') {
      if (!state.spin.enabled || !state.spin.url) throw new Error('SPIn is not configured — enable it in Settings first');
      const orderId = `web-${Date.now()}`;
      const spinTerminal = await getOrCreateSpinTerminal();
      const resp = await fetch(`${API}/payments/spin`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ terminal_id: spinTerminal.id, order_id: orderId, amount, tip })
      });
      const data = await resp.json();
      if (!resp.ok) throw new Error(data.error || 'SPIn payment failed');
      approved = data.approved;
    } else {
      approved = true;
    }

    if (approved) {
      statusDiv.innerHTML = '<div class="alert success">✓ Payment approved</div>';
      clearCart();
      setTimeout(closePaymentModal, 1500);
    } else {
      statusDiv.innerHTML = '<div class="alert error">✗ Payment declined</div>';
      btn.disabled = false;
    }
  } catch (err) {
    statusDiv.innerHTML = `<div class="alert error">✗ ${err.message}</div>`;
    btn.disabled = false;
  }
}

async function getOrCreateSpinTerminal() {
  const resp = await fetch(`${API}/terminals`);
  const terminals = await resp.json();
  const existing = terminals.find(t => t.type === 'spin');
  if (existing) return existing;

  const create = await fetch(`${API}/terminals`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      name: 'SPIn-Default',
      type: 'spin',
      enabled: true,
      config: { url: state.spin.url, register: state.spin.register, apiKey: state.spin.apiKey }
    })
  });
  return create.json();
}

// ===== Settings UI =====
function loadSettingsUI() {
  document.getElementById('taxRate').value = state.taxRate;
  document.getElementById('terminalName').value = state.terminalName;
  document.getElementById('serverUrl').value = state.serverUrl;
  document.getElementById('spinEnabled').checked = state.spin.enabled;
  document.getElementById('spinUrl').value = state.spin.url;
  document.getElementById('spinRegister').value = state.spin.register;
  document.getElementById('spinApiKey').value = state.spin.apiKey;
  document.getElementById('paxEnabled').checked = state.pax.enabled;
  document.getElementById('paxIp').value = state.pax.ip;
  document.getElementById('paxPort').value = state.pax.port;
}

function saveGeneralSettings() {
  state.taxRate = parseFloat(document.getElementById('taxRate').value) || 5;
  state.terminalName = document.getElementById('terminalName').value.trim() || 'DUOPAY-001';
  state.serverUrl = document.getElementById('serverUrl').value.trim().replace(/\/+$/, '');
  localStorage.setItem('taxRate', state.taxRate);
  localStorage.setItem('terminalName', state.terminalName);
  if (state.serverUrl) localStorage.setItem('server_url', state.serverUrl);
  else localStorage.removeItem('server_url');
  // Re-resolve the API base so a new Server URL takes effect immediately.
  API = window.DUOPAY_CONFIG.resolveApiBase();
  updateCart();
  showToast('General settings saved');
}

function saveSpinConfig() {
  state.spin.enabled = document.getElementById('spinEnabled').checked;
  state.spin.url = document.getElementById('spinUrl').value.trim();
  state.spin.register = document.getElementById('spinRegister').value.trim();
  state.spin.apiKey = document.getElementById('spinApiKey').value;
  localStorage.setItem('spin_enabled', state.spin.enabled);
  localStorage.setItem('spin_url', state.spin.url);
  localStorage.setItem('spin_register', state.spin.register);
  localStorage.setItem('spin_api_key', state.spin.apiKey);
  showToast('SPIn settings saved');
}

function savePaxConfig() {
  state.pax.enabled = document.getElementById('paxEnabled').checked;
  state.pax.ip = document.getElementById('paxIp').value.trim();
  state.pax.port = document.getElementById('paxPort').value;
  localStorage.setItem('pax_enabled', state.pax.enabled);
  localStorage.setItem('pax_ip', state.pax.ip);
  localStorage.setItem('pax_port', state.pax.port);
  showToast('PAX settings saved');
}

async function testSpinConnection() {
  const resultEl = document.getElementById('spinTestResult');
  if (!state.spin.url || !state.spin.register) {
    resultEl.innerHTML = '<div class="alert error">Save SPIn settings first</div>';
    return;
  }
  resultEl.innerHTML = '<div class="alert info"><span class="spinner"></span> Testing…</div>';
  try {
    const resp = await fetch(`${API}/terminals`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: 'SPIn-Test', type: 'spin', enabled: true,
        config: { url: state.spin.url, register: state.spin.register, apiKey: state.spin.apiKey } })
    });
    const t = await resp.json();
    const testResp = await fetch(`${API}/terminals/${t.id}/test`, { method: 'POST' });
    const data = await testResp.json();
    resultEl.innerHTML = data.connected
      ? `<div class="alert success">✓ Connected${data.tpn ? ` — TPN: ${data.tpn}` : ''}</div>`
      : `<div class="alert error">✗ ${data.error || 'Connection failed'}</div>`;
  } catch (err) {
    resultEl.innerHTML = `<div class="alert error">✗ ${err.message}</div>`;
  }
}

function testPaxConnection() {
  document.getElementById('paxTestResult').innerHTML =
    '<div class="alert info">PAX requires the desktop connector app for full connectivity</div>';
}

// ===== Transactions =====
async function loadTransactions() {
  const list = document.getElementById('transactionsList');
  list.innerHTML = '<div class="alert info"><span class="spinner"></span> Loading…</div>';
  try {
    const resp = await fetch(`${API}/transactions?limit=20`);
    const txs = await resp.json();
    if (txs.length === 0) {
      list.innerHTML = '<div style="color:var(--gray);font-size:13px;">No transactions yet</div>';
      return;
    }
    list.innerHTML = txs.map(t => `
      <div class="tx-item">
        <div class="tx-item-row">
          <span>$${parseFloat(t.total).toFixed(2)}</span>
          <span class="${t.status === 'APPROVED' ? 'tx-status-approved' : 'tx-status-other'}">${t.status}</span>
        </div>
        <div class="tx-meta">${new Date(t.created_at).toLocaleString()} · ${t.method}${t.terminal_name ? ' · ' + t.terminal_name : ''}</div>
      </div>`).join('');
  } catch (err) {
    list.innerHTML = `<div class="alert error">Failed to load transactions</div>`;
  }
}

// ===== Navigation =====
function switchSection(sectionId, btn) {
  document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
  document.querySelectorAll('.sidebar-btn').forEach(b => b.classList.remove('active'));
  document.getElementById(sectionId).classList.add('active');
  btn.classList.add('active');
  const titles = { checkout: 'Checkout', transactions: 'Transactions', settings: 'Settings' };
  document.getElementById('headerTitle').textContent = titles[sectionId] || sectionId;
  if (sectionId === 'transactions') loadTransactions();
}

// ===== Toast =====
function showToast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 2200);
}

// ===== Logout =====
function logout() {
  if (confirm('Clear all local config and reload?')) {
    localStorage.clear();
    location.reload();
  }
}

window.addEventListener('load', init);

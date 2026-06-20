const express = require('express');
const cors = require('cors');
const crypto = require('crypto');
const sqlite3 = require('sqlite3').verbose();
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// ===== Middleware =====

const allowedOrigins = process.env.CORS_ORIGIN
  ? process.env.CORS_ORIGIN.split(',').map(o => o.trim())
  : ['http://localhost:3000', 'https://moukas.tech', 'https://www.moukas.tech'];

app.use(cors({
  origin: (origin, cb) => {
    if (!origin || allowedOrigins.includes(origin)) return cb(null, true);
    cb(new Error('Not allowed by CORS'));
  },
  credentials: true
}));
app.use(express.json());
app.use(express.static('public'));

// ===== Database =====

const DB_PATH = process.env.DB_PATH || './duopay.db';
const db = new sqlite3.Database(DB_PATH, (err) => {
  if (err) {
    console.error('Database connection failed:', err);
    process.exit(1);
  }
  console.log('Connected to SQLite database');
  initDatabase();
});

function initDatabase() {
  db.serialize(() => {
    db.run(`
      CREATE TABLE IF NOT EXISTS terminals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        type TEXT NOT NULL,
        enabled BOOLEAN DEFAULT 0,
        config TEXT NOT NULL,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL UNIQUE,
        terminal_id INTEGER NOT NULL,
        amount REAL NOT NULL,
        tip REAL DEFAULT 0,
        total REAL NOT NULL,
        method TEXT NOT NULL,
        status TEXT NOT NULL,
        auth_code TEXT,
        reference_number TEXT,
        response_data TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (terminal_id) REFERENCES terminals(id)
      )
    `);

    db.run(`
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    db.run(`
      INSERT OR IGNORE INTO settings (key, value) VALUES
      ('tax_rate', '5'),
      ('currency', 'CAD'),
      ('terminal_name', 'DUOPAY-001'),
      ('language', 'en')
    `);
  });
}

// ===== Helpers =====

function parseConfig(row) {
  try { return { ...row, config: JSON.parse(row.config) }; }
  catch { return { ...row, config: {} }; }
}

function parseResponseData(row) {
  try { return { ...row, response_data: row.response_data ? JSON.parse(row.response_data) : null }; }
  catch { return { ...row, response_data: null }; }
}

// ===== Health =====

app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ===== Terminals =====

app.get('/api/terminals', (req, res) => {
  db.all('SELECT * FROM terminals', [], (err, rows) => {
    if (err) return res.status(500).json({ error: err.message });
    res.json(rows.map(parseConfig));
  });
});

app.get('/api/terminals/:id', (req, res) => {
  db.get('SELECT * FROM terminals WHERE id = ?', [req.params.id], (err, row) => {
    if (err) return res.status(500).json({ error: err.message });
    if (!row) return res.status(404).json({ error: 'Terminal not found' });
    res.json(parseConfig(row));
  });
});

app.post('/api/terminals', (req, res) => {
  const { name, type, enabled, config } = req.body;
  if (!name || !type || !config) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const configJson = JSON.stringify(config);
  db.run(
    `INSERT INTO terminals (name, type, enabled, config) VALUES (?, ?, ?, ?)
     ON CONFLICT(name) DO UPDATE SET type=excluded.type, enabled=excluded.enabled, config=excluded.config, updated_at=CURRENT_TIMESTAMP`,
    [name, type, enabled ? 1 : 0, configJson],
    function(err) {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ id: this.lastID || undefined, name, type, enabled: !!enabled, config });
    }
  );
});

app.post('/api/terminals/:id/test', (req, res) => {
  db.get('SELECT * FROM terminals WHERE id = ?', [req.params.id], async (err, terminal) => {
    if (err) return res.status(500).json({ error: err.message });
    if (!terminal) return res.status(404).json({ error: 'Terminal not found' });

    const config = JSON.parse(terminal.config);
    try {
      const result = terminal.type === 'spin'
        ? await testSpinConnection(config)
        : terminal.type === 'pax'
          ? testPaxConnection(config)
          : { connected: false, error: 'Unknown terminal type' };
      res.json(result);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });
});

async function testSpinConnection(config) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch(`${config.url}/v1/registers/${config.register}/test-connection`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(config.apiKey && { 'x-api-key': config.apiKey })
      },
      signal: controller.signal
    });
    if (!response.ok) return { connected: false, error: `HTTP ${response.status}` };
    const data = await response.json();
    return { connected: data.connected, tpn: data.tpn, spinRegisterId: data.spinRegisterId };
  } catch (error) {
    return { connected: false, error: error.name === 'AbortError' ? 'Connection timed out' : error.message };
  } finally {
    clearTimeout(timeout);
  }
}

function testPaxConnection(config) {
  return {
    connected: true,
    message: `Ready to connect to ${config.ip}:${config.port}`,
    note: 'Full PAX communication requires the desktop connector'
  };
}

// ===== Transactions =====

app.get('/api/transactions', (req, res) => {
  const limit = Math.min(Math.max(parseInt(req.query.limit) || 100, 1), 500);
  const offset = Math.max(parseInt(req.query.offset) || 0, 0);

  db.all(
    `SELECT t.*, term.name AS terminal_name FROM transactions t
     LEFT JOIN terminals term ON t.terminal_id = term.id
     ORDER BY t.created_at DESC LIMIT ? OFFSET ?`,
    [limit, offset],
    (err, rows) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json(rows.map(parseResponseData));
    }
  );
});

app.get('/api/transactions/:id', (req, res) => {
  db.get(
    `SELECT t.*, term.name AS terminal_name FROM transactions t
     LEFT JOIN terminals term ON t.terminal_id = term.id
     WHERE t.id = ?`,
    [req.params.id],
    (err, row) => {
      if (err) return res.status(500).json({ error: err.message });
      if (!row) return res.status(404).json({ error: 'Transaction not found' });
      res.json(parseResponseData(row));
    }
  );
});

app.post('/api/transactions', (req, res) => {
  const { order_id, terminal_id, amount, tip, method, status, auth_code, reference_number, response_data } = req.body;
  if (!order_id || !terminal_id || amount == null) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const amt = parseFloat(amount);
  const tipAmt = parseFloat(tip) || 0;
  const total = (amt + tipAmt).toFixed(2);
  const responseDataJson = response_data ? JSON.stringify(response_data) : null;

  db.run(
    `INSERT INTO transactions (order_id, terminal_id, amount, tip, total, method, status, auth_code, reference_number, response_data)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [order_id, terminal_id, amt, tipAmt, total, method, status || 'PENDING', auth_code || null, reference_number || null, responseDataJson],
    function(err) {
      if (err) return res.status(500).json({ error: err.message });
      res.status(201).json({ id: this.lastID, order_id, terminal_id, amount: amt, tip: tipAmt, total, method, status, auth_code, reference_number });
    }
  );
});

app.patch('/api/transactions/:id', (req, res) => {
  const { status, response_data } = req.body;
  if (!status) return res.status(400).json({ error: 'Missing status' });

  db.run(
    `UPDATE transactions SET status = ?, response_data = ? WHERE id = ?`,
    [status, response_data ? JSON.stringify(response_data) : null, req.params.id],
    function(err) {
      if (err) return res.status(500).json({ error: err.message });
      if (this.changes === 0) return res.status(404).json({ error: 'Transaction not found' });
      res.json({ success: true, id: req.params.id, status });
    }
  );
});

// ===== Settings =====

app.get('/api/settings', (req, res) => {
  db.all('SELECT * FROM settings', [], (err, rows) => {
    if (err) return res.status(500).json({ error: err.message });
    const settings = Object.fromEntries(rows.map(r => [r.key, r.value]));
    res.json(settings);
  });
});

app.post('/api/settings/:key', (req, res) => {
  const { value } = req.body;
  if (value === undefined) return res.status(400).json({ error: 'Missing value' });

  db.run(
    `INSERT INTO settings (key, value) VALUES (?, ?)
     ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=CURRENT_TIMESTAMP`,
    [req.params.key, value],
    (err) => {
      if (err) return res.status(500).json({ error: err.message });
      res.json({ key: req.params.key, value });
    }
  );
});

// ===== Payments =====

app.post('/api/payments/spin', async (req, res) => {
  const { terminal_id, order_id, amount, tip } = req.body;
  if (!terminal_id || !order_id || amount == null) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  db.get('SELECT * FROM terminals WHERE id = ?', [terminal_id], async (err, terminal) => {
    if (err) return res.status(500).json({ error: err.message });
    if (!terminal) return res.status(404).json({ error: 'Terminal not found' });

    const config = JSON.parse(terminal.config);
    const amt = parseFloat(amount);
    const tipAmt = parseFloat(tip) || 0;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30000);

    try {
      const response = await fetch(`${config.url}/v1/payments/sale`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          ...(config.apiKey && { 'x-api-key': config.apiKey })
        },
        body: JSON.stringify({
          registerId: config.register,
          foodteriaOrderId: order_id,
          amount: amt.toFixed(2),
          ...(tipAmt > 0 && { tip: tipAmt.toFixed(2) }),
          paymentType: 'Credit'
        }),
        signal: controller.signal
      });

      const data = await response.json();
      const approved = data.status === 'APPROVED';
      const txStatus = data.status || 'DECLINED';

      db.run(
        `INSERT INTO transactions (order_id, terminal_id, amount, tip, total, method, status, auth_code, reference_number, response_data)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [order_id, terminal_id, amt, tipAmt, (amt + tipAmt).toFixed(2), 'Card (SPIn)', txStatus, data.authCode || null, data.refId || null, JSON.stringify(data)],
        function(err) {
          if (err) return res.status(500).json({ error: err.message });
          res.status(201).json({ id: this.lastID, order_id, approved, status: txStatus, auth_code: data.authCode, reference_number: data.refId });
        }
      );
    } catch (error) {
      const msg = error.name === 'AbortError' ? 'SPIn request timed out' : error.message;
      res.status(502).json({ error: msg });
    } finally {
      clearTimeout(timeout);
    }
  });
});

// ===== Error handler =====

app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

app.listen(PORT, () => {
  console.log(`DUOPAY server running on http://localhost:${PORT}`);
});

module.exports = app;

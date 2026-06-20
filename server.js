// server.js
const express = require('express');
const cors = require('cors');
const sqlite3 = require('sqlite3').verbose();
const path = require('path');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
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

// Database setup
const DB_PATH = process.env.DB_PATH || './duopay.db';
const db = new sqlite3.Database(DB_PATH, (err) => {
  if (err) {
    console.error('Database connection failed:', err);
  } else {
    console.log('Connected to SQLite database');
    initDatabase();
  }
});

function initDatabase() {
  db.serialize(() => {
    // Terminals table
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

    // Transactions table
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

    // Settings table
    db.run(`
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      )
    `);

    // Insert default settings
    db.run(`
      INSERT OR IGNORE INTO settings (key, value) VALUES 
      ('tax_rate', '5'),
      ('currency', 'CAD'),
      ('terminal_name', 'DUOPAY-001'),
      ('language', 'en')
    `);
  });
}

// ===== API Routes =====

// Health check
app.get('/api/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ===== Terminals API =====

// Get all terminals
app.get('/api/terminals', (req, res) => {
  db.all('SELECT * FROM terminals', [], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    const terminals = rows.map(row => ({
      ...row,
      config: JSON.parse(row.config)
    }));
    res.json(terminals);
  });
});

// Get terminal by ID
app.get('/api/terminals/:id', (req, res) => {
  db.get('SELECT * FROM terminals WHERE id = ?', [req.params.id], (err, row) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    if (!row) {
      return res.status(404).json({ error: 'Terminal not found' });
    }
    row.config = JSON.parse(row.config);
    res.json(row);
  });
});

// Create or update terminal
app.post('/api/terminals', (req, res) => {
  const { name, type, enabled, config } = req.body;

  if (!name || !type || !config) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const configJson = JSON.stringify(config);

  db.run(
    `INSERT INTO terminals (name, type, enabled, config) VALUES (?, ?, ?, ?)
     ON CONFLICT(name) DO UPDATE SET type = ?, enabled = ?, config = ?, updated_at = CURRENT_TIMESTAMP`,
    [name, type, enabled ? 1 : 0, configJson, type, enabled ? 1 : 0, configJson],
    function(err) {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json({ id: this.lastID, name, type, enabled, config });
    }
  );
});

// Test terminal connection
app.post('/api/terminals/:id/test', async (req, res) => {
  db.get('SELECT * FROM terminals WHERE id = ?', [req.params.id], async (err, terminal) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    if (!terminal) {
      return res.status(404).json({ error: 'Terminal not found' });
    }

    const config = JSON.parse(terminal.config);

    try {
      let result;
      if (terminal.type === 'spin') {
        result = await testSpinConnection(config);
      } else if (terminal.type === 'pax') {
        result = await testPaxConnection(config);
      } else {
        result = { connected: false, error: 'Unknown terminal type' };
      }
      res.json(result);
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });
});

async function testSpinConnection(config) {
  try {
    const response = await fetch(`${config.url}/v1/registers/${config.register}/test-connection`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(config.apiKey && { 'x-api-key': config.apiKey })
      }
    });

    if (!response.ok) {
      return { connected: false, error: `HTTP ${response.status}` };
    }

    const data = await response.json();
    return {
      connected: data.connected,
      tpn: data.tpn,
      spinRegisterId: data.spinRegisterId
    };
  } catch (error) {
    return { connected: false, error: error.message };
  }
}

async function testPaxConnection(config) {
  // PAX connection test (simulated, as browser can't access local network)
  return {
    connected: true,
    message: `Ready to connect to ${config.ip}:${config.port}`,
    note: 'Actual connection requires backend proxy'
  };
}

// ===== Transactions API =====

// Get all transactions
app.get('/api/transactions', (req, res) => {
  const limit = parseInt(req.query.limit) || 100;
  const offset = parseInt(req.query.offset) || 0;

  db.all(
    `SELECT t.*, term.name as terminal_name FROM transactions t
     LEFT JOIN terminals term ON t.terminal_id = term.id
     ORDER BY t.created_at DESC LIMIT ? OFFSET ?`,
    [limit, offset],
    (err, rows) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      const transactions = rows.map(row => ({
        ...row,
        response_data: row.response_data ? JSON.parse(row.response_data) : null
      }));
      res.json(transactions);
    }
  );
});

// Get transaction by ID
app.get('/api/transactions/:id', (req, res) => {
  db.get(
    `SELECT t.*, term.name as terminal_name FROM transactions t
     LEFT JOIN terminals term ON t.terminal_id = term.id
     WHERE t.id = ?`,
    [req.params.id],
    (err, row) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      if (!row) {
        return res.status(404).json({ error: 'Transaction not found' });
      }
      row.response_data = row.response_data ? JSON.parse(row.response_data) : null;
      res.json(row);
    }
  );
});

// Create transaction
app.post('/api/transactions', (req, res) => {
  const { order_id, terminal_id, amount, tip, method, status, auth_code, reference_number, response_data } = req.body;

  if (!order_id || !terminal_id || !amount) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  const total = (amount + (tip || 0)).toFixed(2);
  const responseDataJson = response_data ? JSON.stringify(response_data) : null;

  db.run(
    `INSERT INTO transactions (order_id, terminal_id, amount, tip, total, method, status, auth_code, reference_number, response_data)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    [order_id, terminal_id, amount, tip || 0, total, method, status || 'PENDING', auth_code || null, reference_number || null, responseDataJson],
    function(err) {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.status(201).json({
        id: this.lastID,
        order_id,
        terminal_id,
        amount,
        tip,
        total,
        method,
        status,
        auth_code,
        reference_number
      });
    }
  );
});

// Update transaction status
app.patch('/api/transactions/:id', (req, res) => {
  const { status, response_data } = req.body;

  const responseDataJson = response_data ? JSON.stringify(response_data) : null;

  db.run(
    `UPDATE transactions SET status = ?, response_data = ? WHERE id = ?`,
    [status, responseDataJson, req.params.id],
    function(err) {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json({ success: true, id: req.params.id, status });
    }
  );
});

// ===== Settings API =====

// Get all settings
app.get('/api/settings', (req, res) => {
  db.all('SELECT * FROM settings', [], (err, rows) => {
    if (err) {
      return res.status(500).json({ error: err.message });
    }
    const settings = {};
    rows.forEach(row => {
      settings[row.key] = row.value;
    });
    res.json(settings);
  });
});

// Update setting
app.post('/api/settings/:key', (req, res) => {
  const { value } = req.body;
  if (value === undefined) {
    return res.status(400).json({ error: 'Missing value' });
  }

  db.run(
    `INSERT INTO settings (key, value) VALUES (?, ?) 
     ON CONFLICT(key) DO UPDATE SET value = ?, updated_at = CURRENT_TIMESTAMP`,
    [req.params.key, value, value],
    (err) => {
      if (err) {
        return res.status(500).json({ error: err.message });
      }
      res.json({ key: req.params.key, value });
    }
  );
});

// ===== Payment Processing =====

// Process payment via SPIn
app.post('/api/payments/spin', async (req, res) => {
  const { terminal_id, order_id, amount, tip, auth_code } = req.body;

  if (!terminal_id || !order_id || !amount) {
    return res.status(400).json({ error: 'Missing required fields' });
  }

  db.get('SELECT * FROM terminals WHERE id = ?', [terminal_id], async (err, terminal) => {
    if (err || !terminal) {
      return res.status(404).json({ error: 'Terminal not found' });
    }

    const config = JSON.parse(terminal.config);

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
          amount: amount.toFixed(2),
          tip: tip > 0 ? tip.toFixed(2) : undefined,
          paymentType: 'Credit'
        })
      });

      const data = await response.json();
      const approved = data.status === 'APPROVED' || response.status === 402;

      // Store transaction
      const transaction = {
        order_id,
        terminal_id,
        amount,
        tip: tip || 0,
        method: 'Card (SPIn)',
        status: data.status || 'DECLINED',
        auth_code: data.authCode,
        reference_number: data.refId,
        response_data: data
      };

      db.run(
        `INSERT INTO transactions (order_id, terminal_id, amount, tip, total, method, status, auth_code, reference_number, response_data)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [
          transaction.order_id,
          transaction.terminal_id,
          transaction.amount,
          transaction.tip,
          (transaction.amount + transaction.tip).toFixed(2),
          transaction.method,
          transaction.status,
          transaction.auth_code,
          transaction.reference_number,
          JSON.stringify(transaction.response_data)
        ],
        function(err) {
          if (err) {
            return res.status(500).json({ error: err.message });
          }
          res.status(201).json({
            id: this.lastID,
            ...transaction,
            approved
          });
        }
      );
    } catch (error) {
      res.status(500).json({ error: error.message });
    }
  });
});


// ===== Deploy Webhook =====
// Called by GitHub Actions on push to main — triggers a git pull + restart
const crypto = require('crypto');

app.post('/api/deploy', express.raw({type: 'application/json'}), (req, res) => {
  const secret = process.env.DEPLOY_SECRET || 'duopay-deploy-secret';
  const signature = req.headers['x-hub-signature-256'];
  
  if (signature) {
    const hmac = crypto.createHmac('sha256', secret);
    const digest = 'sha256=' + hmac.update(req.body).digest('hex');
    if (signature !== digest) {
      return res.status(401).json({ error: 'Invalid signature' });
    }
  }
  
  const body = JSON.parse(req.body);
  
  // Only deploy on push to main branch
  if (body.ref && body.ref !== 'refs/heads/main') {
    return res.json({ message: 'Skipping non-main branch', ref: body.ref });
  }
  
  res.json({ message: 'Deployment triggered', timestamp: new Date().toISOString() });
  
  // Run deployment asynchronously
  const { exec } = require('child_process');
  exec('/opt/duopay/duopay-update.sh', { timeout: 120000 }, (error, stdout, stderr) => {
    if (error) {
      console.error('Deploy error:', error.message);
      console.error('stderr:', stderr);
    } else {
      console.log('Deploy success:', stdout);
    }
  });
});

// ===== Error handler =====
app.use((err, req, res, next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

// Start server
app.listen(PORT, () => {
  console.log(`DUOPAY server running on http://localhost:${PORT}`);
});

module.exports = app;

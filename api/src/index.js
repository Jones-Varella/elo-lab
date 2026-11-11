// elo-lab API: cria tarefas, enfileira no BullMQ e transmite o progresso por SSE.
const express = require('express');
const { Pool } = require('pg');
const IORedis = require('ioredis');
const { Queue } = require('bullmq');
const { MongoClient } = require('mongodb');

const PORT = process.env.PORT || 3000;
const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';

// RDS exige conexão criptografada. No laboratório aceitamos o certificado da AWS sem validar;
// no ambiente real, use o bundle de CA da AWS (ver README).
const pg = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});
const redis = new IORedis(REDIS_URL, { maxRetriesPerRequest: null });
const queue = new Queue('tasks', { connection: redis });
const mongo = new MongoClient(process.env.MONGO_URL || 'mongodb://localhost:27017');

async function log(level, msg, extra = {}) {
  try {
    await mongo.db('elo_lab').collection('logs').insertOne({ service: 'api', level, msg, ...extra, at: new Date() });
  } catch (e) {
    console.error('falha ao gravar log no Mongo:', e.message);
  }
  console.log(`[${level}] ${msg}`);
}

async function migrate() {
  await pg.query(`
    CREATE TABLE IF NOT EXISTS tasks (
      id SERIAL PRIMARY KEY,
      texto TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'na_fila',
      resultado TEXT,
      criado_em TIMESTAMPTZ NOT NULL DEFAULT now(),
      concluido_em TIMESTAMPTZ
    )`);
}

const app = express();
app.use(express.json());

// Página simples para testar pelo navegador.
app.get('/', (_req, res) => {
  res.type('html').send(`<!doctype html><meta charset="utf-8"><title>elo-lab</title>
<body style="font-family:system-ui;max-width:640px;margin:40px auto;padding:0 16px">
<h1>elo-lab v2</h1>
<form id="f"><input id="t" placeholder="Texto da tarefa" required style="width:70%"> <button>Criar tarefa</button></form>
<pre id="out"></pre>
<script>
const out = document.getElementById('out');
document.getElementById('f').onsubmit = async (e) => {
  e.preventDefault();
  const r = await fetch('/tasks', {method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify({texto: document.getElementById('t').value})});
  const {id} = await r.json();
  out.textContent += 'Tarefa ' + id + ' criada\\n';
  const es = new EventSource('/tasks/' + id + '/events');
  es.onmessage = (m) => { const d = JSON.parse(m.data); out.textContent += 'Tarefa ' + id + ': ' + d.progresso + '%\\n'; if (d.progresso >= 100) es.close(); };
};
</script></body>`);
});

// Saúde de cada dependência e tamanho da fila: é o que o monitoramento vai consultar.
app.get('/health', async (_req, res) => {
  const checks = {};
  try { await pg.query('SELECT 1'); checks.postgres = 'ok'; } catch (e) { checks.postgres = e.message; }
  try { await redis.ping(); checks.redis = 'ok'; } catch (e) { checks.redis = e.message; }
  try { await mongo.db('admin').command({ ping: 1 }); checks.mongo = 'ok'; } catch (e) { checks.mongo = e.message; }
  try { checks.fila_aguardando = await queue.getWaitingCount(); } catch (e) { checks.fila_aguardando = null; }
  const healthy = ['postgres', 'redis', 'mongo'].every((k) => checks[k] === 'ok');
  res.status(healthy ? 200 : 503).json({ status: healthy ? 'ok' : 'degradado', ...checks });
});

app.post('/tasks', async (req, res) => {
  const texto = (req.body && req.body.texto || '').toString().trim();
  if (!texto) return res.status(400).json({ erro: 'Informe o campo "texto".' });
  const { rows } = await pg.query('INSERT INTO tasks (texto) VALUES ($1) RETURNING id', [texto]);
  const id = rows[0].id;
  await queue.add('processar', { id, texto }, { attempts: 3, backoff: { type: 'exponential', delay: 2000 } });
  await log('info', 'tarefa criada', { taskId: id });
  res.status(201).json({ id });
});

app.get('/tasks', async (_req, res) => {
  const { rows } = await pg.query('SELECT * FROM tasks ORDER BY id DESC LIMIT 50');
  res.json(rows);
});

// SSE: o worker publica o progresso no Redis e a API repassa ao navegador.
app.get('/tasks/:id/events', async (req, res) => {
  res.set({ 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache', Connection: 'keep-alive', 'X-Accel-Buffering': 'no' });
  res.flushHeaders();
  const sub = new IORedis(REDIS_URL);
  const channel = `task:${req.params.id}`;
  await sub.subscribe(channel);
  sub.on('message', (_ch, msg) => res.write(`data: ${msg}\n\n`));
  const ping = setInterval(() => res.write(': ping\n\n'), 15000);
  req.on('close', () => { clearInterval(ping); sub.quit(); });
});

(async () => {
  await mongo.connect();
  await migrate();
  app.listen(PORT, () => log('info', `API ouvindo na porta ${PORT}`));
})().catch((e) => { console.error('Falha ao iniciar a API:', e); process.exit(1); );

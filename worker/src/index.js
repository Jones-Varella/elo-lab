// elo-lab worker: consome a fila "tasks", simula um processamento em etapas,
// publica o progresso no Redis e grava o resultado no Postgres.
const { Pool } = require('pg');
const IORedis = require('ioredis');
const { Worker } = require('bullmq');
const { MongoClient } = require('mongodb');

const REDIS_URL = process.env.REDIS_URL || 'redis://localhost:6379';
const pg = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.PGSSL === 'true' ? { rejectUnauthorized: false } : false,
});
const connection = new IORedis(REDIS_URL, { maxRetriesPerRequest: null });
const pub = new IORedis(REDIS_URL);
const mongo = new MongoClient(process.env.MONGO_URL || 'mongodb://localhost:27017');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function log(level, msg, extra = {}) {
  try {
    await mongo.db('elo_lab').collection('logs').insertOne({ service: 'worker', level, msg, ...extra, at: new Date() });
  } catch (e) {
    console.error('falha ao gravar log no Mongo:', e.message);
  }
  console.log(`[${level}] ${msg}`);
}

async function processar(job) {
  const { id, texto } = job.data;
  // Para testar os alertas: uma tarefa com "#falhar" no texto sempre dá erro.
  if (texto.includes('#falhar')) throw new Error('falha simulada para testar alertas');
  await pg.query("UPDATE tasks SET status = 'processando' WHERE id = $1", [id]);
  for (let p = 20; p <= 100; p += 20) {
    await sleep(1000); // aqui, no sistema real, entraria a chamada de IA ou integração
    await pub.publish(`task:${id}`, JSON.stringify({ progresso: p }));
    await job.updateProgress(p);
  }
  const resultado = texto.toUpperCase();
  await pg.query("UPDATE tasks SET status = 'concluida', resultado = $2, concluido_em = now() WHERE id = $1", [id, resultado]);
  await log('info', 'tarefa concluída', { taskId: id });
}

(async () => {
  await mongo.connect();
  const worker = new Worker('tasks', processar, { connection, concurrency: Number(process.env.CONCURRENCY || 2) });
  worker.on('failed', (job, err) => log('error', 'tarefa falhou', { taskId: job && job.data.id, erro: err.message }));
  worker.on('error', (err) => log('error', 'erro no worker', { erro: err.message }));
  await log('info', 'worker aguardando tarefas');
  const shutdown = async () => { await worker.close(); process.exit(0); };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
})().catch((e) => { console.error('Falha ao iniciar o worker:', e); process.exit(1); });

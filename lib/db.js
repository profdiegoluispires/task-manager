import { Pool } from 'pg'

let pool = null

export async function getPool() {
  if (!pool) {
    // Se estiver rodando no build time, usa um mock
    if (process.env.NEXT_PHASE) {
      console.warn('⚠️  Using mock pool for build time')
      pool = {
        query: async () => ({ rows: [] }),
        end: async () => {},
      }
    } else {
      pool = new Pool({
        host: process.env.DATABASE_HOST || 'localhost',
        port: parseInt(process.env.DATABASE_PORT || '5432'),
        database: process.env.DATABASE_NAME || 'task_manager',
        user: process.env.DATABASE_USER || 'admin',
        password: process.env.DATABASE_PASSWORD || 'admin',
        // Bancos gerenciados (ex.: Azure PostgreSQL Flexible Server) exigem SSL
        // por padrão — o postgres:15 local do docker-compose não exige.
        ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false,
      })
    }
  }
  return pool
}

export async function initDatabase() {
  const pool = await getPool()
  
  // Retry com timeout de 30 segundos
  const maxRetries = 15
  const retryDelay = 2000
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS tasks (
          id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
          title VARCHAR(255) NOT NULL,
          description TEXT,
          status VARCHAR(20) DEFAULT 'pendente' CHECK (status IN ('pendente', 'em-andamento', 'concluida')),
          priority VARCHAR(10) DEFAULT 'media' CHECK (priority IN ('baixa', 'media', 'alta')),
          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        )
      `)
      console.log('✅ Database initialized successfully')
      return
    } catch (error) {
      if (attempt < maxRetries) {
        console.log(`⏳ Database initialization attempt ${attempt}/${maxRetries} failed, retrying in ${retryDelay/1000}s...`)
        await new Promise(resolve => setTimeout(resolve, retryDelay))
      } else {
        console.error('❌ Error initializing database after retries:', error.message)
        throw error
      }
    }
  }
}

export async function closeDatabase() {
  if (pool && pool.end) {
    await pool.end()
    pool = null
  }
}

import { v4 as uuidv4 } from 'uuid'

const VALID_STATUSES = ['pendente', 'em-andamento', 'concluida']
const VALID_PRIORITIES = ['baixa', 'media', 'alta']
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

async function getPool() {
  // Se estiver rodando no build time, usa um mock
  if (process.env.NEXT_PHASE) {
    console.warn('⚠️  Using mock pool for build time')
    return {
      query: async () => ({ rows: [] }),
      end: async () => {},
    }
  }
  
  const { Pool } = await import('pg')
  return new Pool({
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

export async function GET() {
  try {
    const pool = await getPool()
    const result = await pool.query(
      'SELECT id, title, description, status, priority, created_at FROM tasks ORDER BY created_at DESC'
    )
    
    return Response.json({ tasks: result.rows })
  } catch (error) {
    console.error('Error fetching tasks:', error)
    return Response.json({ error: 'Failed to fetch tasks' }, { status: 500 })
  }
}

export async function POST(request) {
  try {
    const body = await request.json()
    const { title, description, status, priority } = body

    if (!title) {
      return Response.json({ error: 'Title is required' }, { status: 400 })
    }

    if (status && !VALID_STATUSES.includes(status)) {
      return Response.json({ error: `Invalid status. Must be one of: ${VALID_STATUSES.join(', ')}` }, { status: 400 })
    }

    if (priority && !VALID_PRIORITIES.includes(priority)) {
      return Response.json({ error: `Invalid priority. Must be one of: ${VALID_PRIORITIES.join(', ')}` }, { status: 400 })
    }

    const pool = await getPool()
    const id = uuidv4()
    const currentStatus = status || 'pendente'
    const currentPriority = priority || 'media'

    const result = await pool.query(
      `INSERT INTO tasks (id, title, description, status, priority) 
       VALUES ($1, $2, $3, $4, $5) 
       RETURNING *`,
      [id, title, description || null, currentStatus, currentPriority]
    )

    return Response.json({ task: result.rows[0] }, { status: 201 })
  } catch (error) {
    console.error('Error creating task:', error)
    return Response.json({ error: 'Failed to create task' }, { status: 500 })
  }
}

export async function PUT(request) {
  try {
    const body = await request.json()
    const { id, title, description, status, priority } = body

    if (!id) {
      return Response.json({ error: 'Task ID is required' }, { status: 400 })
    }

    if (!UUID_REGEX.test(id)) {
      return Response.json({ error: 'Task not found' }, { status: 404 })
    }

    if (status && !VALID_STATUSES.includes(status)) {
      return Response.json({ error: `Invalid status. Must be one of: ${VALID_STATUSES.join(', ')}` }, { status: 400 })
    }

    if (priority && !VALID_PRIORITIES.includes(priority)) {
      return Response.json({ error: `Invalid priority. Must be one of: ${VALID_PRIORITIES.join(', ')}` }, { status: 400 })
    }

    const pool = await getPool()
    const result = await pool.query(
      `UPDATE tasks 
       SET title = COALESCE($1, title), 
           description = COALESCE($2, description), 
           status = COALESCE($3, status), 
           priority = COALESCE($4, priority),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $5 
       RETURNING *`,
      [title || null, description || null, status || null, priority || null, id]
    )

    if (result.rows.length === 0) {
      return Response.json({ error: 'Task not found' }, { status: 404 })
    }

    return Response.json({ task: result.rows[0] })
  } catch (error) {
    console.error('Error updating task:', error)
    return Response.json({ error: 'Failed to update task' }, { status: 500 })
  }
}

export async function DELETE(request) {
  try {
    const body = await request.json()
    const { id } = body

    if (!id) {
      return Response.json({ error: 'Task ID is required' }, { status: 400 })
    }

    if (!UUID_REGEX.test(id)) {
      return Response.json({ error: 'Task not found' }, { status: 404 })
    }

    const pool = await getPool()
    const result = await pool.query('DELETE FROM tasks WHERE id = $1 RETURNING *', [id])

    if (result.rows.length === 0) {
      return Response.json({ error: 'Task not found' }, { status: 404 })
    }

    return Response.json({ message: 'Task deleted successfully' })
  } catch (error) {
    console.error('Error deleting task:', error)
    return Response.json({ error: 'Failed to delete task' }, { status: 500 })
  }
}

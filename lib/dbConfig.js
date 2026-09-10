export const dbConfig = {
  host: process.env.DATABASE_HOST || 'localhost',
  port: parseInt(process.env.DATABASE_PORT || '5432'),
  database: process.env.DATABASE_NAME || 'task_manager',
  user: process.env.DATABASE_USER || 'admin',
  password: process.env.DATABASE_PASSWORD || 'admin',
  // Bancos gerenciados (ex.: Azure PostgreSQL Flexible Server) exigem SSL por
  // padrão — o postgres:15 local do docker-compose não exige, então isso fica
  // desligado a menos que explicitamente habilitado.
  ssl: process.env.DATABASE_SSL === 'true' ? { rejectUnauthorized: false } : false,
}

export function getDatabaseUrl() {
  return `postgres://${dbConfig.user}:${dbConfig.password}@${dbConfig.host}:${dbConfig.port}/${dbConfig.database}`
}

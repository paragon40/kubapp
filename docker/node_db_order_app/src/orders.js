const { Pool } = require("pg");

const pool = new Pool({
    host: process.env.DB_HOST,
    port: Number(process.env.DB_PORT || 5432),
    database: process.env.DB_NAME,
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    ssl: {
        rejectUnauthorized: false
    }
});

async function initializeDatabase() {
    await pool.query(`
        CREATE TABLE IF NOT EXISTS orders (
            id SERIAL PRIMARY KEY,
            customer TEXT NOT NULL,
            item TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            status TEXT NOT NULL
        )
    `);
}

async function createOrder(customer, item, quantity) {
    const result = await pool.query(
        `
        INSERT INTO orders (customer, item, quantity, status)
        VALUES ($1, $2, $3, 'CREATED')
        RETURNING id, customer, item, quantity, status
        `,
        [customer, item, quantity]
    );

    return result.rows[0];
}

async function getOrders() {
    const result = await pool.query(`
        SELECT id, customer, item, quantity, status
        FROM orders
        ORDER BY id
    `);

    return result.rows;
}

async function getOrderById(orderId) {
    const result = await pool.query(
        `
        SELECT id, customer, item, quantity, status
        FROM orders
        WHERE id = $1
        `,
        [orderId]
    );

    return result.rows[0];
}

async function closeDatabase() {
    await pool.end();
}

module.exports = {
    initializeDatabase,
    createOrder,
    getOrders,
    getOrderById,
    closeDatabase
};

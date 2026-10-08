const {
    initializeDatabase,
    closeDatabase
} = require("./orders");

async function main() {
    try {
        await initializeDatabase();

        console.log("Database initialization completed successfully");
    } catch (error) {
        console.error("Database initialization failed:", error);
        process.exitCode = 1;
    } finally {
        await closeDatabase();
    }
}

main();

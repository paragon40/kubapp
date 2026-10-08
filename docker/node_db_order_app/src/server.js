const app = require("./app");
const { initializeDatabase } = require("./orders");

const port = process.env.PORT || 3000;

async function start() {
    await initializeDatabase();

    app.listen(port, () => {
        console.log(`Order API listening on port ${port}`);
    });
}

start().catch((error) => {
    console.error("Failed to start application:", error);
    process.exit(1);
});


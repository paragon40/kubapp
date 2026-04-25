const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;

// serve static files
app.use(express.static(path.join(__dirname, "public")));

// simple API route (optional test)
app.get("/api/health", (req, res) => {
  res.json({
    status: "ok",
    message: "Node app is running ",
    time: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`Server running on http://0.0.0.0:${PORT}`);
});

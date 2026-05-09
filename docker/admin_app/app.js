const express = require("express");
const app = express();

const PORT = 4000;

const html = `
<!DOCTYPE html>
<html>
<head>
  <title>Admin Dashboard</title>
  <style>
    body { font-family: Arial; text-align: center; margin-top: 50px; background: #fff8f8; }
    .box { padding: 25px; border-radius: 12px; background: #ffebee; display: inline-block; }
    .badge { font-size: 14px; color: #b71c1c; }
  </style>
</head>
<body>
  <div class="box">
    <h1>🔐 ADMIN DASHBOARD</h1>
    <p class="badge">Restricted Area</p>
    <p>Status: OK</p>
  </div>
</body>
</html>
`;

// Root
app.get("/", (req, res) => res.send(html));

// Explicit route for ingress testing
app.get("/admin", (req, res) => res.send(html));

// Health checks
app.get("/health", (req, res) => {
  res.status(200).json({
    status: "healthy",
    service: "admin",
    port: PORT
  });
});

app.get("/live", (req, res) => {
  res.status(200).json({
    status: "alive",
    service: "admin",
    port: PORT
  });
});

app.listen(PORT, () => {
  console.log(`Admin app running on port ${PORT}`);
});

const express = require("express");
const path = require("path");
const routes = require("./routes/urlRoutes");

const app = express();
const PORT = process.env.PORT || 3000;

app.use(express.json());

// API
app.use("/api", routes);

// frontend
app.use(express.static(path.join(__dirname, "../../frontend")));

app.listen(PORT, () => {
  console.log(`Running on http://localhost:${PORT}`);
});

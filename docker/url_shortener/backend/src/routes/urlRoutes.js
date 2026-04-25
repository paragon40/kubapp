const express = require("express");
const controller = require("../controllers/urlController");

const router = express.Router();

router.post("/shorten", controller.shorten);
router.get("/urls", controller.list);
router.delete("/urls/:code", controller.remove);
router.get("/stats/:code", controller.stats);

router.get("/:code", controller.redirect);

module.exports = router;

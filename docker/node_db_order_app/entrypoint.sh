#!/bin/sh

if [ "$APP_MODE" = "health" ]; then
    exec node src/health.js
fi

exec node src/server.js

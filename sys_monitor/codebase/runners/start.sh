#!/bin/bash

echo "Building Codebase App.."
docker build -t codebase .
echo ""
echo "Running codebase next..."
docker run \
  -p 8080:8080 \
  -v "$(cd ../evidence && pwd):/evidence" \
  codebase


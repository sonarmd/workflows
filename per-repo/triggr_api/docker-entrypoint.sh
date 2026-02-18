#!/bin/sh
set -e

# Generate configuration.json from environment variables
node /app/generate-config.js

# Execute the main command (e.g., node dist/server.js)
exec "$@"

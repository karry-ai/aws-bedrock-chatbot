#!/usr/bin/env sh
set -e

# Substitute environment variables in config
envsubst < /app/config.json > /app/config.effective.json

# Set MCPO auth if API key is provided
if [ -n "$API_KEY" ]; then
  MCPO_AUTH="--api-key $API_KEY"
else
  MCPO_AUTH=""
fi

# Set port with default fallback
PORT=${PORT:-8000}

# Start MCPO with the effective config (supports both local and remote servers)
# Note: Using non-privileged port to avoid permission issues
exec mcpo --port $PORT $MCPO_AUTH --config /app/config.effective.json

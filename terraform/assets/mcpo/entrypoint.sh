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

# Start MCPO with the effective config
exec uvx mcpo --host 0.0.0.0 --port 80 $MCPO_AUTH --config /app/config.effective.json

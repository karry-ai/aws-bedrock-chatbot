FROM python:3.11-slim

# Install Node.js and npm
RUN apt-get update && apt-get install -y curl gnupg && \
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
RUN node -v && npm -v && npx --version

WORKDIR /app

COPY config.json config.json
COPY entrypoint.sh entrypoint.sh

# Install MCPO and uv
RUN pip install mcpo uv

# Install envsubst for environment variable substitution
RUN apt-get update && apt-get install -y gettext-base && apt-get clean && rm -rf /var/lib/apt/lists/*

# Make entrypoint executable
RUN chmod +x entrypoint.sh

# Set default port environment variable
ENV PORT=8000

EXPOSE $PORT

CMD ["./entrypoint.sh"]
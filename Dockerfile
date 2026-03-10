FROM ghcr.io/berriai/litellm:main-latest

# Install Node.js v20 LTS (Wolfi-based image uses apk)
RUN apk update && apk add --no-cache nodejs-20

# Copy configuration
COPY litellm-config.yaml /app/config.yaml

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:4000/health/liveliness')" || exit 1

# Start LiteLLM with config
CMD ["--config", "/app/config.yaml", "--port", "4000"]

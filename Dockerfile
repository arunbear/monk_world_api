# Use the pre-built image with all dependencies
FROM arunbear/monkworld-api-deps:0.001001

WORKDIR /app

# Create logs directory
RUN mkdir -p /app/logs && chmod -R a+rwX /app/logs

# Copy all files at once to avoid path issues
COPY . .

# Set proper permissions
RUN chmod -R a+rwX /app

# Expose the port your app runs on
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Default command to run the application
CMD ["hypnotoad", "-f", "script/monk_world_api"]

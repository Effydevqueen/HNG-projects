#!/bin/bash
# switch.sh

wait_for_healthy() {
    container="$1"
    port="$2"
    timeout="${3:-60}"
    interval=3
    start=$(date +%s)

    echo "Waiting for $container to become healthy (timeout ${timeout}s)..."

    while true; do
        now=$(date +%s)
        elapsed=$((now - start))
        
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "❌ Timeout waiting for $container to be healthy"
            return 1
        fi

        status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null)
        if [ "$status" = "healthy" ]; then
            echo "✅ $container is healthy"
            return 0
        fi

        if curl -sf "http://localhost:${port}/healthz" >/dev/null 2>&1; then
            echo "✅ $container health check passed"
            return 0
        fi
        echo "⏳ Waiting... (${elapsed}s)"
        sleep $interval
    done
}

# Determine current and target environments
if grep -q "ACTIVE_POOL=blue" .env; then
    TARGET_CONTAINER="green_app"
    TARGET_PORT="${GREEN_PORT:-8082}"
    NEW_POOL="green"
else
    TARGET_CONTAINER="blue_app"
    TARGET_PORT="${BLUE_PORT:-8081}"
    NEW_POOL="blue"
fi

# Validate health before switch
echo "🔍 Validating $TARGET_CONTAINER health before switching..."
if wait_for_healthy "$TARGET_CONTAINER" "$TARGET_PORT" 30; then
    echo "✅ Target container is healthy. Proceeding with switch..."

    # Update .env to reflect new active pool
    sed -i "s/ACTIVE_POOL=.*/ACTIVE_POOL=$NEW_POOL/" .env

    # Reload nginx with new config
    docker-compose up -d nginx

    # Verify nginx health
    sleep 3
    if curl -sf "http://localhost:${NGINX_PORT:-8080}/healthz" >/dev/null 2>&1; then
        echo "🎉 Switch completed successfully — NGINX now serving ${NEW_POOL} environment!"
        exit 0
    else
        echo "⚠️ Warning: NGINX health check failed after switch"
        exit 2
    fi
else
    echo "❌ Failed to switch — target environment not healthy"
    exit 1
fi

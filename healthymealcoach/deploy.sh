#!/bin/bash
set -euo pipefail

# ========== VARIABLES ==========
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="deploy_${TIMESTAMP}.log"
TMP_DIR="/tmp/deploy_repo"

trap 'echo "[ERROR] Script failed at line $LINENO." | tee -a "$LOG_FILE"; exit 1' ERR

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# ========== USER INPUTS ==========
read -p "Enter GitHub repository URL (e.g., https://github.com/user/repo.git): " REPO_URL
read -p "Enter GitHub Personal Access Token (PAT): " GITHUB_PAT
read -p "Enter branch name (default: main): " BRANCH
BRANCH=${BRANCH:-main}
read -p "Enter remote server username: " SSH_USER
read -p "Enter remote server IP address: " SSH_HOST
read -p "Enter SSH private key path (e.g., ~/.ssh/id_ed25519): " SSH_KEY_PATH
read -p "Enter application port (container internal port, e.g., 5000): " APP_PORT
read -p "Enter remote absolute path for deployment (e.g., /home/ubuntu/app): " REMOTE_PATH

log "Starting deployment..."

# ========== CLONE OR UPDATE REPO ==========
log "Cleaning temporary files..."
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

AUTH_REPO_URL="${REPO_URL/https:\/\/github.com/https:\/\/$GITHUB_PAT@github.com}"

log "Cloning repository from $REPO_URL (branch: $BRANCH)..."
git clone --branch "$BRANCH" "$AUTH_REPO_URL" "$TMP_DIR"

log "Repository ready at $TMP_DIR"

# ========== VERIFY DOCKERFILE ==========
if [ ! -f "$TMP_DIR/Dockerfile" ] && [ ! -f "$TMP_DIR/docker-compose.yml" ]; then
    log "[ERROR] No Dockerfile or docker-compose.yml found."
    exit 1
fi
log "Docker setup found in repository."

# ========== SSH CONNECTIVITY ==========
log "Testing SSH connection to $SSH_USER@$SSH_HOST..."
if ! ssh -i "$SSH_KEY_PATH" -o BatchMode=yes -o ConnectTimeout=5 "$SSH_USER@$SSH_HOST" "echo SSH OK" &>/dev/null; then
    log "[ERROR] SSH connection failed."
    exit 2
fi
log "SSH connectivity confirmed."

# ========== REMOTE ENVIRONMENT SETUP ==========
log "Installing Docker, Docker Compose, and Nginx on remote..."

ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" bash << EOF
set -e
sudo apt-get update -y

# Docker
if ! command -v docker >/dev/null; then
    sudo apt-get install -y docker.io
    sudo systemctl enable docker
    sudo systemctl start docker
fi

# Docker Compose
if ! command -v docker-compose >/dev/null; then
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-\$(uname -s)-\$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
fi

# Nginx
if ! command -v nginx >/dev/null; then
    sudo apt-get install -y nginx
    sudo systemctl enable nginx
    sudo systemctl start nginx
fi

# Docker group
if ! groups $SSH_USER | grep -qw docker; then
    sudo usermod -aG docker $SSH_USER
fi
EOF

# ========== TRANSFER FILES ==========
log "Transferring app files to $SSH_USER@$SSH_HOST:$REMOTE_PATH..."
ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" "mkdir -p '$REMOTE_PATH'"
rsync -e "ssh -i $SSH_KEY_PATH" -av --delete "$TMP_DIR"/ "$SSH_USER@$SSH_HOST:$REMOTE_PATH/"

# ========== DEPLOY APP ==========
log "Building and running Docker container on remote..."

ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" bash << EOF
set -e
cd "$REMOTE_PATH"

if [ \$(docker ps -q -f name=healthymealcoach) ]; then
    docker stop healthymealcoach || true
    docker rm healthymealcoach || true
fi

if [ -f docker-compose.yml ]; then
    docker-compose down || true
    docker-compose build
    docker-compose up -d
else
    docker build -t healthymealcoach .
    docker run -d -p $APP_PORT:$APP_PORT --name healthymealcoach healthymealcoach
fi
EOF


# ========== CONFIGURE NGINX ==========
log "Checking if port 80 is available..."
if ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" "sudo lsof -i :80 | grep LISTEN" &>/dev/null; then
    log "[WARN] Port 80 is already in use."
    log "[WARN] Attempting to force release of port 80 (testing)..."
    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" "sudo fuser -k 80/tcp || true"
    sleep 2
fi

log "[INFO] Setting up Nginx reverse proxy..."

ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" bash << EOF
set -e

# Set up Nginx config
NGINX_CONF="/etc/nginx/sites-available/healthymealcoach"
NGINX_LINK="/etc/nginx/sites-enabled/healthymealcoach"

# Remove default config to prevent conflict
sudo rm -f /etc/nginx/sites-enabled/default

# Create new config
sudo tee \$NGINX_CONF > /dev/null << NGINXCONF
server {
    listen 80;
    server_name $SSH_HOST;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
NGINXCONF

sudo ln -sf \$NGINX_CONF \$NGINX_LINK

# Test Nginx config
log "[INFO] Testing Nginx configuration..."
if ! sudo nginx -t; then
    echo "[ERROR] Nginx config test failed."
    exit 1
fi

# Start or reload Nginx
if ! sudo systemctl is-active --quiet nginx; then
    echo "[INFO] Starting Nginx..."
    sudo systemctl enable nginx
    sudo systemctl start nginx
else
    echo "[INFO] Reloading Nginx..."
    sudo systemctl reload nginx
fi
EOF

# ========== VALIDATION ==========
log "Validating deployment..."

ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" bash << EOF
set -e

if ! systemctl is-active --quiet docker; then
    echo "Docker not running"
    exit 3
fi

STATUS=\$(docker inspect -f '{{.State.Status}}' healthymealcoach 2>/dev/null || echo "not found")
if [ "\$STATUS" != "running" ]; then
    echo "Container is not running."
    exit 4
fi

if curl -s http://localhost | grep -iq "<html>"; then
    echo "App is reachable via Nginx."
else
    echo "App is NOT reachable via Nginx."
    exit 5
fi
EOF

# ========== CLEANUP SUPPORT ==========
if [[ "${1:-}" == "--cleanup" ]]; then
    log "Cleanup requested. Removing app..."

    ssh -i "$SSH_KEY_PATH" "$SSH_USER@$SSH_HOST" bash << EOF
    docker stop healthymealcoach || true
    docker rm healthymealcoach || true
    docker rmi healthymealcoach || true
    sudo rm -f /etc/nginx/sites-available/healthymealcoach
    sudo rm -f /etc/nginx/sites-enabled/healthymealcoach
    sudo systemctl reload nginx
EOF
    log "Cleanup completed."
    exit 0
fi

# ========== DONE ==========
log "=============================================="
log "✅ Deployment successful!"
log "🌐 Visit your app at: http://$SSH_HOST"
log "📜 Logs saved to: $LOG_FILE"
log "=============================================="


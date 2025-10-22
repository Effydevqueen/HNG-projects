#!/bin/bash
set -e

echo "=============================================="
echo "     🚀 HealthyMealCoach Deployment Script"
echo "=============================================="
echo

# --- USER INPUTS ---
read -p "Enter GitHub repository URL (e.g., https://github.com/Effydevqueen/HNG-projects.git): " REPO_URL
read -p "Enter branch name (e.g., main): " BRANCH
read -p "Enter application port (container internal port, e.g., 5000): " APP_PORT
read -p "Enter absolute path on EC2 for deployment (e.g., /home/ubuntu/app): " EC2_PATH
read -p "Enter SSH private key path (e.g., ~/.ssh/id_ed25519): " SSH_KEY_PATH

echo
echo "[INFO] Starting deployment..."
echo

# --- PREPARE WORKSPACE ---
echo "[INFO] Cleaning previous temporary files..."
rm -rf /tmp/deploy_repo
mkdir -p /tmp/deploy_repo

# --- CLONE REPOSITORY ---
echo "[INFO] Cloning repository from $REPO_URL (branch: $BRANCH)"
git clone --branch "$BRANCH" "$REPO_URL" /tmp/deploy_repo

# --- NAVIGATE TO APP FOLDER ---
APP_DIR="/tmp/deploy_repo/healthymealcoach"
if [ ! -d "$APP_DIR" ]; then
    echo "[ERROR] Could not find 'healthymealcoach' folder inside the repository."
    exit 1
fi
cd "$APP_DIR"

echo "[INFO] Current directory: $(pwd)"
echo

# --- DEPLOY TO EC2 PATH ---
echo "[INFO] Copying app files to EC2 path..."
mkdir -p "$EC2_PATH"
cp -r ./* "$EC2_PATH"/

cd "$EC2_PATH"
echo "[INFO] Switched to deployment directory: $(pwd)"
echo

# --- BUILD DOCKER IMAGE ---
echo "[INFO] Building Docker image..."
docker build -t healthymealcoach .

# --- STOP EXISTING CONTAINER ---
if [ "$(docker ps -q -f name=healthymealcoach)" ]; then
    echo "[INFO] Stopping existing container..."
    docker stop healthymealcoach
    docker rm healthymealcoach
fi

# --- RUN NEW CONTAINER ---
echo "[INFO] Running new container on port $APP_PORT..."
docker run -d -p "$APP_PORT":"$APP_PORT" --name healthymealcoach healthymealcoach

echo
echo "=============================================="
echo " ✅ Deployment successful!"
echo " Application is running on port $APP_PORT"
echo "=============================================="


# # ========== CONFIGURE NGINX ==========
NGINX_CONF="/etc/nginx/sites-available/healthymealcoach"
NGINX_LINK="/etc/nginx/sites-enabled/healthymealcoach"

echo "[INFO] Checking if port 80 is available..."
if sudo lsof -i :80 | grep -q LISTEN; then
    echo "[WARN] Port 80 is already in use."

    echo "[WARN] Attempting to force release of port 80 (testing mode only)..."
    sudo fuser -k 80/tcp

    sleep 2
    echo "[INFO] Re-checking port 80..."
    if sudo lsof -i :80 | grep -q LISTEN; then
        echo "[ERROR] Port 80 is still in use. Cannot proceed."
        exit 1
    else
        echo "[INFO] Port 80 successfully freed."
    fi
else
    echo "[INFO] Port 80 is available."
fi

echo "[INFO] Setting up Nginx reverse proxy..."
sudo tee "$NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf "$NGINX_CONF" "$NGINX_LINK"
echo "[INFO] Testing Nginx configuration..."
sudo nginx -t
echo "[INFO] Reloading Nginx..."
sudo systemctl reload nginx

# ========== VALIDATE DEPLOYMENT ==========
echo "[INFO] Validating Docker container status..."
CONTAINER_STATUS=$(docker inspect -f '{{.State.Status}}' healthymealcoach || echo "not found")
if [[ "$CONTAINER_STATUS" != "running" ]]; then
    echo "[ERROR] Container is not running."
    exit 1
fi
echo "[INFO] Testing app endpoint via Nginx (localhost)..."
if curl -s "http://localhost" | grep -iq "<html>"; then
    echo "[INFO] App is reachable via Nginx!"
else
    echo "[ERROR] App is not reachable through Nginx."
    exit 1
fi

# ========== FINAL MESSAGE ==========
echo
echo "=============================================="
echo " ✅ Deployment successful!"
echo " 🌐 App should be reachable at: http://<your-ec2-public-ip>"
echo " 📜 Logs saved to: $LOG_FILE"
echo "=============================================="


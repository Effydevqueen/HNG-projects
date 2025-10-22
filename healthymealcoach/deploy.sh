#!/bin/bash

# Exit if any command fails
set -e

# Variables
PROJECT_ROOT="/home/ubuntu/hng13-projects/hng13-stage1-devopstask"
APP_DIR="$PROJECT_ROOT/healthymealcoach"
REPO_URL="https://github.com/Effydevqueen/HNG-projects.git"
BRANCH="main"
IMAGE_NAME="healthymealcoach"
CONTAINER_NAME="healthymealcoach-container"

echo "---- Starting deployment ----"

# Move to project root
cd /home/ubuntu/hng13-projects/

# Clone or update repository
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo "Cloning repository..."
    git clone -b $BRANCH $REPO_URL
else
    echo "Pulling latest changes from repository..."
    cd $PROJECT_ROOT
    git fetch origin $BRANCH
    git reset --hard origin/$BRANCH
fi

# Move into app directory
cd $APP_DIR

echo "---- Building Docker image ----"
docker build -t $IMAGE_NAME .

# Stop and remove any existing container with same name
if [ "$(docker ps -aq -f name=$CONTAINER_NAME)" ]; then
    echo "Stopping existing container..."
    docker stop $CONTAINER_NAME || true
    docker rm $CONTAINER_NAME || true
fi

echo "---- Running new container ----"
docker run -d \
  --name $CONTAINER_NAME \
  -p 5000:5000 \
  $IMAGE_NAME

echo "---- Deployment successful! ----"
docker ps | grep $CONTAINER_NAME


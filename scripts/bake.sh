#!/bin/bash
set -e

REPO=$1
if [ -z "$REPO" ]; then
  echo >&2 error: bake: missing repository
  exit 1
fi
CONFIG=${2:-dev}

echo Baking...

if [ -e "./build.sh" ]; then
  "./build.sh" $CONFIG
fi

docker build -t $REPO:latest .

if [ "$CONFIG" == "dev" ]; then
  TAG=$CONFIG-$(whoami)-$(docker images -q $REPO:latest)
else
  TAG=$(git rev-parse HEAD)
fi

docker tag $REPO:latest $REPO:$TAG
docker push $REPO:$TAG
docker rmi $REPO:$TAG

echo Bake completed

#!/bin/bash
set -e

SERVICE=$1
if [ -z "$SERVICE" ]; then
  echo >&2 error: deploy: missing service name
  exit 1
fi
REPO=$2
if [ -z "$REPO" ]; then
  echo >&2 error: deploy: missing repository
  exit 1
fi
CONFIG=${3:-dev}

echo Deploying...

kubectl get service $SERVICE >/dev/null 2>&1 || cat << EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $SERVICE
  labels:
    run: $SERVICE
spec:
  selector:
    run: l5d
  type: ClusterIP
  ports:
  - name: http
    port: 80
EOF

LABELS="via=$SERVICE"
if [ "$CONFIG" == "dev" ]; then
  TAG=$CONFIG-$(whoami)-$(docker images -q $REPO:latest)
  DEPLOY=$SERVICE-$CONFIG-$(whoami)
  LABELS="$LABELS,$CONFIG=$(whoami)"
else
  TAG=$(git rev-parse HEAD)
  DEPLOY=$SERVICE-${TAG::7}
  LABELS="$LABELS,track=canary"
fi
LABELS="$LABELS,run=$DEPLOY"

EXISTS=$(kubectl get deployment -l run=$DEPLOY -o go-template='{{range .items}}{{.metadata.name}}{{end}}')
if [ -z "$EXISTS" ]; then
  kubectl run $DEPLOY --image=$REPO:$TAG --port=80
  kubectl rollout status deployment/$DEPLOY
  kubectl expose deployment $DEPLOY --type=ClusterIP --port=80 -l $LABELS
elif [ "$CONFIG" == "dev" ]; then
  kubectl set image deployment/$DEPLOY $DEPLOY=$REPO:$TAG
  kubectl rollout status deployment/$DEPLOY
else
  echo >&2 error: deploy: deployment "$DEPLOY" already deployed
  exit 1
fi

echo Deploy completed

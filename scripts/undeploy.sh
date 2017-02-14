#!/bin/bash
set -e

SERVICE=$1
if [ -z "$SERVICE" ]; then
  echo >&2 error: cleanup: missing service name
  exit 1
fi

echo Undeploying...

CANARY=$(kubectl get service -l via=$SERVICE,track=canary -o go-template='{{range .items}}{{.metadata.name}}{{end}}')

kubectl delete deployment,service -l run=$CANARY

echo Undeploy completed

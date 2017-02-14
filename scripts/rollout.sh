#!/bin/bash
set -e

SERVICE=$1
if [ -z "$SERVICE" ]; then
  echo >&2 error: rollout: missing service name
  exit 1
fi

echo Rolling out...

STABLE=$(kubectl get service -l via=$SERVICE,track=stable -o go-template='{{range .items}}{{.metadata.name}}{{end}}')
CANARY=$(kubectl get service -l via=$SERVICE,track=canary -o go-template='{{range .items}}{{.metadata.name}}{{end}}')
if [ -z "$CANARY" ]; then
  echo >&2 error: rollout: no canary service to roll out
  exit 1
fi

update-l5d-rule() {
  kubectl annotate --overwrite service $SERVICE l5d="$1"
}

rollout-to() {
  PERCENT=$1
  update-l5d-rule "$((100-PERCENT))*/svc/$STABLE & $PERCENT*/svc/$CANARY"
}

reset() {
  update-l5d-rule 100*/svc/$STABLE
}

update-track() {
  kubectl label --overwrite service $1 track=$2
}

if [ -z "$STABLE" ]; then
  update-track $CANARY stable
  STABLE=$CANARY
  reset
  echo Rollout completed
  exit 0
fi

for percent in 5 10 20 50 100; do
  echo -n "Rollout to $percent%? (y/n): "
  read answer
  if [ "$answer" == "y" ]; then
    rollout-to $percent
  else
    echo Rolling back...
    reset
    exit 1
  fi
done

update-track $CANARY stable
update-track $STABLE canary

STABLE=$CANARY
reset

echo Rollout completed

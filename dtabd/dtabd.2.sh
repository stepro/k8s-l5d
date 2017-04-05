#!/bin/bash
set -e

TEMPLATE="$1"
if [ -z "$TEMPLATE" ]; then
  echo >&2 error: dtabd: must specify template file
  exit 1
fi
if [ ! -e "$TEMPLATE" ]; then
  echo >&2 error: dtabd: template file \"$TEMPLATE\" not found
  exit 1
fi
if [ -n "$ENV_SUBST" ]; then
  envsubst "$ENV_SUBST" < "$TEMPLATE" > "$(dirname $0)/dtab.tmpl"
  TEMPLATE="$(dirname $0)/dtab.tmpl"
fi
N4D_HOST=${2:-localhost:4180}
KINDS=${3:-namespace,ingress,service}

until curl -s $N4D_HOST/api/1/dtabs > /dev/null; do
  echo dtabd: waiting for connectivity...
  sleep 1
done

update() {
    kubectl get --all-namespaces $KINDS -o go-template-file="$TEMPLATE" \
    | curl -isX PUT $N4D_HOST/api/1/dtabs/default -H 'Content-Type: application/dtab' -H 'Expect:' -d @- \
    | head -n1
}

echo -n dtabd: initializing dtab...
update

watch() {
  KIND=$1
  while read resource; do
    echo dtabd: $resource was created, updated or deleted
    echo -n dtabd: updating dtab...
    update
  done < <(kubectl get --all-namespaces $KIND --watch-only -o go-template='{{.kind}} "{{.metadata.name}}.{{.metadata.namespace}}"
')
}

PIDS=
trap "kill $PIDS; exit 130" INT
trap "kill $PIDS; exit 143" TERM

for kind in ${KINDS//,/ }; do
  watch $kind &
  PIDS="$PIDS $!"
done

wait $PIDS
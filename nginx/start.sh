#!/bin/bash
set -e

NGINX_TEMPLATE="$1"
if [ -z "$NGINX_TEMPLATE" ]; then
  echo >&2 error: must specify nginx template file
  exit 1
fi
if [ ! -e "$NGINX_TEMPLATE" ]; then
  echo >&2 error: template file \"$NGINX_TEMPLATE\" not found
  exit 1
fi
DTAB_TEMPLATE="$2"
if [ -z "$DTAB_TEMPLATE" ]; then
  echo >&2 error: must specify dtab template file
  exit 1
fi
if [ ! -e "$DTAB_TEMPLATE" ]; then
  echo >&2 error: template file \"$DTAB_TEMPLATE\" not found
  exit 1
fi
if [ -n "$ENV_SUBST" ]; then
  envsubst "$ENV_SUBST" < "$NGINX_TEMPLATE" > "$(dirname $0)/nginx.conf.tmpl"
  NGINX_TEMPLATE="$(dirname $0)/nginx.conf.tmpl"
  envsubst "$ENV_SUBST" < "$DTAB_TEMPLATE" > "$(dirname $0)/dtab.tmpl"
  DTAB_TEMPLATE="$(dirname $0)/dtab.tmpl"
fi
KINDS=$3
if [ -z "$KINDS" ]; then
  echo >&2 error: must specify resource types
  exit 1
fi
N4D_HOST=${4:-localhost:4180}
N4D_NAMESPACE=${5:-default}

until curl -s $N4D_HOST/api/1/dtabs > /dev/null; do
  echo Waiting for namerd...
  sleep 1
done

update-nginx() {
  kubectl get $KINDS -o go-template-file="$NGINX_TEMPLATE" > /etc/nginx/nginx.conf
  nginx -s reload
  echo done
}

update-dtab() {
  kubectl get $KINDS -o go-template-file="$DTAB_TEMPLATE" \
  | curl -isX PUT $N4D_HOST/api/1/dtabs/$N4D_NAMESPACE -H 'Content-Type: application/dtab' -H 'Expect:' -d @- \
  | head -n1
}

echo -n Initializing dtab...
update-dtab

echo -n Initializing nginx...
kubectl get $KINDS -o go-template-file="$NGINX_TEMPLATE" > /etc/nginx/nginx.conf
echo done

echo -n Starting nginx...
nginx
echo done

watch() {
  KIND=$1
  while read resource; do
    echo $resource was created, updated or deleted
    echo -n Updating dtab...
    update-dtab
    echo -n Updating nginx...
    update-nginx
  done < <(kubectl get $KIND --watch-only -o go-template='{{.kind}} "{{.metadata.name}}"
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

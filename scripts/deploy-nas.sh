#!/bin/sh
set -eu
: "${PROD_ENV_FILE:?Define protected File variable PROD_ENV_FILE in GitLab}"
: "${CI_COMMIT_SHA:?Missing CI_COMMIT_SHA}"
test -f "$PROD_ENV_FILE" || { echo 'PROD_ENV_FILE must be a File variable.' >&2; exit 1; }
umask 077
cp "$PROD_ENV_FILE" .env
trap 'rm -f .env' EXIT HUP INT TERM
export APP_IMAGE_TAG="$CI_COMMIT_SHA"
compose() { docker compose --env-file .env -f compose.prod.yaml "$@"; }
compose config --quiet
docker image inspect "k-agora:$APP_IMAGE_TAG" >/dev/null || {
  echo 'Verified image missing from NAS Docker. Rerun build-test and image-scan in this pipeline.' >&2; exit 1;
}
existing="$(compose ps -q app)"
existing_port=''
if [ -n "$existing" ] && [ "$(docker inspect --format '{{.State.Running}}' "$existing")" = true ]; then
  existing_port="$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$existing" | sed -n 's/^PORT=//p')"
fi
compose run --rm --no-deps -e "K_AGORA_EXISTING_PORT=$existing_port" app python scripts/nas-preflight.py
compose up -d --no-build app
container="$(compose ps -q app)"
attempt=0
while [ "$attempt" -lt 60 ]; do
  health="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}missing{{end}}' "$container")"
  case "$health" in
    healthy) echo 'K-AGORA deployed; health check passed. Persistent DB volume: k-agora-data'; exit 0 ;;
    unhealthy|missing) echo "Deployment health check failed: $health" >&2; exit 1 ;;
  esac
  attempt=$((attempt + 1))
  sleep 2
done
echo 'Deployment health check timed out. Inspect the container on the NAS.' >&2
exit 1

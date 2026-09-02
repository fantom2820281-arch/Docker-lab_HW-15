#!/usr/bin/env bash
# ДЗ: скачать форк в /opt и поднять проект.
# На ВМ лежит в ДОМАШНЕМ каталоге, не в /opt:
#   sudo bash ~/deploy-to-opt.sh
# /opt/Docker-lab_HW-15 создаёт сам git clone.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/fantom2820281-arch/Docker-lab_HW-15.git}"
REPO_DIR="${REPO_DIR:-/opt/Docker-lab_HW-15}"
RETRY_WAIT="${RETRY_WAIT:-5}"
HTTP_WAIT_SEC="${HTTP_WAIT_SEC:-90}"

export DEBIAN_FRONTEND=noninteractive
export COMPOSE_HTTP_TIMEOUT="${COMPOSE_HTTP_TIMEOUT:-300}"

log() { printf '\n[%s] %s\n' "$(date '+%H:%M:%S')" "$*"; }
die() { printf 'ОШИБКА: %s\n' "$*" >&2; exit 1; }

retry() {
  local attempt=1
  local max=5
  until "$@"; do
    if (( attempt >= max )); then
      die "не вышло после ${max} попыток: $*"
    fi
    log "Повтор ${attempt}/${max} через ${RETRY_WAIT}с..."
    sleep "${RETRY_WAIT}"
    attempt=$((attempt + 1))
  done
}

wait_http() {
  local url="$1"
  local deadline=$((SECONDS + HTTP_WAIT_SEC))
  while (( SECONDS < deadline )); do
    if curl -fsS --max-time 5 "${url}" >/dev/null; then
      log "Ответил ${url}"
      return 0
    fi
    sleep 3
  done
  log "Пока тихо: curl -v ${url}"
  return 1
}

[[ "$(id -u)" -eq 0 ]] || die "нужен root: sudo bash $0"

log "1/4 пакеты"
retry apt-get update -y
retry apt-get install -y ca-certificates curl git gnupg

log "2/4 Docker"
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  log "Docker уже есть — установку пропускаю."
  docker --version
  docker compose version
else
  install -m 0755 -d /etc/apt/keyrings
  retry curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # shellcheck disable=SC1091
  . /etc/os-release
  printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
    "$(dpkg --print-architecture)" "${VERSION_CODENAME}" \
    > /etc/apt/sources.list.d/docker.list
  retry apt-get update -y
  retry apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
systemctl enable --now docker
usermod -aG docker dima 2>/dev/null || true
usermod -aG docker ubuntu 2>/dev/null || true

log "3/4 клон в ${REPO_DIR}"
if [[ -d "${REPO_DIR}/.git" ]]; then
  retry git -C "${REPO_DIR}" pull --ff-only
elif [[ -e "${REPO_DIR}" ]]; then
  die "${REPO_DIR} уже есть и это не git. Разбери руками."
else
  retry git clone "${REPO_URL}" "${REPO_DIR}"
fi

log "4/4 .env и compose"
if [[ ! -f "${REPO_DIR}/.env" ]]; then
  if [[ -f "${REPO_DIR}/.env.example" ]]; then
    die "Нет ${REPO_DIR}/.env (секреты не в git).
  sudo cp ${REPO_DIR}/.env.example ${REPO_DIR}/.env
  sudo nano ${REPO_DIR}/.env
Потом снова: sudo bash $0"
  fi
  die "Нет ни .env, ни .env.example в ${REPO_DIR}."
fi

cd "${REPO_DIR}"
retry docker compose up -d --build
docker compose ps

wait_http "http://127.0.0.1:8090" || true
curl -fsS --max-time 10 http://127.0.0.1:8090 || true

EXT_IP="$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null || true)"
cat <<EOF

Готово: ${REPO_DIR}
  на ВМ:     curl http://127.0.0.1:8090
  с улицы:   http://${EXT_IP:-<IP>}:8090

check-host.net (браузер на ноутбуке, не на ВМ):
  1. открыть https://check-host.net/check-http
  2. в поле вставить: http://${EXT_IP:-<IP>}:8090
  3. Check → скриншот зелёных узлов (цепочка Nginx → HAProxy → FastAPI → БД)
EOF

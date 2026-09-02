#!/usr/bin/env bash
# Задача 5: дамп MySQL в /opt/backup через schnitzler/mysqldump в сети backend.
# Пароли НЕ в git: читаем /opt/Docker-lab_HW-15/.env (тот же файл, что у compose).
#
# Ручной тест на ВМ:
#   sudo bash /path/to/backup-mysql.sh
#   ls -l /opt/backup
#
# Cron раз в минуту (паролей в crontab нет):
#   sudo cp backup-mysql.sh /usr/local/bin/backup-mysql.sh
#   sudo chmod 700 /usr/local/bin/backup-mysql.sh
#   echo '* * * * * root /usr/local/bin/backup-mysql.sh' | sudo tee /etc/cron.d/mysql-backup
#   sudo chmod 644 /etc/cron.d/mysql-backup
set -euo pipefail

ENV_FILE="${ENV_FILE:-/opt/Docker-lab_HW-15/.env}"
BACKUP_DIR="${BACKUP_DIR:-/opt/backup}"
IMAGE="${IMAGE:-schnitzler/mysqldump}"

[[ "$(id -u)" -eq 0 ]] || { echo "нужен root: sudo $0" >&2; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "нет ${ENV_FILE}" >&2; exit 1; }

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

: "${MYSQL_USER:?}" "${MYSQL_PASSWORD:?}" "${MYSQL_DATABASE:?}"

mkdir -p "${BACKUP_DIR}"
chmod 700 "${BACKUP_DIR}"

NETWORK="$(docker network ls --format '{{.Name}}' | grep -E '_backend$' | head -n1 || true)"
[[ -n "${NETWORK}" ]] || { echo "сеть *backend не найдена. Сначала подними проект." >&2; exit 1; }

STAMP="$(date +%s_%Y-%m-%d_%H%M%S)"
OUT="${BACKUP_DIR}/${STAMP}_${MYSQL_DATABASE}.sql"

# Документация образа: single backup = пустой entrypoint + mysqldump.
# Сеть backend — как в задании; хост db = сервис compose (172.20.0.10).
docker run --rm \
  --network "${NETWORK}" \
  --entrypoint "" \
  -v "${BACKUP_DIR}:/backup" \
  -e MYSQL_HOST=db \
  -e MYSQL_USER="${MYSQL_USER}" \
  -e MYSQL_PASSWORD="${MYSQL_PASSWORD}" \
  -e MYSQL_DATABASE="${MYSQL_DATABASE}" \
  "${IMAGE}" \
  mysqldump --opt \
    -h db \
    -u "${MYSQL_USER}" \
    -p"${MYSQL_PASSWORD}" \
    --result-file="/backup/$(basename "${OUT}")" \
    "${MYSQL_DATABASE}"

echo "ok ${OUT} ($(wc -c < "${OUT}") bytes) network=${NETWORK}"

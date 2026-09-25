#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# healthcheck.sh — проверка состояния сервера по пороговым значениям.
#
# Назначение : регулярный автоматический контроль (запуск из cron).
# Зависимости: coreutils; опционально systemctl, procps.
# Коды возврата:
#   0 — все проверки в норме
#   1 — ошибка конфигурации
#   3 — обнаружены отклонения (используется системой мониторинга)
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${TOOLKIT_CONFIG:-$REPO_ROOT/config/toolkit.conf}"

DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-85}"
MEMORY_USAGE_THRESHOLD="${MEMORY_USAGE_THRESHOLD:-90}"
CRITICAL_SERVICES="${CRITICAL_SERVICES:-sshd cron}"

WARNINGS=0

usage() {
    cat <<'USAGE'
Использование: healthcheck.sh [ОПЦИЯ]

Проверяет заполненность дисков, использование памяти и состояние
критичных служб. Предназначен для запуска из cron.

Опции:
  -h, --help     показать справку
  -q, --quiet    выводить только отклонения

Коды возврата: 0 — норма, 3 — есть отклонения.
USAGE
}

QUIET=0
log()  { [ "$QUIET" -eq 1 ] || echo "[$(date '+%H:%M:%S')] $*"; }
warn() { echo "[$(date '+%H:%M:%S')] ВНИМАНИЕ: $*"; WARNINGS=$((WARNINGS + 1)); }
has()  { command -v "$1" >/dev/null 2>&1; }

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" || { echo "Не удалось прочитать $CONFIG_FILE" >&2; exit 1; }
    fi
}

check_disk() {
    log "Проверяю дисковое пространство (порог ${DISK_USAGE_THRESHOLD}%)"
    local line mount usage
    while read -r line; do
        usage="$(echo "$line" | awk '{print $5}' | tr -d '%')"
        mount="$(echo "$line" | awk '{print $6}')"
        [[ "$usage" =~ ^[0-9]+$ ]] || continue
        if [ "$usage" -ge "$DISK_USAGE_THRESHOLD" ]; then
            warn "раздел $mount заполнен на ${usage}%"
        else
            log "  $mount — ${usage}%, норма"
        fi
    done < <(df -P 2>/dev/null | tail -n +2 | grep -v -E "tmpfs|devfs|map ")
}

check_memory() {
    log "Проверяю память (порог ${MEMORY_USAGE_THRESHOLD}%)"
    if ! has free; then
        log "  (free недоступна, проверка пропущена)"
        return 0
    fi
    local total used percent
    total="$(free | awk '/^Mem:/ {print $2}')"
    used="$(free | awk '/^Mem:/ {print $3}')"
    [ "${total:-0}" -gt 0 ] || { log "  (не удалось определить объём памяти)"; return 0; }
    percent=$(( used * 100 / total ))
    if [ "$percent" -ge "$MEMORY_USAGE_THRESHOLD" ]; then
        warn "память занята на ${percent}%"
    else
        log "  память — ${percent}%, норма"
    fi
}

check_services() {
    log "Проверяю критичные службы: $CRITICAL_SERVICES"
    if ! has systemctl; then
        log "  (systemctl недоступен, проверка пропущена)"
        return 0
    fi
    local svc
    for svc in $CRITICAL_SERVICES; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            log "  $svc — работает"
        else
            warn "служба $svc не запущена"
        fi
    done
}

main() {
    load_config

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)  usage; exit 0 ;;
            -q|--quiet) QUIET=1; shift ;;
            *)          echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    log "=== Проверка состояния сервера ==="
    check_disk
    check_memory
    check_services

    if [ "$WARNINGS" -gt 0 ]; then
        echo "Обнаружено отклонений: $WARNINGS"
        exit 3
    fi
    log "Все проверки пройдены, отклонений нет"
    return 0
}

main "$@"

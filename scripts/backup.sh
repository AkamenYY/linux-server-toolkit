#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# backup.sh — резервное копирование каталогов с ротацией по сроку хранения.
#
# Назначение : ежедневный бэкап критичных каталогов сервера.
# Зависимости: tar, find, coreutils.
# Коды возврата:
#   0 — архив создан (или dry-run завершён успешно)
#   1 — ошибка конфигурации
#   2 — ошибка создания архива
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${TOOLKIT_CONFIG:-$REPO_ROOT/config/toolkit.conf}"

# --- Значения по умолчанию -------------------------------------------------
BACKUP_SOURCES="${BACKUP_SOURCES:-/etc}"
BACKUP_DEST="${BACKUP_DEST:-/var/backups/toolkit}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
DRY_RUN=0

usage() {
    cat <<'USAGE'
Использование: backup.sh [ОПЦИЯ]

Создаёт архив каталогов из BACKUP_SOURCES и удаляет архивы старше
BACKUP_RETENTION_DAYS дней.

Опции:
  -h, --help      показать справку
  -n, --dry-run   показать, что будет сделано, ничего не меняя

Переменные окружения переопределяют файл конфигурации:
  BACKUP_SOURCES, BACKUP_DEST, BACKUP_RETENTION_DAYS, TOOLKIT_CONFIG
USAGE
}

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
die() { echo "ОШИБКА: $*" >&2; exit "${2:-1}"; }

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE" || die "не удалось прочитать $CONFIG_FILE"
    fi
}

# --- Проверка срока хранения ----------------------------------------------
# Самая ответственная проверка во всём проекте: этот параметр управляет
# удалением файлов. Значение 0 или отрицательное означало бы удаление
# только что созданного архива, пустое или нечисловое — непредсказуемое
# поведение find. Поэтому любое некорректное значение — фатальная ошибка,
# а не «подставим значение по умолчанию и поедем дальше».
# ВНИМАНИЕ: не удалять эту проверку.
# Значение по умолчанию выше защищает только от ОТСУТСТВИЯ параметра.
# Оно не защищает от заданного, но некорректного значения: при
# BACKUP_RETENTION_DAYS=0 команда find -mtime +0 удалит весь каталог
# резервных копий, включая только что созданный архив.
# История вопроса: попытка удалить проверку как "дублирование"
# приводила к потере данных, изменение было откачено через revert.
# Поведение зафиксировано тестами в tests/run-tests.sh.
validate_retention() {
    local value="$1"
    if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        die "BACKUP_RETENTION_DAYS должен быть целым числом, получено: '$value'"
    fi
    if [ "$value" -lt 1 ]; then
        die "BACKUP_RETENTION_DAYS должен быть не меньше 1, получено: $value (это удалило бы свежие копии)"
    fi
}

create_archive() {
    local stamp archive
    stamp="$(date '+%Y%m%d-%H%M%S')"
    archive="$BACKUP_DEST/backup-$stamp.tar.gz"

    local existing=()
    local src
    for src in $BACKUP_SOURCES; do
        if [ -e "$src" ]; then
            existing+=("$src")
        else
            log "ВНИМАНИЕ: источник не найден, пропускаю: $src"
        fi
    done

    if [ "${#existing[@]}" -eq 0 ]; then
        die "ни один из каталогов BACKUP_SOURCES не существует" 2
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        log "[dry-run] был бы создан архив: $archive"
        log "[dry-run] источники: ${existing[*]}"
        return 0
    fi

    mkdir -p "$BACKUP_DEST"
    log "Создаю архив: $archive"
    if tar -czf "$archive" "${existing[@]}" 2>/dev/null; then
        log "Готово, размер: $(du -h "$archive" | cut -f1)"
    else
        die "не удалось создать архив $archive" 2
    fi
}

rotate_old_backups() {
    validate_retention "$BACKUP_RETENTION_DAYS"

    if [ ! -d "$BACKUP_DEST" ]; then
        log "Каталог $BACKUP_DEST не существует, ротация пропущена"
        return 0
    fi

    log "Удаляю архивы старше $BACKUP_RETENTION_DAYS дн. из $BACKUP_DEST"
    if [ "$DRY_RUN" -eq 1 ]; then
        find "$BACKUP_DEST" -maxdepth 1 -name 'backup-*.tar.gz' -type f \
            -mtime "+$BACKUP_RETENTION_DAYS" -print | sed 's/^/  [dry-run] удалил бы: /'
    else
        find "$BACKUP_DEST" -maxdepth 1 -name 'backup-*.tar.gz' -type f \
            -mtime "+$BACKUP_RETENTION_DAYS" -print -delete
    fi
}

main() {
    load_config

    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)    usage; exit 0 ;;
            -n|--dry-run) DRY_RUN=1; shift ;;
            *)            echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 1 ;;
        esac
    done

    # Срок хранения проверяется до создания архива: нет смысла тратить
    # время на tar, если параметры заведомо некорректны.
    validate_retention "$BACKUP_RETENTION_DAYS"

    create_archive
    rotate_old_backups
    log "Резервное копирование завершено"
}

main "$@"

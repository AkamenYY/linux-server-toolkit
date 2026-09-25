#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# sysinfo.sh — сбор диагностической сводки о состоянии сервера.
#
# Назначение : первый шаг при разборе любой нештатной ситуации.
# Зависимости: coreutils; опционально iproute2, procps, util-linux.
#              Отсутствующие утилиты не считаются ошибкой — соответствующий
#              раздел помечается как недоступный.
# Коды возврата:
#   0 — сводка собрана
#   1 — ошибка чтения конфигурации или неизвестный аргумент
# ---------------------------------------------------------------------------

set -euo pipefail

# Каталог самого скрипта: путь не зависит от того, откуда его запустили.
# Это принципиально для запуска из cron. (Замечание №3 ревью.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${TOOLKIT_CONFIG:-$REPO_ROOT/config/toolkit.conf}"

# --- Значения по умолчанию (переопределяются конфигурацией и окружением) ---
LOG_LEVEL="${LOG_LEVEL:-INFO}"

usage() {
    cat <<'USAGE'
Использование: sysinfo.sh [ОПЦИЯ]

Выводит сводку о состоянии сервера.

Опции:
  -h, --help          показать эту справку и выйти
      --show-config   показать действующую конфигурацию и выйти
      --no-color      отключить цветной вывод

Примеры:
  ./sysinfo.sh
  TOOLKIT_CONFIG=/etc/toolkit.conf ./sysinfo.sh --show-config
USAGE
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck source=/dev/null
        if ! source "$CONFIG_FILE"; then
            echo "Ошибка: не удалось прочитать конфигурацию $CONFIG_FILE" >&2
            exit 1
        fi
    fi
}

# Утилита есть в системе?
has() { command -v "$1" >/dev/null 2>&1; }

# Раздел с мягкой деградацией: если утилиты нет — сообщаем, но не падаем.
section() { echo; echo "--- $* ---"; }
unavailable() { echo "  (недоступно: не найдена утилита $1)"; }

show_config() {
    echo "Файл конфигурации: $CONFIG_FILE"
    if [ -f "$CONFIG_FILE" ]; then
        echo "Статус: загружен"
    else
        echo "Статус: не найден, используются значения по умолчанию"
    fi
    echo
    echo "LOG_LEVEL=$LOG_LEVEL"
    echo "DISK_USAGE_THRESHOLD=${DISK_USAGE_THRESHOLD:-85}"
    echo "MEMORY_USAGE_THRESHOLD=${MEMORY_USAGE_THRESHOLD:-90}"
}

main() {
    load_config

    case "${1:-}" in
        -h|--help)     usage; exit 0 ;;
        --show-config) show_config; exit 0 ;;
        --no-color)    ;;
        "")            ;;
        *)             echo "Неизвестный аргумент: $1" >&2; usage >&2; exit 1 ;;
    esac

    echo "=========================================="
    echo " Информация о системе"
    echo " Собрано: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=========================================="

    echo "Имя хоста:   $(hostname)"
    echo "ОС:          $(uname -s)"
    echo "Ядро:        $(uname -r)"
    echo "Архитектура: $(uname -m)"
    if has uptime; then
        echo "Аптайм:      $(uptime | sed 's/^ *//')"
    else
        echo "Аптайм:      (недоступно)"
    fi

    section "Процессор"
    # На ARM в /proc/cpuinfo нет поля "model name", поэтому несколько
    # источников по очереди. (Замечание №2 ревью.)
    if [ -r /proc/cpuinfo ] && grep -q "model name" /proc/cpuinfo 2>/dev/null; then
        echo "  Модель: $(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
    elif has lscpu; then
        echo "  Модель: $(lscpu | grep -m1 -E "Model name|Модель" | cut -d: -f2- | sed 's/^ *//')"
    elif has sysctl && sysctl -n machdep.cpu.brand_string >/dev/null 2>&1; then
        echo "  Модель: $(sysctl -n machdep.cpu.brand_string)"
    else
        echo "  Модель: (не определена)"
    fi
    if has nproc; then
        echo "  Ядер:   $(nproc)"
    elif has sysctl; then
        echo "  Ядер:   $(sysctl -n hw.ncpu 2>/dev/null || echo '(не определено)')"
    else
        echo "  Ядер:   (не определено)"
    fi

    section "Память"
    if has free; then
        free -h | sed 's/^/  /'
    elif has vm_stat; then
        vm_stat | head -5 | sed 's/^/  /'
    else
        unavailable "free"
    fi

    section "Дисковое пространство"
    if has df; then
        df -h 2>/dev/null | grep -v -E "tmpfs|devfs|map " | sed 's/^/  /'
    else
        unavailable "df"
    fi

    section "Сетевые интерфейсы"
    if has ip; then
        ip -4 addr show | grep -E "inet " | sed 's/^ */  /'
    elif has ifconfig; then
        ifconfig | grep -E "inet " | sed 's/^ */  /'
    else
        unavailable "ip/ifconfig"
    fi

    section "Последние входы в систему"
    # last требует чтения /var/log/wtmp: от обычного пользователя может не
    # хватить прав, поэтому ошибку глушим и сообщаем понятным текстом.
    # (Замечание №6 ревью.)
    if has last && last -n 5 >/dev/null 2>&1; then
        last -n 5 2>/dev/null | head -5 | sed 's/^/  /'
    else
        echo "  (недоступно: нет прав на чтение журнала входов)"
    fi

    echo
    echo "=========================================="
    return 0
}

main "$@"

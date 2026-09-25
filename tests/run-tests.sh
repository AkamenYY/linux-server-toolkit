#!/usr/bin/env bash
# Простой тестовый каркас без внешних зависимостей.
# Возвращает 0, если все проверки пройдены, иначе 1.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0

ok()   { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }

check() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

echo "=== Тесты linux-server-toolkit ==="
echo

echo "1. Синтаксис shell-скриптов"
for f in "$REPO_ROOT"/scripts/*.sh "$REPO_ROOT"/tests/*.sh; do
    [ -e "$f" ] || continue
    check "$(basename "$f") — синтаксически корректен" bash -n "$f"
done

echo
echo "2. Права на выполнение"
for f in "$REPO_ROOT"/scripts/*.sh; do
    [ -e "$f" ] || continue
    check "$(basename "$f") — исполняемый" test -x "$f"
done

echo
echo "3. Наличие shebang"
for f in "$REPO_ROOT"/scripts/*.sh; do
    [ -e "$f" ] || continue
    if head -1 "$f" | grep -q '^#!'; then
        ok "$(basename "$f") — есть shebang"
    else
        bad "$(basename "$f") — нет shebang"
    fi
done

echo
echo "4. Запуск sysinfo.sh"
if [ -x "$REPO_ROOT/scripts/sysinfo.sh" ]; then
    check "sysinfo.sh завершается с кодом 0" bash "$REPO_ROOT/scripts/sysinfo.sh"
fi

echo
echo "=================================="
echo "Пройдено: $PASS   Провалено: $FAIL"
echo "=================================="
[ "$FAIL" -eq 0 ]

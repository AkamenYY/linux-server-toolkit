#!/bin/bash
# sysinfo.sh - сводка о состоянии сервера

CONFIG=../config/toolkit.conf

echo "=========================================="
echo " Информация о системе"
echo "=========================================="

echo "Имя хоста:   $(hostname)"
echo "Ядро:        $(uname -r)"
echo "Архитектура: $(uname -m)"
echo "Аптайм:      $(uptime -p)"

echo ""
echo "--- Процессор ---"
grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2
echo "Ядер: $(nproc)"

echo ""
echo "--- Память ---"
free -h | grep Mem

echo ""
echo "--- Диски ---"
df -h | grep -v tmpfs

echo ""
echo "--- Сеть ---"
ip -4 addr | grep inet

echo ""
echo "--- Последние 5 входов в систему ---"
last -n 5

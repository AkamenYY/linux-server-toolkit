# Установка

Документ описывает установку `linux-server-toolkit` на целевой сервер.

## 1. Требования

| Компонент | Минимальная версия | Проверка |
|-----------|--------------------|----------|
| ОС        | Debian 11 / Ubuntu 20.04 / RHEL 8 | `cat /etc/os-release` |
| Bash      | 4.2                | `bash --version` |
| coreutils | 8.30               | `df --version` |
| tar       | 1.30               | `tar --version` |
| cron      | любая              | `systemctl status cron` |

Скрипты написаны на POSIX-совместимом Bash и не требуют внешних зависимостей
вроде Python или jq. Это осознанное решение: инструмент должен запускаться на
«голом» сервере сразу после установки ОС.

## 2. Установка

### 2.1. Клонирование

```bash
sudo git clone https://github.com/<USER>/linux-server-toolkit.git /opt/linux-server-toolkit
cd /opt/linux-server-toolkit
```

Каталог `/opt` выбран согласно FHS (Filesystem Hierarchy Standard) — это
штатное место для стороннего ПО, устанавливаемого не через пакетный менеджер.

### 2.2. Права доступа

```bash
sudo chown -R root:root /opt/linux-server-toolkit
sudo chmod 750 /opt/linux-server-toolkit/scripts/*.sh
```

Права `750` вместо `755`: скрипты работают с системными данными, и давать
право на запуск всем пользователям не нужно (принцип наименьших привилегий).

### 2.3. Конфигурация

```bash
sudo cp config/toolkit.conf.example config/toolkit.conf
sudo chmod 640 config/toolkit.conf
sudo nano config/toolkit.conf
```

Подробности параметров — в [CONFIGURATION.md](CONFIGURATION.md).

### 2.4. Проверка установки

```bash
./scripts/sysinfo.sh
```

Если скрипт вывел сводку по системе и завершился с кодом `0` — установка
выполнена корректно.

## 3. Добавление в PATH (необязательно)

```bash
echo 'export PATH="$PATH:/opt/linux-server-toolkit/scripts"' | sudo tee /etc/profile.d/toolkit.sh
source /etc/profile.d/toolkit.sh
```

## 4. Настройка расписания

Регулярные задачи ставятся в cron от имени root:

```bash
sudo crontab -e
```

```cron
# Проверка здоровья системы каждые 15 минут
*/15 * * * * /opt/linux-server-toolkit/scripts/healthcheck.sh >> /var/log/toolkit-health.log 2>&1

# Ежедневный бэкап в 03:30
30 3 * * * /opt/linux-server-toolkit/scripts/backup.sh >> /var/log/toolkit-backup.log 2>&1
```

## 5. Удаление

```bash
sudo crontab -l | grep -v linux-server-toolkit | sudo crontab -
sudo rm -rf /opt/linux-server-toolkit
sudo rm -f /etc/profile.d/toolkit.sh
```

Резервные копии, созданные инструментом, при удалении **не** затрагиваются —
их нужно удалять отдельно и осознанно.

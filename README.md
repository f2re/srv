# srv

Интерактивная подготовка Ubuntu VM и инструменты миграции серверной инфраструктуры на Proxmox.

Основной сценарий: создать VM вручную в Proxmox, установить **Ubuntu Server 22.04 или 24.04**, войти в неё и выполнить одну команду. Скрипт работает **внутри VM**; доступ к Proxmox API/CLI ему не нужен.

## Быстрый запуск

На свежей Ubuntu VM:

```bash
curl -fsSLo /tmp/srv-install.sh https://raw.githubusercontent.com/f2re/srv/main/install.sh \
  && sudo bash /tmp/srv-install.sh
```

Появится интерактивное меню выбора роли. Если роль уже известна:

```bash
curl -fsSLo /tmp/srv-install.sh https://raw.githubusercontent.com/f2re/srv/main/install.sh \
  && sudo bash /tmp/srv-install.sh --role gitlab
```

Примеры ролей:

```text
gitlab          GitLab CE/EE
gitlab-runner   GitLab Runner
web             сайт/API runtime
planka          PLANKA
telemetry       телеметрия
fileserver      Samba/NFS
nextcloud       Nextcloud
mailcow         Mailcow (тяжёлый)
mail-lite       Postfix + Dovecot + Rspamd
monitoring      Prometheus + Grafana + Alertmanager
edge            Nginx reverse proxy
vaultwarden     Vaultwarden
sftpgo          SFTPGo
```

Для небольшого Proxmox-хоста см. `docs/VM_SIZING.md`.

## Что делает базовая инициализация

Перед установкой выбранной роли мастер:

- проверяет Ubuntu и доступность сети/DNS;
- ждёт освобождения `apt/dpkg` locks;
- обновляет систему;
- устанавливает OpenSSH Server и QEMU Guest Agent;
- устанавливает и настраивает Fail2Ban для SSH;
- включает unattended security updates;
- устанавливает auditd/AppArmor и административные утилиты;
- предлагает добавить SSH public key;
- безопасно меняет SSH-порт с `sshd -t` и проверкой listening socket;
- запрещает root SSH login;
- отключает парольную SSH-аутентификацию только если у администратора уже есть рабочий `authorized_keys`;
- предлагает host UFW либо внешний firewall в зависимости от роли;
- устанавливает Fish и опционально Oh My Fish;
- сохраняет изменяемые конфиги перед правкой;
- пишет подробный журнал;
- после установки роли выполняет health-check.

Если шаг завершился ошибкой, интерактивный обработчик предлагает **повторить**, **показать журнал**, **открыть rescue shell** или **прервать**. Необязательные шаги можно пропустить. Критический шаг нельзя автоматически считать успешным после ошибки.

## После первого запуска

Репозиторий сохраняется на VM в:

```text
/opt/srv
```

Повторный мастер:

```bash
sudo /opt/srv/vm-init/vm-setup.sh
```

Проверка состояния:

```bash
sudo /opt/srv/vm-init/healthcheck.sh
sudo /opt/srv/vm-init/status.sh
```

Обновить комплект до актуального `main`:

```bash
sudo /opt/srv/update.sh
```

## Безопасность SSH

При смене SSH-порта мастер сначала записывает конфигурацию и выполняет `sshd -t`, затем перезапускает socket/service и проверяет, что новый порт действительно слушается.

**Не закрывайте текущую сессию**, пока из второго терминала не проверили:

```bash
ssh -p 2222 USER@IP
```

При проблеме используйте Console VM в Proxmox.

## Docker и firewall

Docker может публиковать контейнерные порты вне ожидаемой модели UFW. Поэтому Docker-роли рекомендуют фильтрацию на **Proxmox Firewall / VLAN / маршрутизаторе**. UFW не считается единственным сетевым периметром Docker VM.

## Почта

На слабом хосте используйте `mail-lite`; Mailcow требует значительно больше памяти. Ни один скрипт не может автоматически обеспечить доставляемость публичной почты без реальных DNS/IP-параметров. Перед переключением MX должны быть проверены PTR, inbound/outbound TCP/25, SPF, DKIM и DMARC.

## Миграция со старого VDS

Каталог `migration/` содержит отдельный двухпроходный migration-kit:

1. inventory/read-only обследование старого сервера;
2. предварительный export и перенос без остановки;
3. восстановление на изолированной целевой VM;
4. проверка;
5. финальный `cutover` с короткой остановкой записи;
6. повторная дельта данных и health-check.

Для GitLab и почты используются штатные backup/restore механизмы там, где это возможно. Для больших файловых каталогов предусмотрен staged `rsync` с сохранением UID/GID, ACL и xattr.

Начните с `migration/docs/RUNBOOK.md`.

## Структура репозитория

```text
srv/
├── install.sh              # bootstrap: скачать/обновить repo и запустить мастер
├── update.sh               # обновление /opt/srv
├── vm-init/                # provisioning внутри Ubuntu VM
│   ├── vm-setup.sh
│   ├── base.sh
│   ├── healthcheck.sh
│   ├── roles/
│   └── lib/
├── migration/              # перенос данных и конфигурации со старых VDS
├── docs/
└── scripts/verify.sh       # локальная статическая/Unit-проверка
```

## Проверка исходников

```bash
git clone https://github.com/f2re/srv.git
cd srv
./scripts/verify.sh
```

CI проверяет синтаксис shell-скриптов и unit-тесты migration-kit.

# Migration kit

Управляемый перенос сервисов со старых VDS/серверов на подготовленные VM.

Полная проверенная версия migration-kit 1.0.0 хранится в репозитории одним неизменяемым архивом:

```text
../archives/infrastructure-migration-kit-v1.0.0.tar.gz
SHA-256: 08323f6fa1c14cd04b3053cc352c2bff7caad9faf1ebf75c8337054869ce01be
```

Это сделано намеренно: архив является зафиксированным release-snapshot со своими `orchestrator.py`, `remote_agent.py`, тестами, inventory-примерами и документацией. Текущая папка содержит bootstrap/cleanup и почтовые вспомогательные инструменты, которые удобно запускать непосредственно из репозитория.

## Развернуть полный migration-kit

После `git clone`:

```bash
cd srv
sha256sum -c archives/SHA256SUMS
mkdir -p /opt/migration-kit
sudo tar -xzf archives/infrastructure-migration-kit-v1.0.0.tar.gz -C /opt/migration-kit
cd /opt/migration-kit
./check-controller.sh
```

Либо без клонирования всего репозитория:

```bash
curl -fL https://raw.githubusercontent.com/f2re/srv/main/archives/infrastructure-migration-kit-v1.0.0.tar.gz \
  -o /tmp/infrastructure-migration-kit-v1.0.0.tar.gz
printf '%s  %s\n' \
  '08323f6fa1c14cd04b3053cc352c2bff7caad9faf1ebf75c8337054869ce01be' \
  '/tmp/infrastructure-migration-kit-v1.0.0.tar.gz' | sha256sum -c -
mkdir -p ~/migration-kit
 tar -xzf /tmp/infrastructure-migration-kit-v1.0.0.tar.gz -C ~/migration-kit
```

## Принцип

```text
источник
   ↓ штатный backup / rsync
controller staging
   ↓ checksum + SSH
изолированная целевая VM
   ↓ restore
health-check
   ↓
ручное переключение DNS/NAT/MX
```

Оркестратор **не меняет DNS, MX, NAT и публичный reverse proxy автоматически**. Это отдельная контрольная точка после проверки цели.

Поддерживаются GitLab, GitLab Runner, сайт/systemd/Docker, PostgreSQL/MySQL, PLANKA, Nextcloud, файловые каталоги с ACL/xattr, телеметрия, Mailcow, PMG, monitoring и legacy Postfix/Dovecot.

Следующий документ: [`docs/RUNBOOK.md`](docs/RUNBOOK.md).

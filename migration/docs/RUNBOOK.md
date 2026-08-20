# Runbook миграции VDS → Proxmox VM

Этот runbook рассчитан на перенос без одновременной модернизации приложений. Сначала переносим рабочую систему на совместимые версии, проверяем, затем обновляем отдельно.

## 0. Правила

1. Не меняйте одновременно хостинг, ОС, БД и major-версию приложения.
2. Stateful source и target не должны одновременно принимать запись.
3. Перед первым production cutover должно быть выполнено тестовое восстановление.
4. VM backup не заменяет штатный backup БД/GitLab/Mailcow.
5. Старый VDS не удаляется сразу после переключения.

## 1. Подготовить целевые VM

На каждой свежей Ubuntu VM:

```bash
curl -fsSLo /tmp/srv-install.sh https://raw.githubusercontent.com/f2re/srv/main/install.sh
sudo bash /tmp/srv-install.sh --role ROLE
```

Для GitLab при миграции в мастере выберите установку точной версии старого GitLab.

## 2. Развернуть controller

```bash
git clone https://github.com/f2re/srv.git
cd srv
sha256sum -c archives/SHA256SUMS
mkdir -p ~/migration-kit
tar -xzf archives/infrastructure-migration-kit-v1.0.0.tar.gz -C ~/migration-kit
cd ~/migration-kit
./check-controller.sh
```

Создайте отдельный временный SSH-ключ:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/migration_ed25519 -C migration-controller
```

## 3. Подготовить source/target узлы

На каждом source и target скопируйте `bootstrap-node.sh` и public key, затем:

```bash
sudo ./bootstrap-node.sh \
  --authorized-key-file ./migration_ed25519.pub \
  --user migration
```

Этот ключ во время работ нужно считать привилегированным. После приёмки удалите временный доступ `cleanup-node.sh`.

## 4. Inventory

```bash
cp inventory.example.json inventory.json
chmod 600 inventory.json
nano inventory.json
```

Укажите реальные:

- source/target адреса;
- SSH port/key;
- systemd units;
- пути данных;
- БД;
- health URLs;
- каталоги object storage;
- большие каталоги в `staged_paths`.

Не храните пароли в inventory.

## 5. Read-only обследование

```bash
RUN=prod-$(date +%Y%m%d-%H%M)
./orchestrator.py --inventory inventory.json --run "$RUN" init-run
./orchestrator.py --inventory inventory.json bootstrap
./orchestrator.py --inventory inventory.json --run "$RUN" validate
./orchestrator.py --inventory inventory.json --run "$RUN" inspect
./orchestrator.py --inventory inventory.json --run "$RUN" plan
```

До переноса устраните несовпадение версий, нехватку места, отсутствующие утилиты и ошибочные пути.

## 6. Репетиция

Сначала менее критичный сервис, например PLANKA:

```bash
./orchestrator.py --inventory inventory.json --run "$RUN" \
  --service planka rehearse
```

Цель должна быть изолирована от production DNS/NAT/webhooks.

Проверить вручную:

- web UI;
- авторизацию;
- вложения;
- количество/размер данных;
- фоновые jobs;
- logs;
- restart VM.

## 7. Предварительная синхронизация больших файлов

`rehearse` может заранее передать `staged_paths`. Для файловых каталогов используется rsync с numeric UID/GID, ACL, xattr и sparse support. `delete_target_extra` оставляйте `false` до отдельного dry-run сравнения.

## 8. Финальный cutover

Перед началом убедитесь, что есть проверенный backup источника и понятный rollback.

```bash
./orchestrator.py --inventory inventory.json --run "$RUN" \
  --service SERVICE cutover
```

Оркестратор:

1. quiesce источника;
2. делает финальный application backup;
3. передаёт финальную дельту;
4. восстанавливает target;
5. запускает health-check;
6. при ошибке до внешнего переключения пытается возобновить source.

## 9. Внешнее переключение

Только после успешной проверки вручную меняются необходимые элементы:

- DNS A/AAAA/CNAME;
- NAT/HAProxy;
- MX/PMG transport;
- webhook URL;
- адреса collectors;
- SMTP relay;
- Runner URL.

После появления новых production-записей на target простое возвращение DNS на source уже не является безопасным rollback.

## 10. После переключения

В течение первых часов:

```bash
systemctl --failed
ss -lntup
df -h
journalctl -p err --since '-1 hour'
```

Проверить application-specific health и создать первый backup новой VM на NAS.

Старый VDS держите выключенным/read-only минимум 2–4 недели, если стоимость допускает.

## 11. Завершение

```bash
sudo ./cleanup-node.sh migration
```

Удалите migration SSH key, незашифрованные staging bundles после их архивирования и все временные firewall-исключения.

# IMAP migration helper

`mailbox_sync.py` выполняет повторяемую миграцию ящиков через `imapsync`.

Пароли не хранятся в CSV. Для каждого source и target mailbox указывается отдельный файл с правами `0600`.

## Подготовка

```bash
sudo apt install imapsync
cp mailboxes.example.csv mailboxes.csv
mkdir -m 700 /root/migration-secrets
printf '%s\n' 'OLD_PASSWORD' > /root/migration-secrets/user-old.pass
printf '%s\n' 'NEW_PASSWORD' > /root/migration-secrets/user-new.pass
chmod 600 /root/migration-secrets/*.pass
```

## Pilot dry-run

```bash
./mailbox_sync.py mailboxes.csv --mailbox user1@example.org
```

## Реальный sync

```bash
./mailbox_sync.py mailboxes.csv --apply
```

Команду можно повторять перед cutover: `imapsync` сверит существующие сообщения и перенесёт дельту.

См. также `../docs/MAIL_MIGRATION.md`.

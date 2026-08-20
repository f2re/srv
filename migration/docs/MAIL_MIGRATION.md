# Миграция почты

Почту переносите отдельно от сайта/GitLab: здесь важны очередь SMTP, DNS, PTR и недопущение параллельной записи в два хранилища.

## Вариант A — Mailcow → Mailcow

1. На новой VM установите совместимый Mailcow через `install.sh --role mailcow`.
2. На старой системе создайте штатный полный backup `backup_and_restore.sh backup all`.
3. Перенесите backup на target.
4. Выполните restore только на изолированной target VM.
5. Проверьте domains/mailboxes/aliases, IMAP, submission, DKIM и web UI.
6. Перед cutover заблокируйте новые SMTP/IMAP writes на source; PMG/внешний gateway должен держать входящую очередь.
7. Сделайте финальный backup/restore.
8. Переключите MX/PMG transport.

Не теряйте Mailcow crypt volume/keys: они входят в штатный полный backup и нужны для расшифровки данных.

## Вариант B — Postfix/Dovecot → тот же стек

Используйте `legacy_mail` из полного migration-kit. Сохраняются конфиги Postfix/Dovecot/Rspamd/OpenDKIM, TLS, user DB, Maildir и service units. На target должны совпадать UID/GID, схема виртуальных пользователей и пути Maildir.

## Вариант C — Postfix/Dovecot → Mailcow

Не копируйте произвольные старые SQL-таблицы или Maildir напрямую в внутреннюю структуру Mailcow.

Правильный процесс:

1. Заархивировать старый mail stack как rollback.
2. Составить CSV доменов, ящиков и aliases.
3. Создать пустые домены/ящики в Mailcow.
4. Для каждого source/target mailbox создать отдельные password files `0600`.
5. Сделать pilot sync одного ящика.
6. Сделать предварительный IMAP sync всех ящиков.
7. В cutover запретить запись в старую систему.
8. Повторить IMAP sync — он дотянет дельту.
9. Проверить папки/сообщения.
10. Переключить PMG/MX.

Пример запуска:

```bash
cd migration/mail-migration
./mailbox_sync.py mailboxes.csv --mailbox user@example.org
./mailbox_sync.py mailboxes.csv --apply
```

Скрипт передаёт пароли `imapsync` через `--passfile1/--passfile2`, а не через CSV или аргументы с явным паролем.

## Антиспам после миграции

Для небольшого локального хоста предпочтителен внешний SMTP gateway/PMG и внутренний mail server через WireGuard. Не включайте одновременно агрессивный greylisting/DNSBL на двух независимых уровнях без необходимости.

Минимум проверить до production:

- PTR = FQDN исходящего SMTP;
- A/AAAA и MX;
- SPF;
- DKIM;
- DMARC;
- inbound/outbound TCP 25;
- 465/587 submission;
- 993 IMAPS;
- TLS certificate;
- SMTP queue;
- отправку на Gmail/Outlook/Yandex/Mail.ru и обратный приём.

# Эксплуатация

## Обновление установочного комплекта

```bash
sudo /opt/srv/update.sh
```

После обновления существующий сервис автоматически не перенастраивается. Для повторного мастера:

```bash
sudo /opt/srv/vm-init/vm-setup.sh
```

## Проверка VM

```bash
sudo /opt/srv/vm-init/healthcheck.sh
sudo /opt/srv/vm-init/status.sh
```

Журнал provisioning:

```text
/var/log/infra-provision/provision.log
```

Резервные копии конфигурации, которые делает мастер перед изменениями:

```text
/var/backups/infra-provision/
```

## После смены SSH-порта

Не закрывайте существующую SSH/Proxmox Console сессию до проверки нового подключения во втором терминале.

## Docker

UFW не рассматривается как единственная защита Docker-портов. Ограничивайте доступ также Proxmox Firewall, VLAN или внешним маршрутизатором.

## Stateful-сервисы

GitLab, почта, Nextcloud и телеметрия должны иметь прикладные backup в дополнение к backup всей VM. Проверяйте восстановление, а не только факт создания архива.

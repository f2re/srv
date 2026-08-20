# Рекомендуемые VM для небольшого Proxmox-хоста

Ориентир для хоста класса Ryzen 5 5600H / 16 GiB RAM: не запускать все роли как отдельные VM одновременно.

| Роль | vCPU | RAM | Системный диск | Данные |
|---|---:|---:|---:|---|
| GitLab | 4 | 4 GiB | 60–80 GiB | отдельный диск/NAS для backup |
| GitLab Runner | 2 | 1.5–2 GiB | 40 GiB | включать по необходимости |
| Web + PLANKA | 2 | 2 GiB | 40 GiB | можно объединить на слабом хосте |
| Telemetry | 2 | 2 GiB | 30–40 GiB | большой ряд — отдельный диск/NAS |
| Fileserver | 1–2 | 1 GiB | 20 GiB | пользовательские файлы — NAS |
| Monitoring | 1 | 1 GiB | 20–40 GiB | короткая retention |
| Edge | 1 | 512 MiB–1 GiB | 10–20 GiB | — |
| Mail Lite | 2 | 2 GiB | 30 GiB | mail data отдельно |
| Mailcow | 4+ | 6+ GiB | 40 GiB | для 16 GiB хоста обычно не рекомендуется |

CPU в Proxmox можно overcommit. RAM — нет: оставляйте несколько GiB самому Proxmox и файловому кэшу.

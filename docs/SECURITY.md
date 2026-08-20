# Security model

## Scope

`srv` automates initial hardening and service provisioning of Ubuntu VMs. It is not a replacement for network segmentation, backups or application security updates.

## SSH

- root login is disabled;
- password login is disabled only after a valid `authorized_keys` exists;
- SSH config is validated with `sshd -t` before restart;
- the selected port is checked as listening after restart;
- Fail2Ban protects the actual SSH port;
- keep the Proxmox Console open until a second SSH login succeeds.

## Firewall

For non-Docker roles, host UFW is a reasonable additional layer. For Docker roles use Proxmox Firewall/VLAN/router ACLs as the primary perimeter because container port publication interacts directly with netfilter.

## Secrets

Generated application secrets are stored only in root-readable `.env`/secret files. Do not commit generated configs, migration inventories containing secrets, password files or staging bundles.

## Migration access

The temporary `migration` account is intentionally privileged enough to run the migration agent and rsync. Treat its key as root-equivalent for the duration of migration. Remove it with `migration/cleanup-node.sh` after acceptance.

## Data disks

The storage helper will not format a block device unless:

1. it is a real block device;
2. it is not mounted;
3. a parent disk containing partitions is not accidentally selected;
4. the destination mount point is empty;
5. the operator types the exact device path a second time.

## Updates

Base OS security updates are enabled automatically without automatic reboot. Stateful applications are updated separately; GitLab migration mode pins the exact package version until restore is complete.

## Mail

Do not expose a new mail server until PTR, MX, SPF, DKIM, DMARC, TLS and TCP/25 routing are verified. On small local deployments an external SMTP gateway is preferred.

## Backups

VM backup is not an application-consistent backup guarantee. Keep application backups for databases, GitLab, Mailcow/legacy mail and file data, and regularly test restore.

# Monitoring Stack: Project Brief for Claude

You are building a monitoring environment from scratch on this VM, for a network that is
separate from the operator's existing lab. The operator is a senior network engineer: be
terse, show commands and diffs, and skip beginner explanations.

## Goal
One Docker Compose stack on this VM that gives metrics, logs, dashboards and alerting for:
- VMware (vCenter / ESXi hosts, VMs, datastores, snapshots)
- Microsoft Active Directory (DCs, replication, DNS, DHCP, Kerberos/LDAP load)
- Windows servers and Linux hosts (physical and VMs)
- Ubiquiti UniFi network (gateway, switches, APs, clients) and UniFi Protect (NVR and cameras)
- Hyper-V hosts (including the host this monitoring VM runs on)
- Veeam Backup & Replication (job results, backup age, repository capacity)
- Unraid server (array/parity health, disks, SMART, Docker containers)

## Target environment (fill this in before the agent starts)
| Item | Value |
|---|---|
| This VM hostname / IP | monitor-grafana / 10.1.6.25 |
| Monitoring subnet(s) to discover | 10.1.6.0/24 (servers/infra); 10.1.40.0/24 (station 1 cameras); 10.2.40.0/24 (station 2 cameras) |
| vCenter FQDN (or standalone ESXi hosts) | vcenter.ttvfd.com (10.1.6.29) |
| Domain controllers | DC1 10.1.6.10, DC2 10.1.6.11 (domain ttvfd.com) |
| UniFi controller / console (UDM, Cloud Key, self-hosted) | 10.1.6.1 (console + gateway) |
| UniFi Protect NVR | station 1: 10.1.40.2; station 2: 10.2.40.3 |
| Hyper-V hosts (note which one runs this VM) | veeam 10.1.6.24 (runs this VM) |
| Veeam B&R server + version (12.x / 13, Windows or appliance) | veeam 10.1.6.24 (version TBD) |
| Veeam repositories (and whether any sit on Unraid) | |
| Unraid server + version | 10.1.6.22 (version TBD) |
| DNS servers / NTP | DNS 10.1.6.10, 10.1.6.11; NTP TBD |
| Alert destination (email / Slack / Teams / ntfy / Pushover) | ntfy.sh, private topic + access token |

## Stack
| Function | Component | Notes |
|---|---|---|
| Metrics TSDB | Prometheus | 30d local retention to start; leave room for VictoriaMetrics later if retention grows |
| Dashboards | Grafana | Datasources and dashboards provisioned from files in git, not clicked in |
| Alerting | Alertmanager | Routes to the destination above; one route per severity |
| Logs | Loki | Retention 14 to 30d |
| Log / agent collector | Grafana Alloy | Receives syslog (UniFi, ESXi) and ships Windows event logs and Linux journals to Loki. Do not use Promtail (deprecated) |
| VMware | Telegraf `inputs.vsphere` exposing `outputs.prometheus_client` | Preferred over pryorda/vmware_exporter (now looking for maintainers). Read-only vCenter account |
| Windows + AD | windows_exporter on each Windows host | Enable `ad`, `dns`, `dhcp`, `cpu`, `memory`, `logical_disk`, `net`, `os`, `service`, `system` collectors as appropriate per role |
| Hyper-V | windows_exporter with the `hyperv` collector on each host | Per-VM CPU/memory/vSwitch/storage metrics; also send the Hyper-V-VMMS and Hyper-V-Worker event logs to Loki |
| Veeam | Small custom exporter in this repo (Python) polling the VBR REST API on :9419 | Export per job: last result, last successful run timestamp, duration, transferred bytes; per repository: capacity and free space; license expiry. Also send the "Veeam Backup" Windows event log to Loki. If VBR is the v13 Linux appliance, check its built-in node exporter settings for host metrics |
| Unraid | Official node_exporter image as a Docker container (Community Apps template), plus smartctl_exporter | Avoid the older ich777 plugin thread (marked deprecated). Array/parity/disk state via a node_exporter textfile collector script that reads `/var/local/emhttp/*.ini`; cAdvisor for container metrics if wanted |
| Linux | node_exporter on each host | Install via a script or Ansible role kept in this repo |
| UniFi network | UnPoller (Prometheus output) | Read-only local controller account; import the UnPoller Grafana dashboards |
| UniFi Protect | A Protect exporter (evaluate options) plus blackbox ICMP on each camera | Validate the exporter against the current Protect version before relying on it |
| Network devices (fallback) | snmp_exporter | For anything UnPoller does not cover and any non-UniFi gear |
| Reachability | blackbox_exporter | ICMP for every device, HTTPS/cert expiry for web UIs, DNS probes against the DCs, TCP for LDAP/Kerberos |
| Status page (optional) | Uptime Kuma | Human-friendly up/down view |
| Reverse proxy | Caddy or Traefik | TLS in front of Grafana; nothing else exposed |

## Build phases (complete and verify each one before starting the next)
1. **Base**: Docker and Compose installed; repo layout created; Prometheus, Grafana, Alertmanager, Loki and Alloy up; Grafana provisioned with datasources; self-monitoring targets green.
2. **Discovery**: nmap sweep of the subnets above, read-only. Produce `inventory/hosts.yml` (IP, hostname, OS guess, role, open ports) and **show it to the operator for confirmation** before any targets are added.
3. **Linux + Windows**: exporter install scripts/Ansible for both; file-based service discovery (`targets/*.yml`) generated from the confirmed inventory.
4. **AD**: windows_exporter AD/DNS/DHCP collectors on DCs; Windows event logs (Security 4625/4740, Directory Service, DNS Server, System) to Loki via Alloy; blackbox DNS and LDAP probes.
5. **VMware**: Telegraf vSphere collector; dashboards for hosts, clusters, datastores, VMs and snapshot age; ESXi syslog to Alloy.
6. **UniFi**: UnPoller; UniFi syslog to Alloy; Protect exporter plus camera ICMP probes.
7. **Hyper-V, Veeam, Unraid**: hyperv collector on the Hyper-V hosts; the Veeam exporter (build it, test it against the API, then containerize it); node_exporter, smartctl_exporter and the array-state textfile script on Unraid.
8. **Alerting**: rules for host down, disk >85%, memory pressure, CPU saturation, AD replication failure, account lockout bursts, datastore >80%, snapshot older than 7d, AP/switch offline, camera offline, cert expiring <21d, scrape target down, Veeam job failed or warning, no successful backup for any job in >26h, Veeam repository >85%, Unraid array not started / parity invalid / disk disabled, SMART reallocated or pending sectors increasing, disk temp high, Hyper-V VM unexpectedly off. Also add a "watchdog" alert that always fires, so you know alerting itself is alive. Send a test alert end to end.
9. **Dashboards**: one overview "NOC" dashboard (red/green per domain) linking to per-domain drill-downs. Use community dashboards where good and adjust them; commit all JSON to git.
10. **Docs**: `README.md` covering how to add a host, rotate a credential, restore Grafana, and what each alert means.

## Repo conventions
- Everything is code: compose files, configs, provisioning, dashboards, alert rules, install scripts.
- Use `git init` and commit after each working step with a clear message.
- Secrets go in `.env` (in `.gitignore`) or Docker secrets, never in committed files. Provide `.env.example`.
- Pin image versions; no `latest` tags.
- Persistent data lives in named volumes or `/srv/monitoring/<service>`; document the backup path.
- Suggested layout:
  ```
  compose.yml  .env.example  README.md
  prometheus/ (prometheus.yml, rules/, targets/)
  alertmanager/  grafana/ (provisioning/, dashboards/)
  loki/  alloy/  telegraf/  unpoller/  blackbox/  snmp/
  inventory/  scripts/  ansible/
  ```

## Guardrails
- **Read-only against the monitored network.** Use only read-only service accounts (vCenter Read-Only role, a UniFi local "View Only" admin, an AD account in the Performance Monitor Users / Event Log Readers groups rather than Domain Admins, a Veeam account with the Veeam Backup Viewer role).
- **Never call any Veeam REST endpoint that starts, stops, edits or deletes anything.** The exporter uses GET requests only (plus the OAuth token request).
- **Unraid:** don't touch the array, shares or existing containers; only add the exporter containers.
- **This VM runs on Hyper-V and is backed up by Veeam.** Note in the README that if the Hyper-V host goes down, monitoring goes down with it, and suggest an external dead-man's-switch check (for example, a heartbeat to an outside service) for the watchdog alert.
- **Ask before** making any change on a device that isn't this VM: installing an agent, opening a firewall rule, changing a GPO, enabling SNMP or syslog on a device. Prepare the exact commands or steps and wait for a go-ahead.
- Discovery scans are limited to the subnets listed above, at a polite rate (no aggressive timing, no vuln scripts).
- If a credential is missing, stop and ask for it. Do not guess or try defaults.
- Prefer one working end-to-end path over many half-configured exporters.

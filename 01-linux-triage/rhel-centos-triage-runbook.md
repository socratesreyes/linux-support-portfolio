 # RHEL/CentOS Triage Runbook

First-pass triage notes for RHEL/CentOS servers in a client-support
environment. Written for support engineers who need to confirm a symptom,
narrow the cause, capture evidence, and either fix safely or escalate
with enough context that L3 can act without redoing the work.

Every scenario follows the same shape: symptoms, checks, how to read the
output, what to capture, and a client-safe update line.

All commands assume sudo where required. Read-only commands come first.
No restarts, config edits, or deletions without change approval.

---

## Environment assumptions

- RHEL 8/9 or CentOS Stream, systemd, firewalld, SELinux enforcing
- SSH access with sudo; changes flow through change control
- Logs via journald and `/var/log`
- Database is MySQL; application services run behind a reverse proxy
- Transport protocols in scope: SFTP, AS2, HTTPS

---

## Pre-Flight Diagnostics

When a ticket lands, do this before touching anything:

1. **Read the ticket twice.** Note the exact timestamp and the exact
   error text. Client wording is evidence.
2. **Determine scope.** Identify if the failure is isolated to a single client or widespread across multiple connections.
	- **Single Client:** - Focus on account permissions, localized IPs, and specific directory paths (`namei -l`).
	- **Multi-Client:** Immediately declare a **Major Incident**, notify stakeholders, and shift focus from user settings to global platform infrastructure (e.g., checking global daemon health, interface bindings, or storage limits). Prepare infrastructure logs before engaging L3.
    - CRITICAL SEVERITY HIGH IMPACT SERVICE.(special cases ) - AUTOMATIC escalation- if a core infastructure service is confirmed down entirely dropping a site. or   global `sshd` binding failure, total AS2 transport listener collapse) - escalate to l3/devops following specific KB instruction. 
-2. **Determine scope.** Identify if the failure is isolated to a single client or widespread across multiple connections.
	- **Single Client:** - Focus on account permissions, localized IPs, and specific directory paths (`namei -l`).
	- **Multi-Client:** Immediately declare a **Major Incident**, notify stakeholders, and shift focus from user settings to global platform infrastructure (e.g., checking global daemon health, interface bindings, or storage limits). Prepare infrastructure logs before engaging L3.
    - CRITICAL SEVERITY HIGH IMPACT SERVICE.(special cases ) - AUTOMATIC escalation- if a core infastructure service is confirmed down entirely dropping a site. or   global `sshd` binding failure, total AS2 transport listener collapse) - escalate to l3/devops following specific KB instruction. 

3. **Audit the Change Window** Recent deploy, patch, cert renewal, firewall
   rule, DNS change. 
	- **INTERNAL OPERATIONS** -audit intern **CHANGE REQUESTS** registry, maintenance calendars, and operational broadcast emails.  (recent deployments, network routing changes, firewall modifications or TLS certificate renewals.)
	-  EXTERNAL B2B Clients(black box) - in this business setup we dont have internal access to internal ticketing systems or infrastructure changes. engage client technical contact to confirm if they have changes. 
4. **Check the service state.** `systemctl status <svc>` first, always.
5. **Look at the log window.** Last 15 minutes around the reported time,
   not "last 24 hours of noise."
6. **Decide: fix or escalate.** If the fix needs a change approval, you
   escalate — you do not "just try" a restart on a client server.

The four questions that shape everything after:

- **Is the service running?** → `systemctl status`
- **Is it listening?** → `ss -tulpn`
- **Is it reachable?** → `nc -vz`, `curl -v`
- **Is the host healthy?** → `uptime`, `df -h`, `free -m`

---

## Escalation rules

Escalate to L3+/platform owner when:

- A production service stays down after one approved restart
- Disk is full and cleanup is not obviously safe
- You suspect data loss, corruption, or a security event
- The fix needs config, package, firewall, or SELinux change without approval
- Client impact is wider than the single reported symptom
- Logs point to application code rather than the environment

Capture evidence **before** escalating. Escalations without evidence
bounce back and cost the client time.

---

## Evidence capture standard

For every ticket, collect:

- **Timestamp window** (from ticket, not "now")
- **Exact error text** (copied, not paraphrased)
- **`systemctl status <svc>`** output
- **Last 50 log lines** for the affected service in the window
- **`ss -tulpn`** filtered to the relevant port
- **`df -h`** and **`free -m`** snapshot
- **What you tried** and the result, in order
- **Client-facing summary** in plain language

Paste this into the ticket notes. It becomes the hand off if you escalate
and the audit trail if the client asks later.

---

## Scenario 1 — Service down

**Symptoms**
- "SFTP login failing"
- "Files stuck in queue"
- "Portal unreachable"
- "AS2 receipts missing"

**Checks**

```bash
systemctl status <service> --no-pager
journalctl -u <service> --since "1 hour ago" --no-pager | tail -80
journalctl -p err -b --no-pager | tail -40
ss -tulpn | grep ':<port>'
```

For SFTP specifically:

```bash
systemctl status sshd --no-pager
journalctl -u sshd --since "1 hour ago" --no-pager | tail -80
ss -tulpn | grep ':22'
```

**Reading the output**

- `Active: inactive (dead)` → service stopped; check who and why before starting
- `Active: failed` → read the last 20 journal lines for the actual error
- `active (running)` but port not in `ss` → wrong bind address, wrong port, or app crashed internally
- Port listening but client still failing → move to Scenario 5 (network)
- Repeated `start` / `crash` loop → read `dmesg -T | tail -50` for kernel-level cause (OOM, disk, SELinux)

**Capture**
`systemctl status`, last 80 journal lines, `ss` for the port, whether
any restart was attempted and the result.

**Client-safe update**
> "We've confirmed the SFTP service is not accepting connections on the
> server. We're reviewing the service logs now and will update you within
> [timeframe] with either a fix or a clear next step."

---

## Scenario 2 — Disk full

**Symptoms**
- "No space left on device"
- Service crash-looping or failing to start
- Writes failing in the portal or transfer queue

**Checks**

```bash
df -h
df -i
du -sh /var/* 2>/dev/null | sort -h | tail -15
du -sh /var/log/* 2>/dev/null | sort -h | tail -15
lsof +L1 2>/dev/null | head -20
```

**Reading the output**

- `df -h` near 100% on `/` or `/var` → confirmed disk pressure
- `df -i` near 100% → inode exhaustion, usually from millions of small files (mail spools, session files, cache)
- Large directory in `du` → likely log growth, cache, backups, or core dumps
- `lsof +L1` showing large deleted files → space is held by a process still writing to a deleted file; the fix is a service restart with approval, not `rm`

**Safe cleanup (only with approval)**
- Rotate or truncate logs the team owns
- Clear `dnf clean all`, `/var/cache/dnf`
- Remove old core dumps in `/var/crash`
- Never delete active logs, database files, or anything you didn't create

**Capture**
`df -h`, `df -i`, top 10 directories by size, `lsof +L1` output.

**Client-safe update**
> "The server's filesystem is at [X]% and writes are failing. We've
> identified the largest consumers and are confirming with you before
> removing anything."

---

## Scenario 3 — High load / CPU

**Symptoms**
- Portal slow, timeouts on report generation
- Client reports "everything is lagging"

**Checks**

```bash
uptime
top -b -n1 | head -20
ps -eo pid,ppid,pcpu,pmem,etime,cmd --sort=-pcpu | head -15
vmstat 1 5
```

**Reading the output**

- Load average > core count sustained → real pressure, not a spike
- `top` shows one process at high `%CPU` → identify it; is it a backup, batch import, or unexpected?
- `vmstat` with high `wa` (iowait) → not CPU; it's disk I/O, pivot to Scenario 2 checks
- Multiple processes climbing together → likely a scheduled job or a runaway loop in the app

**Do not kill processes on a client server without approval.** Identify
the top consumers and their parent processes, capture evidence, escalate.

**Capture**
`uptime`, top 15 by CPU, `vmstat 1 5`, and the parent chain of the top
process (`ps -o pid,ppid,cmd -p <pid>`).

**Client-safe update**
> "The server is under elevated load from [process/pattern]. Response
> times are affected. We're confirming whether this is expected workload
> before taking action."

---

## Scenario 4 — Memory pressure

**Symptoms**
- Service restarts on its own
- OOM kills in logs
- Swap-heavy host, everything slow

**Checks**

```bash
free -m
top -b -n1 | head -20
journalctl -k --since "24 hours ago" | grep -iE 'oom|killed process'
```

**Reading the output**

- `free -m` with low available and high swap use → confirmed pressure
- `journalctl -k` showing `Out of memory: Killed process <pid> (<name>)` → the kernel acted; find that process
- One process growing steadily → likely a leak; capture memory over time, not a snapshot

**Capture**
`free -m`, OOM log lines with timestamps and process names, top 10 by
memory (`ps -eo pid,pcpu,pmem,cmd --sort=-pmem | head -10`).

**Client-safe update**
> "The server shows memory pressure and [service] was restarted by the
> OS. We're reviewing which process is consuming memory before
> recommending a fix."

---

## Scenario 5 — Port unreachable / network

**Symptoms**
- "Cannot reach SFTP port 22"
- "Portal returns timeout"
- "VPN tunnel drops"
- Transfers failing with connection errors

**Checks**

```bash
ss -tulpn | grep ':<port>'
firewall-cmd --list-all
getenforce
nc -vz <host> <port>
curl -v telnet://<host>:<port> --max-time 5
ping -c 4 <host>
traceroute -n <host>
dig +short <host>
```

**Reading the output**

- `ss` shows no listener → service problem, not network. Return to Scenario 1.
- `ss` shows listener, `nc` times out → firewall, routing, or upstream block
- `ss` shows listener, `nc` returns refused → service bound to `127.0.0.1` only
- `firewall-cmd` missing the port in the active zone → firewall rule gap
- `curl -v` shows TLS handshake failure → not a network issue; cert or protocol mismatch, escalate to app owner
- `dig` returns nothing or wrong IP → DNS, not the server
- `ping` succeeds but `nc` fails → ICMP allowed, port blocked; check firewall and upstream ACLs
- VPN drops → client-side issue; capture `ping`/`traceroute` from client to server and escalate to the network owner

**Capture**
`ss` for the port, `firewall-cmd --list-all`, `getenforce`, `nc -vz`
output, `curl -v` output, `ping`/`traceroute` summaries, `dig` result.

**Client-safe update**
> "We've confirmed whether the server is listening on the port and whether
> the firewall is allowing it. Next we're checking the path between your
> network and the server."

---

## Scenario 6 — Permission / sudo / SELinux

**Symptoms**
- "Permission denied" on a specific path
- A user can't run a command they used to run
- SFTP auth succeeds but transfer is rejected
- Service fails to start after a file was moved or restored

**Checks**

```bash
id <user>
ls -ld <path>
ls -l <path>
namei -l <path>
sudo -l -U <user>
getenforce
ausearch -m avc -ts recent 2>/dev/null | tail -20
```

**Reading the output**

- `id` missing an expected group → group membership gap
- `ls -ld` shows wrong owner or mode on a directory in the path → file permission issue
- `namei -l` traces every directory in the path; the first one that fails is the blocker — this is the fastest way to find "why can't the user write here"
- `sudo -l -U` shows the actual sudoers view for that user, not what someone thinks it is
- `getenforce` = Enforcing and `ausearch` shows `avc: denied` → SELinux is blocking; capture the AVC line before considering any fix
- SFTP-specific: home directory must not be group- or world-writable; `ls -ld /home/<user>` should show `drwx------` or ownership that matches

**Do not `setenforce 0`.** That is never the fix. Capture the AVC denial
and escalate to the platform owner with the exact context and target path.

**Capture**
`id`, `ls -ld` on the failing path, `namei -l` full output, `sudo -l -U`
output, any `avc: denied` lines with timestamps.

**Client-safe update**
> "We've identified which permission layer is blocking access. We're
> confirming the correct owner/group with you before making a change."

---

## Scenario 7 — Package / update drift

**Symptoms**
- A service fails to start after a patch window
- Install or upgrade command fails
- Version mismatch between servers

**Checks**

```bash
rpm -q <package>
dnf history | head -20
dnf check-update
journalctl -u <service> --since "24 hours ago" --no-pager | tail -50
```

**Reading the output**

- `rpm -q` shows a different version than expected → drift
- `dnf history` shows a recent transaction → suspect the change
- `dnf check-update` failing → repo unreachable or GPG key issue
- Service fails right after an update → config format change is common; check the service log for a config parse error

**Capture**
`rpm -q` output, last 5 `dnf history` entries with timestamps, service
log lines from after the update.

**Client-safe update**
> "The package state doesn't match the expected version. We're checking
> the update history and repo availability before recommending a
> rollback or reinstall."

---

## Scenario 8 — Time drift / clock

**Symptoms**
- Auth failures that "worked yesterday"
- TLS or certificate errors
- Partner rejects transfers with timestamp errors
- Log timestamps inconsistent across servers

**Checks**

```bash
timedatectl
date -u
chronyc tracking 2>/dev/null
```

**Reading the output**

- `timedatectl` shows `System clock synchronized: no` → NTP not working
- `chronyc tracking` shows large `System time` offset → drift in seconds or more
- Timezone wrong → not a sync problem; a config problem, and it affects log correlation across servers
- Drift > 5 minutes breaks Kerberos, many TLS handshakes, and most partner transfer protocols

**Capture**
`timedatectl`, `chronyc tracking`, `date -u`.

**Client-safe update**
> "The server clock is [X] seconds off from reference time, which can
> cause auth and certificate failures. We're checking NTP sync status
> before correcting it."

---

## Ticket-to-command map

Fast lookup for the tickets in this dataset.

| Ticket                    | First command                   | Second command              | Third command                |
| ------------------------- | ------------------------------- | --------------------------- | ---------------------------- |
| SFTP login failing        | `systemctl status sshd`         | `journalctl -u sshd`        | `ss -tulpn \| grep ':22'`    |
| Portal slow on reports    | `uptime`                        | `top -b -n1`                | `vmstat 1 5`                 |
| Files stuck in queue      | `systemctl status <transport>`  | `journalctl -u <transport>` | `df -h`                      |
| AS2 receipts missing      | `journalctl -u <transport>`     | `df -h`                     | `journalctl -p err -b`       |
| Cannot reach SFTP port 22 | `ss -tulpn \| grep ':22'`       | `firewall-cmd --list-all`   | `nc -vz <host> 22`           |
| VPN tunnel drops          | `ping`/`traceroute` from client | `nc -vz <host> <port>`      | escalate to network owner    |
| Password reset loop       | `id <user>`                     | `sudo -l -U <user>`         | `ausearch -m avc -ts recent` |
| Request: CSV export       | not a triage ticket             | route to enhancement        | document as feature request  |

---

## Related

- `commands-cheatsheet.md` — one-page lookup for the commands above
- `04-network-triage/network-triage-runbook.md` — deeper network path
- `05-tickets/` — scenarios applied to actual (simulated) tickets
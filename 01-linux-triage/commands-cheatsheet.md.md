### RHEL/CentOS Commands Cheatsheet

One-page lookup for triage under pressure. Grouped by intent, not by tool.  
Flags shown are the ones that matter; drop the rest. 

Replace `<svc>`, `<port>`, `<host>`, `<user>`, `<path>`, `<package>` as needed.  
Run read-only first. Anything that changes state needs approval. 

---

### Service state



```
systemctl status <svc> --no-pager          # is it running, since when, last exit
systemctl is-active <svc>                  # active | inactive | failed
systemctl is-enabled <svc>                 # will it start on boot
systemctl list-units --failed --no-pager   # anything failed right now
systemctl show <svc> -p MainPID,ExecStart  # what binary, what PID
systemctl cat <svc>                        # full unit file
systemctl list-dependencies <svc> --reverse # what depends on it
systemctl restart <svc>                    # APPROVAL ONLY
systemctl reload <svc>                     # prefer over restart if supported
```



**Rule:** `reload` before `restart`, `restart` before `stop`+`start`, and never on a client server without approval. 

---

### Logs



```
journalctl -u <svc> --since "15 min ago" --no-pager
journalctl -u <svc> --since "2026-10-27 01:00" --until "2026-10-27 02:00"
journalctl -u <svc> -p err -b --no-pager        # errors this boot only
journalctl -p err -b --no-pager | tail -40      # errors across all services
journalctl -k --since "24 hours ago"            # kernel messages (OOM, disk, NIC)
journalctl -f -u <svc>                          # live tail, Ctrl+C to stop
journalctl --disk-usage                         # is journald eating disk
```



**Time windows beat `-n 1000`.** Always bound to the ticket timestamp. 

---

### Listening ports and sockets


```
ss -tulpn                          # all TCP/UDP listeners with PID
ss -tulpn | grep ':<port>'         # is the port open at all
ss -tnp state established          # who is actually connected
ss -s                              # summary counts by state
```



`-t` TCP, `-u` UDP, `-l` listening, `-p` process, `-n` numeric (no DNS).  
If `ss` shows no listener, it's a service problem, not a network problem. 

---

### Disk and inodes



```
df -h                              # space per filesystem
df -i                              # inode usage (millions of tiny files)
du -sh /var/* 2>/dev/null | sort -h | tail -15
du -sh /var/log/* 2>/dev/null | sort -h | tail -15
lsof +L1 2>/dev/null | head -20    # deleted-but-open files holding space
find /var/log -type f -size +100M 2>/dev/null
```



**`df -h` full but `du` doesn't add up → `lsof +L1`.** That's the deleted-file-held-open case; the fix is a service restart with approval, not `rm`. 

---

### CPU and load


```
uptime                             # 1/5/15 min load vs core count
nproc                              # core count for comparison
top -b -n1 | head -20              # snapshot, not interactive
ps -eo pid,ppid,pcpu,pmem,etime,cmd --sort=-pcpu | head -15
vmstat 1 5                         # CPU, runqueue, iowait, swap over 5s
pidstat 1 3 2>/dev/null            # per-process CPU, if sysstat installed
```


**Load average > `nproc` sustained = real pressure.** High `wa` in `vmstat` means disk I/O, not CPU — pivot to disk checks. 

---

### Memory


```
free -m                            # available, not "free"
top -b -n1 | head -20
ps -eo pid,pcpu,pmem,rss,cmd --sort=-rss | head -10
journalctl -k --since "24 hours ago" | grep -iE 'oom|killed process'
```



Read **`available`**, not `free`. `free` low and `available` high is normal Linux caching. 

---

### Network path



```
ping -c 4 <host>                   # ICMP reachability
traceroute -n <host>               # path, numeric to skip DNS
mtr -rw -c 10 <host> 2>/dev/null   # combined ping+traceroute, if installed
nc -vz <host> <port>               # is the TCP port open end-to-end
curl -v telnet://<host>:<port> --max-time 5
curl -v https://<host>/health --max-time 10   # TLS + HTTP in one
dig +short <host>                  # DNS resolution
dig +short <host> A
dig +trace <host>                  # full resolution path, slow but decisive
```



**Fastest order:** `dig` → `ping` → `nc` → `curl -v`.  
Each one narrows the layer: DNS, ICMP, TCP, application. 

---

### Firewall


```
firewall-cmd --state
firewall-cmd --list-all            # active zone: services, ports, sources
firewall-cmd --list-ports
firewall-cmd --get-active-zones
firewall-cmd --query-port=<port>/tcp
iptables -L -n -v 2>/dev/null | head -40   # if firewalld not in use
```



Adding a rule is a change. Capture `--list-all` before and after. 

---

### Permissions and users



```
id <user>                          # uid, gid, all groups
groups <user>
ls -ld <path>                      # directory permissions
ls -l <path>
namei -l <path>                    # every component in the path, in order
sudo -l -U <user>                  # sudoers view for that user
getent passwd <user>
getent group <group>
last <user> | head -10             # recent logins
who                                # currently logged in
```



**`namei -l` is the fastest way to answer "why can't the user write here."** The first line that fails is the blocker. 

---

### SELinux


```
getenforce                         # Enforcing | Permissive | Disabled
sestatus
ausearch -m avc -ts recent 2>/dev/null | tail -20
ausearch -m avc -ts today 2>/dev/null | grep denied | tail -20
ls -Z <path>                       # SELinux context on a file
ps -eZ | grep <svc>                # SELinux context of the running process
```



**Never `setenforce 0`.** Capture the AVC denial and escalate. The context mismatch is the real finding. 

---

### Packages and updates


```
rpm -q <package>                   # installed version
rpm -qi <package>                  # full package info
rpm -ql <package> | head -20       # files owned by the package
dnf history | head -20             # recent transactions, newest first
dnf history info <id>              # what that transaction did
dnf check-update                   # available updates, repo reachable
dnf repoquery --installed <pkg>    # if you need a repo-aware view
```



After a patch, suspect config format change first. The service log will say so. 

---

### Time and clock



```
timedatectl                        # sync status, timezone, NTP service
date -u                            # UTC, useful when comparing to logs
chronyc tracking 2>/dev/null       # offset, stratum, drift
chronyc sources 2>/dev/null        # which NTP servers, reachable or not
```



**Drift > 5 minutes breaks auth, TLS, and partner transfers.** If `System clock synchronized: no`, that's the finding — don't chase the symptom. 

---

### Files and processes


```
ls -lah <path>
find <path> -type f -mmin -60      # files modified in last 60 min
find <path> -type f -size +500M    # large files
stat <path>                        # timestamps, inode, owner
lsof <path>                        # who has this file open
lsof -p <pid> | head -20           # what this process has open
ps -ef --forest | grep -A5 <svc>   # process tree around a service
pstree -p <pid>                    # children of a PID
```


---

### Archive and transfer (support glue)



```
tar -czf /tmp/<name>.tar.gz <path> # compress for evidence handoff
tar -tzf <file>.tar.gz | head      # verify before shipping
scp <file> user@host:/path         # copy evidence off the box
rsync -av --progress <src> <dst>   # resumable, good for large logs
sha256sum <file>                   # integrity, always ship with evidence
```



**Every evidence bundle ships with a `sha256sum`.** That's the audit trail. 

---

### The five commands you'll run most

In order, for almost every ticket: 


```
systemctl status <svc> --no-pager
journalctl -u <svc> --since "15 min ago" --no-pager
ss -tulpn | grep ':<port>'
df -h
free -m
```



If those five don't narrow it, the ticket goes to the runbook, not to more commands. 

---

### Related

- `rhel-centos-triage-runbook.md` — scenario flow using these commands 
- `04-network-triage/network-triage-runbook.md` — deeper network path

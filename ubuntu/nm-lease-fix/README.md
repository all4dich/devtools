# nm-lease-fix

Ansible playbook for the failure found on hwp-server-01 on 2026-10-16:
dbus-daemon segfaults during unattended-upgrades, NetworkManager exits
cleanly and is never restarted, the DHCP lease is not renewed, and ten days
later the kernel deletes the host's IP address while the host stays up.

Full write-up: https://claude.ai/code/artifact/72c6a568-5fd3-4183-850a-41bf05e92ac1
Session: claude --resume 9b42ccb2-3ec7-4a96-8cab-d8092ce64fea


## What it changes on each host

| Tag        | Change                                                                 | Default |
|------------|------------------------------------------------------------------------|---------|
| dropin     | `/etc/systemd/system/NetworkManager.service.d/10-restart-always.conf` with `Restart=always`, `RestartSec=5` | on |
| remediate  | starts dbus and NetworkManager if they are down, which renews the leases | on |
| dbus       | creates system group `power` if a dbus policy file references it      | on |
| dbus,never | reloads dbus to prove the crash is gone (`-e verify_dbus_reload=true`) | off |
| logind     | `HandlePowerKey=poweroff` (`-e logind_power_key_poweroff=true`)        | off |
| verify     | asserts NetworkManager active with Restart=always and every dynamic address has more than 80000 s left | on |

Hosts without `/usr/sbin/NetworkManager` are skipped.

On hwp-server-01 the policy file that references the missing group is
`/etc/dbus-1/system.d/org.freedesktop.thermald.conf`; the `dbus` tag creates
the group so the next dbus config reload has nothing to choke on.

## Run

Ansible is not installed on hwp-server-01. Run from a workstation that has it
(`pipx install ansible-core`) and SSH access to the hosts.

```bash
# dry run with diff
ansible-playbook -i inventory.ini playbook.yml -K --check --diff

# one urgent host first
ansible-playbook -i inventory.ini playbook.yml -K -l rebel-hw-test-11.rebellions.dev

# everything
ansible-playbook -i inventory.ini playbook.yml -K

# later: prove the dbus reload no longer kills anything (drop-in must be in place)
ansible-playbook -i inventory.ini playbook.yml -K -e verify_dbus_reload=true --tags dbus
```

`-K` asks for the sudo password. Set `ansible_user` in `inventory.ini` to the
account that can SSH in; the hosts other than hwp-agent-04 did not accept
sunjoo.park's key during the investigation.

## Expected output on a broken host

```
TASK [Show state before changes]
  "NetworkManager: inactive, dbus: active"
  "dynamic addresses (iface addr valid_lft): ['enxb0386ce018f8 192.168.15.74/24 162006']"
TASK [Install NetworkManager drop-in ...]            changed
TASK [Ensure NetworkManager is enabled and running]  changed
TASK [Show state after changes]
  ["ActiveState=active", "Restart=always", "Result=success"]
  "dynamic addresses (iface addr valid_lft): ['enxb0386ce018f8 192.168.15.74/24 863997']"
```

## Already isolated host

If the address has already expired, Ansible cannot reach the host. Log in on
the BMC console and run `sudo systemctl start NetworkManager`, then run this
playbook against it to install the drop-in.

## disable-unattended-upgrades.yml

Stops automatic package upgrades fleet-wide until the dbus reload crash is
fixed, because every upgrade morning re-runs the chain above on any host
where NetworkManager is still alive.

| Change | Detail |
|--------|--------|
| unattended-upgrades.service | stopped and disabled |
| apt-daily-upgrade.timer | stopped, disabled, masked |
| apt-daily.timer | untouched by default (`-e disable_apt_daily_download=true` masks it too) |
| /etc/apt/apt.conf.d/99-nm-lease-fix-no-unattended | `APT::Periodic::Unattended-Upgrade "0"`; 20auto-upgrades is left as is |

`inventory-all.ini` lists the 28 hosts scraped by Prometheus on 2026-10-16.
Hosts that are not Debian-based are skipped.

```bash
ansible-playbook -i inventory-all.ini disable-unattended-upgrades.yml -K --check --diff
ansible-playbook -i inventory-all.ini disable-unattended-upgrades.yml -K
ansible-playbook -i inventory-all.ini disable-unattended-upgrades.yml -K -e state=enabled   # revert
```

Security patches then have to be applied by hand (`apt update && apt
upgrade` in a window with a reboot). Re-enable once the thermald policy or
dbus is fixed and `systemctl reload dbus` is proven safe.

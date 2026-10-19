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
ansible-playbook -i inventory.ini restore-networkmanager.yml -K --check --diff

# one urgent host first
ansible-playbook -i inventory.ini restore-networkmanager.yml -K -l rebel-hw-test-11.rebellions.dev

# everything
ansible-playbook -i inventory.ini restore-networkmanager.yml -K

# later: prove the dbus reload no longer kills anything (drop-in must be in place)
ansible-playbook -i inventory.ini restore-networkmanager.yml -K -e verify_dbus_reload=true --tags dbus
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

## manage-ubuntu-auto-updates.yml (combined playbook)

Combines `disable_ubuntu_auto_updates.yml` and `disable-unattended-upgrades.yml`.
Requires Ubuntu with systemd and ansible-core 2.16+. Both original files remain
available, but use this playbook for subsequent policy changes.

| Option | Default | Behavior |
|--------|---------|----------|
| `state` | `disabled` | `disabled` blocks automatic updates; `enabled` applies an explicit enabled policy |
| `disable_apt_daily_download` | `true` | With updates disabled, also blocks package-list refreshes; `false` enables daily list refreshes while upgrades and package predownloads stay blocked |
| `disable_snap_auto_updates` | `true` | If Snap is installed, holds automatic refreshes indefinitely when disabled and removes the global hold when enabled; `false` leaves Snap untouched |
| `desktop_users` | `[]` | Disables selected users' update-notifier autostart; enabled mode removes matching managed overrides; changes take effect at next login |
| `stop_unattended_service` | `false` | Optional legacy behavior: stop/disable the unattended-upgrades shutdown helper when disabling updates |

```bash
# Preview; no target settings are changed
ansible-playbook -i inventory-all.ini manage-ubuntu-auto-updates.yml -K --check --diff

# Disable APT and Snap automation, including automatic security updates
ansible-playbook -i inventory-all.ini manage-ubuntu-auto-updates.yml -K

# Also suppress the selected desktop user's update notifier
ansible-playbook -i inventory.ini manage-ubuntu-auto-updates.yml -K \
  -e '{"desktop_users":["sunjoo.park"]}'

# Narrow APT-only policy: keep daily package-list refreshes; leave Snap untouched
ansible-playbook -i inventory-all.ini manage-ubuntu-auto-updates.yml -K \
  -e '{"disable_apt_daily_download":false,"disable_snap_auto_updates":false}'

# Re-enable updates and the same user's notifier
ansible-playbook -i inventory.ini manage-ubuntu-auto-updates.yml -K \
  -e '{"state":"enabled","desktop_users":["sunjoo.park"]}'
```

The combined playbook replaces the two original APT override files with
`/etc/apt/apt.conf.d/99-z-managed-auto-updates`. It manages both timers and
their underlying services, including unmasking the daily units when switching
`disable_apt_daily_download` from `true` to `false`. Running APT services are
allowed to finish. The shutdown helper is left alone by default when disabling
and enabled when present in enabled mode, including after use of the older
playbook. Errors managing installed units are not suppressed.

Enabled mode is a policy change, not a restore of the previous machine state:
it enables both APT timers and sets periodic processing, package-list refresh,
package predownload, and unattended upgrades to `1`. It removes this playbook's
automatic-reboot override, leaving the underlying reboot policy in effect.
Packages are never installed or removed, so enabled mode requires an existing
unattended-upgrades installation and suitable vendor upgrade configuration to
actually install upgrades. Desktop overrides use the standard `~/.config`
location; custom files are backed up before replacement, and enabled mode only
removes files matching the managed content. Restore any earlier custom content
from its backup if needed. Supply the same desktop users when re-enabling.

Snap capability checks happen before changes. Snap policy is reasserted every
run and deliberately reports changed. Setting `disable_snap_auto_updates=false`
does not remove an existing hold; use enabled mode with Snap management on.
The playbook reports APT policy and unit state before changes and verifies the
effective policy, masks, and timer state afterward. In check mode it reads actual
state and skips final assertions. It does not manage custom cron jobs or
third-party update agents. Apply security updates manually while automation is
disabled (`sudo apt update && sudo apt upgrade`; `sudo snap refresh`).

## disable-unattended-upgrades.yml (original)

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

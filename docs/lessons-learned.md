# Lessons learned

Things that broke while building this, how they were found, and what I'd do differently.

## The Pi kept asking a phone that wasn't there for DNS

**Symptom.** The phone could SSH to the laptop but not to the Pi. `netbird status -d` on the Pi showed the
phone as `Connecting` with no ICE candidates at all (`-/-`). Candidate exchange hadn't even started,
so the problem was signalling, not the network path. The website (Cloudflare Tunnel) still worked.

**Investigation.** Restarting NetBird on the Pi made things worse: the Pi dropped out of the mesh
completely. Reached it over the LAN instead (`ssh -o HostName=<pi>.local pi`; the Pi's MAC prefix
`b8:27:eb` also finds it in `ip neigh`). NetBird's own log (`/var/log/netbird/client.log`, not the journal)
said:

```
lookup api.netbird.io on 172.20.10.1:53: i/o timeout
```

`172.20.10.1` is an **iPhone hotspot's** gateway. The Pi had lived on my hotspot in the dorm before moving
home. NetworkManager knew the right DNS server (`nmcli dev show` → `192.168.1.1`), but
`/etc/resolv.conf` still pointed at the hotspot, and its mtime matched the exact second NetBird restarted.
NetBird backs up `resolv.conf` when it starts managing DNS and restores the backup when it stops. The backup
was weeks old.

**Fix.** `sudo nmcli general reload dns-rc` (rewrite resolv.conf from current state), then restart NetBird.

**Lesson.** Read the actual log before forming a theory. My first guess (a NetBird DNS chicken-and-egg
problem) was close but wrong; the log line pointed straight at the real cause.

## Don't restart the network you're standing on

I restarted NetBird on the Pi **over an SSH session that ran through NetBird**. The tunnel vanished
mid-command and the SSH client hung, waiting for an answer from a peer that no longer existed.
`Enter`, `~`, `.` (SSH's escape sequence, handled locally) kills such a session.

Rule: restart a VPN, firewall, sshd or network interface only over a *different* path (LAN, console), or
detach the command so it survives the disconnect.

## "P2P" doesn't mean "local"

Streaming on the same LAN still showed ~46 ms. `netbird status -d` explained why:

```
ICE candidate (Local/Remote): srflx/srflx
ICE candidate endpoints:      <mobile carrier IP>/<home public IP>
```

`srflx` (server-reflexive) means both sides were using their public addresses. The laptop was on phone
USB tethering, so the "direct" path went out over the mobile network and back in through the home router.
A real LAN path shows `host/host` with private addresses on both ends.

Related: USB tethering vs. the phone's Wi-Fi hotspot gave the same latency (the mobile network dominates)
but **a third of the jitter** (±3 ms vs ±9 ms), which matters more for streaming.

## Smaller ones

- **`sudo cmd > /root-owned/file` fails.** The redirection is done by *your* shell before sudo runs.
  Use `cmd | sudo tee file`.
- **Fedora generates SSH host keys on the first `sshd` start**, so `sshd -t` before that fails with
  "no hostkeys available". Start first, then test.
- **`journalctl -u` doesn't follow unit aliases.** `systemctl status sunshine` works,
  `journalctl -u sunshine` finds nothing; use the real unit name, or Sunshine's own log file.
- **SDDM hides sessions whose `TryExec` binary is missing.** `hyprland-uwsm.desktop` was installed, but
  `uwsm` itself wasn't, so the session didn't appear in the menu.
- **Wake on ping vs. wake on service.** Polling ping says "up" long before the desktop is ready. Poll the
  port of the thing you actually need.
- **Test the test.** A lock test picked "the first state directory" with `ls | head -1`; once another test
  created a second one, it passed or failed depending on hash order. Derive the path the same way the code
  does instead of guessing.

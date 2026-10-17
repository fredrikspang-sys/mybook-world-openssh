# mybook-world-openssh

A current, statically linked **OpenSSH 10.6p1** (with LibreSSL 4.3.3 and zlib 1.3.2) for the
**WD My Book World Edition II** ("white light") NAS. It includes a prebuilt tarball, the build script, the
compatibility shim for the old kernel, and install, init and rollback scripts.

Companion project: [mybook-world-zerotier](https://github.com/fredrikspang-sys/mybook-world-zerotier)
(ZeroTier One plus a `tun.ko` for the same NAS).

## Background

The My Book World Edition II firmware ships **OpenSSH 3.9p1 with OpenSSL 0.9.7e (2004)**. Modern
clients refuse to talk to it unless you re-enable long-deprecated algorithms:

```sh
ssh -oKexAlgorithms=+diffie-hellman-group1-sha1 -oHostKeyAlgorithms=+ssh-rsa \
    -oPubkeyAcceptedAlgorithms=+ssh-rsa -oCiphers=+aes128-cbc root@<NAS_IP>
```

This repo replaces it with a current OpenSSH. You get mlkem768x25519 / curve25519 key exchange,
ed25519/ecdsa/rsa-sha2 host keys, chacha20-poly1305, the SFTP-based `scp`, and no legacy options on
the client. The stock binaries and `/etc/sshd_config` are left in place as a fallback.

| File | What |
|------|------|
| `bin/openssh-10.6p1-armv5te-static.tar.gz` | `/usr/local/openssh` tree: `sbin/sshd`, `libexec/{sshd-session,sshd-auth,sftp-server}`, `bin/{ssh,scp,sftp,ssh-keygen,ssh-keyscan,ssh-add,ssh-agent}`, sample `etc/sshd_config`, `etc/moduli`, `etc/ssh_config`. **No host keys.** |
| `bin/SHA256SUMS` | Checksum of the tarball |
| `scripts/install.sh` | Installer, runs on the NAS. Default: test instance on port 2222. `--switch`: make it the main sshd. |
| `scripts/_SK50sshd` | Replacement `/etc/init.d/_SK50sshd`: new sshd with an automatic fallback to the stock one; GUI toggle compatible |
| `scripts/rollback.sh` | Back to the stock sshd (`--purge` also deletes `/usr/local/openssh`) |
| `scripts/build_openssh.sh` | Reproduces the tarball on an x86_64 Linux host (downloads and verifies the sources and the musl toolchain) |
| `src/compat_old_kernel.c` | `ppoll()` emulation and `getrandom()` fallback for Linux 2.6.24 |
| `patches/` | The one-line `configure` change, plus a description of every build flag that matters |
| `etc/sshd_config` | The sample config that goes into the tarball |

## Tested on

- WD My Book World Edition II, Oxsemi **OX810** (ARM926EJ-S, `armv5tejl`), 128 MB RAM
- WD firmware **01.02.14**, kernel `Linux 2.6.24.4 #1 Thu Apr 1 16:43:58 CST 2010 armv5tejl`, BusyBox 1.1.1, glibc 2.3.4
- Clients: OpenSSH 10.x on macOS (ssh, scp in SFTP and `-O` legacy mode, sftp, interactive pty)
- Tested with the release tarball and scripts from this repo, on a NAS that already had a
  `/usr/local/openssh` install:
  - `rollback.sh`: restores the original WD `_SK50sshd`, brings the stock 3.9p1 back on its old port with
    the lock file in place, and refuses unknown options;
  - `install.sh`: keeps the existing `sshd_config` and host keys, starts `sshd-test` on 2222, and
    `sshd-test` survives the stock script's `killall sshd`;
  - `install.sh --switch`, run from a session on 2222: new sshd on 22, nothing on 443, lock file present,
    same host keys (no known_hosts warning);
  - the web-GUI SSH toggle (off and on), and key login on port 22 afterwards.
- Tested earlier with a build from the same sources, flags and init-script logic. It differed only in
  the embedded build-directory strings.
  - A reboot: the new sshd came up on port 22 by itself after about 100 s.
  - GUI restart.
  - Login with an RSA user key, scp in SFTP and `-O` mode, sftp with md5-verified transfers, and an
    interactive pty.

  **Not tested:**
  - `rollback.sh --purge`. It deletes the live install, so it was only code-reviewed: it refuses to purge
    while nothing listens on the stock port and SSH is enabled in the GUI.
  - A first install on a NAS without any `/usr/local/openssh`, where `install.sh` itself generates the
    host keys. The same `ssh-keygen` commands were run by hand.

The binaries are fully static (musl), so they don't depend on the firmware's glibc. Other firmware
versions with the same CPU will probably work, but only 01.02.14 was tested.

## ⚠ Use at your own risk

This replaces the SSH daemon of an old, unsupported NAS that is probably your only shell access.
The scripts keep the stock sshd as a fallback, back up the init script, and test on a separate port
first. Nothing touches the firmware, flash, kernel or boot partitions. Still, **there is no warranty of
any kind**. If you lock yourself out, the web GUI keeps working, but without a shell you can't easily
undo it.

**Root login on the new sshd is key-only (`PermitRootLogin prohibit-password`).** Install your
public key in `/root/.ssh/authorized_keys` and test it on port 2222 **before** switching. `install.sh
--switch` refuses to run if that file is missing or empty.

## Quick install: test on port 2222 first

1. On your computer, verify the download and copy it to the NAS. Use your NAS's IP and its current
   SSH port: the WD default is 22, or whatever `/etc/sshd_config` says. The stock sshd needs the
   legacy options.

   ```sh
   sha256sum -c bin/SHA256SUMS
   OLD="-oKexAlgorithms=+diffie-hellman-group1-sha1 -oHostKeyAlgorithms=+ssh-rsa -oPubkeyAcceptedAlgorithms=+ssh-rsa -oCiphers=+aes128-cbc"
   tar cf - bin scripts | ssh $OLD root@<NAS_IP> 'mkdir -p /DataVolume/openssh-install && cd /DataVolume/openssh-install && tar xf -'
   ```

2. Install and start the test instance. This doesn't touch the stock sshd or any boot or GUI script.

   ```sh
   ssh $OLD root@<NAS_IP> 'sh /DataVolume/openssh-install/scripts/install.sh'
   ```

   `install.sh` does the following:
   - checks for root, `armv5tejl`, kernel 2.6.24, the WD `_SK50sshd`, and the `sshd` privsep user;
   - saves the original `/etc/init.d/_SK50sshd` as `_SK50sshd.wd-orig`, plus a timestamped `.bak-*`;
   - unpacks to `/usr/local/openssh`. Binaries are replaced; an existing `sshd_config` and host keys are kept;
   - generates ed25519, ecdsa and **rsa 3072** host keys if they are missing (RSA takes about 2 minutes);
   - runs `sshd -t`, then starts the test instance on **port 2222** (pidfile `/var/run/sshd-test.pid`).

3. Test from your computer **without** any legacy options:

   ```sh
   ssh -p 2222 root@<NAS_IP>
   scp -P 2222 somefile root@<NAS_IP>:/tmp/
   sftp -P 2222 root@<NAS_IP>
   ```

4. Switch over. Do this from a session **on port 2222**, so you stay connected whatever happens:

   ```sh
   ssh -p 2222 root@<NAS_IP> 'sh /DataVolume/openssh-install/scripts/install.sh --switch'
   ```

   `--switch` does the following:
   - checks `authorized_keys` and runs `sshd -t`;
   - installs `scripts/_SK50sshd` as `/etc/init.d/_SK50sshd`;
   - if SSH is enabled in the GUI, runs `S50sshd stop` and `S50sshd start`, detached and logged to
     `/var/log/openssh-switch.log`;
   - checks that the port from `sshd_config` (22) is listening, and puts the previous script back
     automatically if it isn't.

   Then test `ssh -p 22 root@<NAS_IP>` from your computer and stop the test instance with
   `kill $(cat /var/run/sshd-test.pid)`.

5. Remove the legacy options from your client config, and replace the old host key in
   `~/.ssh/known_hosts` (`ssh-keygen -R <NAS_IP>`). Compare the new fingerprint with
   `/usr/local/openssh/bin/ssh-keygen -l -f /usr/local/openssh/etc/ssh_host_ed25519_key.pub`.

To run on a different port, edit `Port` in `/usr/local/openssh/etc/sshd_config` before `--switch`.

## How the web GUI SSH toggle works, and why it keeps working

The firmware's GUI (`/proto/SxM_webui/admin/inc/wixSSH.class`, called from `system_advanced.php`) does
not configure sshd itself. It only works through two files:

| GUI action | What it runs |
|------------|--------------|
| Status | "on" if `/var/lock/sshd` exists |
| Enable / restart | `ln -sf _SK50sshd /etc/init.d/S50sshd`, then `/etc/init.d/S50sshd start` (or `restart`) |
| Disable | `rm -f /etc/init.d/S50sshd`, then `/etc/init.d/_SK50sshd stop` |

At boot, `/etc/init.d/rcS` runs every `/etc/init.d/S??*` with `start`, so the `S50sshd` symlink is the
persistent on/off switch. The GUI also stores `<ssh>yes</ssh>` in its config, and a factory reset
removes the symlink.

The new `_SK50sshd` keeps that interface exactly. The GUI code and the symlink are not touched.

- **start:** runs `sshd -t` on the new config. If that passes, it starts `/usr/local/openssh/sbin/sshd`.
  If the binary is missing or the config is broken, it falls back to the stock `/usr/sbin/sshd`. Either
  way it touches `/var/lock/sshd`.
- **stop:** kills the pid in `/var/run/sshd.pid`, then runs the original `killall sshd` (which catches
  the stock sshd too), then removes the lock file.

`killall sshd` matches the listener (process name `sshd`) but not the per-connection `sshd-session`
processes, so open sessions survive a GUI "disable". The test instance runs through a symlink named
`sshd-test`, so `killall sshd` leaves it alone.

## Workarounds for the old kernel, and what they mean for security

Linux 2.6.24 predates several syscalls that current OpenSSH and musl expect, and it has no seccomp.

1. **`ppoll()` emulation** (`src/compat_old_kernel.c`). The kernel has no `ppoll`/`pselect6`. OpenSSH
   uses `ppoll()` with a signal mask so that signals (SIGCHLD, SIGHUP, SIGTERM, SIGALRM...) can't be
   lost between checking a flag and sleeping.
   - The emulation keeps signals **blocked** and polls in slices of at most 250 ms.
   - After each slice it checks `sigpending()`. If a signal would be unblocked by the caller's mask, it
     briefly installs that mask so the handler runs, then returns `EINTR` like the real `ppoll`.
   - Cost: signal handling can be delayed by up to 250 ms, and a waiting process wakes up 4 times a
     second (negligible CPU).
   - It isn't a security boundary, but it is an emulation, not the kernel's atomic implementation.
2. **`getrandom()` fallback.** The kernel has no `getrandom`. OpenSSH takes its randomness from
   LibreSSL, whose `getentropy()` then reads `/dev/urandom`, as does the shim's `getrandom()`.
   - On 2.6.24, `/dev/urandom` never blocks, even if the entropy pool hasn't been seeded yet after boot.
   - The OX810 has no hardware RNG, and I did not check whether the firmware saves and restores a seed
     across reboots.
   - Host keys are generated long after boot (by `install.sh`), but sshd itself starts early in the boot
     sequence, so the very first connections after a reboot use randomness from a possibly weakly
     seeded pool.
3. **Weaker pre-authentication sandbox.** There's no seccomp, so the only usable sandbox is `rlimit`.
   - Normally it sets `RLIMIT_NOFILE=0`, but on Linux `poll()` then fails with `EINVAL` and every
     connection dies right after key exchange.
   - This build uses OpenSSH's own `SANDBOX_SKIP_RLIMIT_NOFILE`. The pre-auth process (`sshd-auth`) still
     runs as the unprivileged `sshd` user, chrooted to the empty `/var/empty`, with `RLIMIT_FSIZE=0` and
     `RLIMIT_NPROC=0`.
   - But it can open new file descriptors (for example sockets), and there is no syscall filtering.
   - This is clearly weaker than OpenSSH on a modern Linux with seccomp. It is still far better than a
     2004 OpenSSH with many known vulnerabilities.
4. **No PAM, no utmp/wtmp/lastlog** (musl has none). `who` and `last` don't show these sessions, and
   logins are logged via syslog (`auth.info`).
5. Every connection logs a harmless `sys_get_rdomain: cannot determine VRF ... Protocol not available`,
   because the kernel predates that socket option.
6. LibreSSL is built with `--disable-asm` (its ARM assembly needs ARMv7), so all crypto is plain C.

Not tested: password login for non-root users (musl `crypt()` against the firmware's password hashes),
`ssh-agent` forwarding, X11 forwarding, and port forwarding. The NAS has no `sha256sum`, so verify
`bin/SHA256SUMS` on your computer before copying.

## Performance and resource use (OX810 @ stock clock)

| | |
|---|---|
| Login time (key auth, mlkem768x25519) | 0.55–1.1 s (stock 3.9p1: about 0.4 s) |
| scp upload, chacha20-poly1305 (default) | **about 1.4 MB/s** |
| scp upload, aes128-gcm / aes128-ctr | about 0.9 MB/s |
| Stock 3.9p1 sshd for comparison | about 1.3 MB/s |
| RSA 3072 host key generation | about 2 minutes |
| RAM: listening sshd | 668 kB RSS (stock: 964 kB) |
| RAM: per logged-in session | about 2.2 MB RSS (`sshd-session` postauth plus user process) |
| Disk: `/usr/local/openssh` | about 16 MB on the root filesystem |

The CPU is the bottleneck: there's no crypto acceleration and no NEON. For bulk transfers on the LAN,
use the NAS's SMB or NFS shares. SSH is fine for shells, configuration and small files.

| Binary (stripped, static) | Size |
|---|---|
| `sbin/sshd` | 1.6 MB |
| `libexec/sshd-session` | 2.0 MB |
| `libexec/sshd-auth` | 2.0 MB |
| `libexec/sftp-server` | 214 kB |
| `bin/ssh` | 1.9 MB |
| `bin/ssh-keygen` | 1.6 MB |
| `bin/scp`, `bin/sftp` | 288 kB, 276 kB |

## Rollback

```sh
sh /DataVolume/openssh-install/scripts/rollback.sh          # stock sshd back on its old port
sh /DataVolume/openssh-install/scripts/rollback.sh --purge  # ... and delete /usr/local/openssh
```

Or by hand:

```sh
cp /etc/init.d/_SK50sshd.wd-orig /etc/init.d/_SK50sshd
kill $(cat /var/run/sshd.pid)
/etc/init.d/S50sshd start
```

Afterwards your clients need the legacy options and the old host key again.

## Building from source

On any x86_64 Linux host, without root:

```sh
WORKDIR=$PWD/work scripts/build_openssh.sh
# optional: TOOLCHAIN=/path/to/armv5l-linux-musleabi-cross   JOBS=8
```

The script does the following:
- downloads the musl.cc `armv5l-linux-musleabi-cross` toolchain (GCC 11.2.1, musl 1.2.2) and the
  OpenSSH, LibreSSL and zlib release tarballs, and checks their pinned SHA-256 sums;
- builds with `-march=armv5te -mfloat-abi=soft -marm`, clearing any host `CFLAGS`/`LDFLAGS`;
- checks that every binary is static and ARMv5TE and that no build path leaked in;
- writes `work/openssh-10.6p1-armv5te-static.tar.gz`.

See `patches/README.md` for every change and why it is needed.

## License

Scripts, shim, config and docs: MIT (`LICENSE`). The binaries contain OpenSSH, LibreSSL, zlib, musl
and libgcc under their own licenses. See `LICENSES.md` and `licenses/`.

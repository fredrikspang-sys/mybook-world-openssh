# Source changes

All changes are applied automatically by `scripts/build_openssh.sh`. Nothing in the OpenSSH,
LibreSSL or zlib C sources is modified.

| Change | Where | Why |
|--------|-------|-----|
| `src/compat_old_kernel.c` linked before libc (`LIBS=compat_old_kernel.o`) | OpenSSH link | Linux 2.6.24 on ARM has no `ppoll`/`pselect6` and no `getrandom` syscall. musl does not emulate them. The object provides `ppoll()` (musl's time64 symbol `__ppoll_time64`) on top of `poll()`, and a `getrandom()` with a `/dev/urandom` fallback. |
| `openssh-10.6p1-configure-rlimit-cross.patch` | OpenSSH `configure` | When cross-compiling, configure cannot run its "select/poll works with descriptor rlimit" test, assumes "no" and refuses `--with-sandbox=rlimit`. The patch flips that one cross-compile default. (The build script applies it with a small `awk` edit, which is equivalent.) |
| `-DSANDBOX_SKIP_RLIMIT_NOFILE` in CFLAGS | OpenSSH `sandbox-rlimit.c` | Linux `poll()`/`ppoll()` return `EINVAL` when `nfds > RLIMIT_NOFILE`. With the default `RLIMIT_NOFILE=0` every connection died right after `SSH2_MSG_KEXINIT` ("ssh_dispatch_run_fatal: ... Invalid argument [preauth]"). This existing OpenSSH switch (also used on some other platforms) leaves the open-file limit alone; `RLIMIT_FSIZE=0` and `RLIMIT_NPROC=0` are still applied. |
| `ac_cv_func_getentropy=no` | LibreSSL configure | Use LibreSSL's own `getentropy_linux.c` (tries `getrandom`, falls back to `/dev/urandom`) instead of musl's `getentropy()`, which only calls the missing syscall. |
| `--disable-asm` | LibreSSL configure | The ARM assembly needs ARMv7 or newer. |
| `-static -no-pie`, `-fno-pie` | OpenSSH link | musl.cc GCC defaults to static-PIE; plain static binaries are simpler and safer on this old kernel. |
| `--with-sandbox=rlimit`, `--without-pam`, `--disable-utmp/wtmp/lastlog` | OpenSSH configure | No seccomp on 2.6.24; no PAM on the NAS; musl has no utmp/wtmp. |
| `-ffile-prefix-map`, `--with-openssldir=/usr/local/openssh/etc/ssl` | all | Keep build-host paths out of the binaries. |

#!/bin/bash
# build_openssh.sh - static OpenSSH + LibreSSL + zlib for the WD My Book World Edition II
# (Oxsemi OX810, ARM926EJ-S = ARMv5TE, soft-float EABI, Linux 2.6.24.4), using a musl cross toolchain.
#
# Runs on an x86_64 Linux host. No root needed. Output: $WORKDIR/openssh-$OPENSSH_VER-armv5te-static.tar.gz
#
# Environment overrides:
#   WORKDIR    build directory                  (default: ./work)
#   TOOLCHAIN  existing musl cross toolchain dir (default: download $TOOLCHAIN_URL into $WORKDIR)
#   JOBS       parallel make jobs               (default: nproc)
set -euo pipefail
unset CFLAGS CXXFLAGS LDFLAGS CPPFLAGS LIBS   # host flags (e.g. -march=native, --as-needed) must not leak in

OPENSSH_VER=10.6p1
OPENSSH_URL=https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-$OPENSSH_VER.tar.gz
OPENSSH_SHA256=a9dc9565dffe8640f64d863cd29a32bc4a3dbdec0566a7fc44c5d6ee767d5f39
LIBRESSL_VER=4.3.3
LIBRESSL_URL=https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/libressl-$LIBRESSL_VER.tar.gz
LIBRESSL_SHA256=ff97c432457f349e6ba3d416ab903bc7468f1436f0f32efe5fff808de292c7b8
ZLIB_VER=1.3.2
ZLIB_URL=https://zlib.net/zlib-$ZLIB_VER.tar.gz
ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16
TOOLCHAIN_URL=https://musl.cc/armv5l-linux-musleabi-cross.tgz   # GCC 11.2.1, musl 1.2.x
TOOLCHAIN_SHA256=c17a278b6824f642083e6e499cd2a5a432cb0a4c662092b62e5bd716e1fa329b

PREFIX=/usr/local/openssh            # install prefix on the NAS (root fs, available before /DataVolume)
T=armv5l-linux-musleabi
ARCHF="-march=armv5te -mtune=arm926ej-s -mfloat-abi=soft -marm"

HERE=$(cd "$(dirname "$0")/.." && pwd)        # repo root (needs src/compat_old_kernel.c)
W=$(mkdir -p "${WORKDIR:-$PWD/work}" && cd "${WORKDIR:-$PWD/work}" && pwd)
SYS=$W/sysroot
JOBS=${JOBS:-$(nproc)}
# keep the build directory out of the binaries (__FILE__, debug info)
MAPF="-ffile-prefix-map=$W=/build -fdebug-prefix-map=$W=/build -ffile-prefix-map=$HERE=/src"

fetch() { # url sha256
	local f=$W/dl/$(basename "$1")
	mkdir -p "$W/dl"
	[ -f "$f" ] || curl -fL --retry 3 -o "$f" "$1"
	echo "$2  $f" | sha256sum -c - >/dev/null || { echo "CHECKSUM MISMATCH: $f" >&2; exit 1; }
	echo "$f"
}

echo '### toolchain'
if [ -z "${TOOLCHAIN:-}" ]; then
	TOOLCHAIN=$W/$T-cross
	[ -x "$TOOLCHAIN/bin/$T-gcc" ] || tar -C "$W" -xzf "$(fetch $TOOLCHAIN_URL $TOOLCHAIN_SHA256)"
fi
export PATH=$TOOLCHAIN/bin:$PATH
export CC=$T-gcc AR=$T-ar RANLIB=$T-ranlib STRIP=$T-strip
$CC --version | head -1

echo '### sources (sha256-verified)'
for s in "$OPENSSH_URL $OPENSSH_SHA256" "$LIBRESSL_URL $LIBRESSL_SHA256" "$ZLIB_URL $ZLIB_SHA256"; do
	set -- $s; f=$(fetch "$1" "$2"); d=$W/$(basename "$f" .tar.gz)
	rm -rf "$d"; tar -C "$W" -xzf "$f"; echo "  $(basename "$d")"
done
mkdir -p "$SYS"

echo '### compat shim for Linux 2.6.24 (ppoll, getrandom)'
$CC $ARCHF $MAPF -O2 -c -o "$SYS/compat_old_kernel.o" "$HERE/src/compat_old_kernel.c"

echo "### zlib $ZLIB_VER (static)"
cd "$W/zlib-$ZLIB_VER"
CFLAGS="$ARCHF $MAPF -O2" CHOST=$T ./configure --static --prefix="$SYS" >/dev/null
make -j"$JOBS" >/dev/null && make install >/dev/null

echo "### LibreSSL $LIBRESSL_VER (static libcrypto, no asm; getentropy via /dev/urandom fallback)"
cd "$W/libressl-$LIBRESSL_VER"
ac_cv_func_getentropy=no ./configure --host=$T --prefix="$SYS" --with-openssldir=$PREFIX/etc/ssl \
	--disable-shared --enable-static --disable-asm --disable-tests CFLAGS="$ARCHF $MAPF -O2" >/dev/null
make -j"$JOBS" -C crypto >/dev/null && make -C crypto install >/dev/null && make -C include install >/dev/null

echo "### OpenSSH $OPENSSH_VER (static, non-PIE, rlimit sandbox without RLIMIT_NOFILE)"
cd "$W/openssh-$OPENSSH_VER"
# When cross-compiling, configure cannot run its "select/poll works with rlimit" test and refuses the
# rlimit sandbox. Flip that one cross-compile default (see patches/openssh-configure-rlimit-cross.patch) ...
cp configure configure.orig
awk '/cross compiling: assuming no/ {c=1} c==1 && /select_works_with_rlimit=no/ {sub(/=no/,"=yes"); c=2} {print}' \
	configure.orig > configure
# ... but build with -DSANDBOX_SKIP_RLIMIT_NOFILE: Linux poll()/ppoll() return EINVAL when nfds exceeds
# RLIMIT_NOFILE, so RLIMIT_NOFILE=0 would kill every connection right after KEXINIT.
./configure --host=$T --prefix=$PREFIX --sysconfdir=$PREFIX/etc \
	--with-privsep-path=/var/empty --with-privsep-user=sshd --with-pid-dir=/var/run \
	--with-ssl-dir="$SYS" --with-zlib="$SYS" --with-sandbox=rlimit \
	--without-pam --without-selinux --without-kerberos5 \
	--without-security-key-builtin --disable-security-key \
	--disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx --disable-lastlog \
	--with-default-path=/usr/bin:/bin:/usr/sbin:/sbin \
	--without-hardening --without-stackprotect \
	CFLAGS="$ARCHF $MAPF -O2 -fno-pie -DSANDBOX_SKIP_RLIMIT_NOFILE" LDFLAGS="-static -no-pie" \
	LIBS="$SYS/compat_old_kernel.o" > "$W/openssh-configure.log"
grep -E 'sandbox style|Random number' "$W/openssh-configure.log"
make -j"$JOBS" > "$W/openssh-make.log" 2>&1 || { tail -40 "$W/openssh-make.log"; exit 1; }

echo '### stage + strip + package'
ST=$W/stage; rm -rf "$ST"
make install-nokeys STRIP_OPT= DESTDIR="$ST" >/dev/null
P=$ST$PREFIX
rm -rf "$ST/usr/local/openssh/share" "$P/libexec/ssh-keysign" "$P/libexec/ssh-pkcs11-helper" "$P/libexec/ssh-sk-helper"
rm -f "$P/etc/sshd_config" "$P/etc/ssh_host_"*
cp "$HERE/etc/sshd_config" "$P/etc/sshd_config"
for f in "$P"/bin/* "$P"/sbin/* "$P"/libexec/*; do $STRIP "$f"; done
for f in sbin/sshd libexec/sshd-session libexec/sshd-auth libexec/sftp-server bin/ssh bin/scp bin/sftp bin/ssh-keygen; do
	$T-readelf -l "$P/$f" | grep -qi interp && { echo "NOT STATIC: $f"; exit 1; }
	$T-readelf -A "$P/$f" | grep -q 'Tag_CPU_arch: v5TE' || { echo "NOT ARMv5TE: $f"; exit 1; }
done
if grep -l "$W" "$P"/bin/* "$P"/sbin/* "$P"/libexec/*; then echo "build path leaked into binaries" >&2; exit 1; fi
OUT=$W/openssh-$OPENSSH_VER-armv5te-static.tar.gz
tar -C "$ST/usr/local" --owner=0 --group=0 --numeric-owner --sort=name --mtime='2026-10-17 00:00:00 UTC' -cf - openssh | gzip -n9 > "$OUT"
ls -l "$OUT"; sha256sum "$OUT"
echo BUILD_OK

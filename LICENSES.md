# Licenses

The scripts, `src/compat_old_kernel.c`, `etc/sshd_config`, the patches and the documentation in this
repository are under the MIT license (`LICENSE`).

The binaries in `bin/openssh-10.6p1-armv5te-static.tar.gz` are statically linked from the following
third-party components. Their license texts are in `licenses/`.

| Component | Version | Source | License | File |
|-----------|---------|--------|---------|------|
| OpenSSH portable | 10.6p1 | https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.6p1.tar.gz | BSD-style; various permissive licences per component, see the file | `licenses/OpenSSH-LICENCE.txt` (the `LICENCE` file from the tarball) |
| LibreSSL (libcrypto only) | 4.3.3 | https://cdn.openbsd.org/pub/OpenBSD/LibreSSL/libressl-4.3.3.tar.gz | Original OpenSSL and SSLeay licenses for inherited code; ISC (and some BSD/public domain) for new code | `licenses/LibreSSL-COPYING.txt` (the `COPYING` file from the tarball) |
| zlib | 1.3.2 | https://zlib.net/zlib-1.3.2.tar.gz | zlib license | `licenses/zlib-LICENSE.txt` |
| musl libc | 1.2.2 (git snapshot in the musl.cc toolchain) | https://musl.libc.org/ , toolchain https://musl.cc/armv5l-linux-musleabi-cross.tgz | MIT | `licenses/musl-COPYRIGHT.txt` |
| libgcc (compiler runtime) | GCC 11.2.1 (musl.cc toolchain) | https://gcc.gnu.org/ | GPL-3.0 with the GCC Runtime Library Exception 3.1, which allows linking it into programs under any license | `licenses/GPL-3.0.txt`, `licenses/GCC-RUNTIME-LIBRARY-EXCEPTION-3.1.txt` |

The SHA-256 checksums of the source tarballs are in `scripts/build_openssh.sh`. The exact build
procedure, including all changes (`patches/README.md`), is `scripts/build_openssh.sh`.

The LibreSSL inherited-code license (OpenSSL/SSLeay) requires that redistributions in binary form
reproduce the copyright notices and acknowledgements: this file and `licenses/LibreSSL-COPYING.txt`
serve that purpose. "This product includes cryptographic software written by Eric Young
(eay@cryptsoft.com)" and "This product includes software developed by the OpenSSL Project for use
in the OpenSSL Toolkit (http://www.openssl.org/)".

OpenSSH, OpenBSD and LibreSSL are projects of the OpenBSD developers. This repository is not
affiliated with or endorsed by them or by Western Digital.

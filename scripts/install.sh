#!/bin/sh
# install.sh - install static OpenSSH on a WD My Book World Edition II (run ON the NAS as root).
#
#   sh scripts/install.sh            install to /usr/local/openssh and start a TEST sshd on port 2222
#                                    (the stock sshd and the boot/GUI scripts are not touched)
#   sh scripts/install.sh --switch   make it the main sshd: install the new /etc/init.d/_SK50sshd
#                                    and restart through /etc/init.d/S50sshd (only if SSH is enabled
#                                    in the web GUI). Rolls back automatically if port 22 does not come up.
#
# Written for the firmware's BusyBox 1.1.1 /bin/sh (no tr, wc, sort, strings, grep -o).
# Uninstall / rollback: sh scripts/rollback.sh
PREFIX=/usr/local/openssh
CONF=$PREFIX/etc/sshd_config
INITD=/etc/init.d
TEST_PORT=${TEST_PORT:-2222}
TEST_PID=/var/run/sshd-test.pid
MARK=/usr/local/openssh/sbin/sshd
case $0 in */*) D=${0%/*} ;; *) D=. ;; esac   # no dirname/basename in BusyBox 1.1.1
HERE=`cd $D/.. && pwd`
TARBALL=`ls $HERE/bin/openssh-*-armv5te-static.tar.gz 2>/dev/null | tail -n 1`
TS=`date +%Y%m%d-%H%M%S`

die() { echo "ERROR: $*" >&2; exit 1; }
say() { echo "==> $*"; }

MODE=test
case "$1" in
  "") ;;
  --switch) MODE=switch ;;
  -h|--help) sed -n '2,12p' $0; exit 0 ;;
  *) die "unknown option $1 (use --switch or nothing)" ;;
esac

# ---- platform checks ----
[ "`id -u`" = 0 ] || die "run as root"
[ "`uname -m`" = armv5tejl ] || die "this is for the OX810 (armv5tejl), found `uname -m`"
case "`uname -r`" in 2.6.24*) ;; *) echo "WARNING: tested only on kernel 2.6.24.4, found `uname -r`" ;; esac
[ -f $INITD/_SK50sshd ] || die "$INITD/_SK50sshd not found - is this WD My Book World Edition firmware?"
grep -q '^sshd:' /etc/passwd || die "privsep user 'sshd' missing in /etc/passwd (the WD firmware has it: sshd:x:103:99:...)"

# ---- back up the init script ----
if ! grep -q "$MARK" $INITD/_SK50sshd; then
	[ -f $INITD/_SK50sshd.wd-orig ] || { cp -p $INITD/_SK50sshd $INITD/_SK50sshd.wd-orig && say "saved original as $INITD/_SK50sshd.wd-orig"; }
fi
cp -p $INITD/_SK50sshd $INITD/_SK50sshd.bak-$TS && say "backup: $INITD/_SK50sshd.bak-$TS"

if [ $MODE = test ]; then
	[ -n "$TARBALL" ] && [ -f "$TARBALL" ] || die "bin/openssh-*-armv5te-static.tar.gz not found next to scripts/"
	# ---- unpack (binaries replaced; existing config and host keys kept) ----
	say "unpacking ${TARBALL##*/} to $PREFIX"
	TMP=/usr/local/.openssh-unpack-$$
	rm -rf $TMP; mkdir -p $TMP || die "mkdir $TMP"
	tar -xzf "$TARBALL" -C $TMP || die "unpack failed"
	[ -x $TMP/openssh/sbin/sshd ] || die "tarball layout unexpected"
	$TMP/openssh/bin/ssh -V 2>&1 | grep -q OpenSSH || die "binary does not run on this NAS"
	mkdir -p $PREFIX/bin $PREFIX/sbin $PREFIX/libexec $PREFIX/etc
	# copy + rename, so binaries of a running sshd can be replaced ("Text file busy" otherwise)
	for d in bin sbin libexec; do
		for f in $TMP/openssh/$d/*; do
			b=${f##*/}
			cp -p $f $PREFIX/$d/.$b.new && mv -f $PREFIX/$d/.$b.new $PREFIX/$d/$b || die "copy $d/$b failed"
		done
	done
	for f in moduli ssh_config; do cp -p $TMP/openssh/etc/$f $PREFIX/etc/$f; done
	if [ -f $CONF ]; then
		cp -p $TMP/openssh/etc/sshd_config $CONF.dist; say "kept existing $CONF (new sample: $CONF.dist)"
	else
		cp -p $TMP/openssh/etc/sshd_config $CONF
	fi
	rm -rf $TMP
	chown -R 0:0 $PREFIX; chmod 755 $PREFIX $PREFIX/*
	[ -d /var/empty ] || { mkdir -p /var/empty && chmod 755 /var/empty; }

	# ---- host keys (only if missing) ----
	for t in ed25519 ecdsa rsa; do
		k=$PREFIX/etc/ssh_host_${t}_key
		[ -f $k ] && continue
		b=; [ $t = rsa ] && b="-b 3072" && say "generating rsa 3072 host key (takes ~2 minutes on the OX810)"
		$PREFIX/bin/ssh-keygen -q -t $t $b -N "" -C "" -f $k </dev/null || die "ssh-keygen $t failed"
		chmod 600 $k; chmod 644 $k.pub
	done
	for k in $PREFIX/etc/ssh_host_*_key.pub; do $PREFIX/bin/ssh-keygen -l -f $k; done

	$PREFIX/sbin/sshd -t -f $CONF || die "sshd -t failed for $CONF"
	$PREFIX/bin/ssh -V

	# ---- test instance on $TEST_PORT ----
	# Started through a symlink named sshd-test so that the GUI's "killall sshd" does not hit it.
	if [ -f $TEST_PID ]; then kill `cat $TEST_PID` 2>/dev/null; rm -f $TEST_PID; sleep 1; fi
	ln -sf sshd $PREFIX/sbin/sshd-test
	$PREFIX/sbin/sshd-test -f $CONF -p $TEST_PORT -o PidFile=$TEST_PID </dev/null >/dev/null 2>&1 || die "test sshd failed to start"
	sleep 1
	netstat -ltn | grep -q ":$TEST_PORT " || die "test sshd is not listening on $TEST_PORT"
	say "test sshd running on port $TEST_PORT (pid `cat $TEST_PID`). The stock sshd was not touched."
	[ -s /root/.ssh/authorized_keys ] || echo "WARNING: /root/.ssh/authorized_keys is missing or empty. Root login is KEY-ONLY (PermitRootLogin prohibit-password)."
	cat <<EOT

Next steps:
  1. From your computer, test WITHOUT any legacy options:
       ssh -p $TEST_PORT root@<NAS_IP>     scp -P $TEST_PORT ...     sftp -P $TEST_PORT ...
  2. If that works, log in on port $TEST_PORT and run:  sh $HERE/scripts/install.sh --switch
  3. Stop the test instance later with:  kill \`cat $TEST_PID\`
EOT
	exit 0
fi

# ================= --switch =================
[ -x $PREFIX/sbin/sshd ] || die "run install.sh without --switch first"
[ -f $HERE/scripts/_SK50sshd ] || die "scripts/_SK50sshd not found"
cat <<EOT
*** WARNING: root login on the new sshd is KEY-ONLY (PermitRootLogin prohibit-password).
*** If /root/.ssh/authorized_keys does not contain a key you have tested on port $TEST_PORT,
*** you will lock yourself out of SSH (the web GUI keeps working).
EOT
[ -s /root/.ssh/authorized_keys ] || die "/root/.ssh/authorized_keys is missing or empty - refusing to switch"
$PREFIX/sbin/sshd -t -f $CONF || die "sshd -t failed for $CONF - not switching"
PORT=`sed -n 's/^[Pp]ort[ 	]*\([0-9]*\).*/\1/p' $CONF | sed -n 1p`; [ -n "$PORT" ] || PORT=22
# refuse if something other than an sshd we are about to restart already listens on $PORT
OLDPORT=`sed -n 's/^[Pp]ort[ 	]*\([0-9]*\).*/\1/p' /etc/sshd_config | sed -n 1p`; [ -n "$OLDPORT" ] || OLDPORT=22   # digits only (WD config has trailing blanks)
if netstat -ltn | grep -q ":$PORT " && ! grep -q "$MARK" $INITD/_SK50sshd && [ "$OLDPORT" != "$PORT" ]; then
	die "port $PORT is already in use by something else"
fi

cp $HERE/scripts/_SK50sshd $INITD/_SK50sshd.new && chmod 755 $INITD/_SK50sshd.new && mv $INITD/_SK50sshd.new $INITD/_SK50sshd || die "installing _SK50sshd failed"
say "installed new $INITD/_SK50sshd (previous one: $INITD/_SK50sshd.bak-$TS)"

if [ ! -L $INITD/S50sshd ]; then
	say "SSH is disabled in the web GUI ($INITD/S50sshd missing): nothing restarted. Enabling SSH in the GUI will start the new sshd."
	exit 0
fi

# The old stop does "killall sshd", which also kills sessions of the stock sshd (possibly this one),
# so the restart runs detached and logs to /var/log/openssh-switch.log.
LOG=/var/log/openssh-switch.log
RUNLOG=/var/log/openssh-switch.last
say "restarting via $INITD/S50sshd in the background, log: $LOG"
(
	trap '' HUP
	echo "--- `date` switch"
	$INITD/S50sshd stop
	$INITD/S50sshd start
	sleep 2
	if netstat -ltn | grep -q ":$PORT "; then
		echo "OK: new sshd listening on port $PORT (pid `cat /var/run/sshd.pid 2>/dev/null`)"
	else
		echo "FAILED: nothing on port $PORT - rolling back to $INITD/_SK50sshd.bak-$TS"
		cp -p $INITD/_SK50sshd.bak-$TS $INITD/_SK50sshd
		$INITD/S50sshd stop; $INITD/S50sshd start
	fi
	netstat -ltn | grep -E ":(22|443|$PORT|$TEST_PORT) "
	cat $RUNLOG >> $LOG
) </dev/null >$RUNLOG 2>&1 &
sleep 6
cat $RUNLOG
echo "Test 'ssh -p $PORT root@<NAS_IP>' from your computer (sessions on other ports stay connected)."
if [ -f $TEST_PID ] && kill -0 `cat $TEST_PID` 2>/dev/null; then
	echo "Then stop the test instance:  kill \`cat $TEST_PID\`"
fi

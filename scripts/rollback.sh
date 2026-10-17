#!/bin/sh
# rollback.sh - go back to the stock WD sshd (OpenSSH 3.9p1 on the port in /etc/sshd_config, normally 443).
# Run ON the NAS as root.
#   sh scripts/rollback.sh           restore the original /etc/init.d/_SK50sshd and restart sshd
#   sh scripts/rollback.sh --purge   also delete /usr/local/openssh (binaries, config AND its host keys)
INITD=/etc/init.d
PREFIX=/usr/local/openssh
MARK=/usr/local/openssh/sbin/sshd
die() { echo "ERROR: $*" >&2; exit 1; }
PURGE=no
case "$1" in
  "") ;;
  --purge) PURGE=yes ;;
  -h|--help) sed -n '2,6p' $0; exit 0 ;;
  *) die "unknown option $1 (use --purge or nothing)" ;;
esac
[ "`id -u`" = 0 ] || die "run as root"

# find the original WD script: _SK50sshd.wd-orig, else the newest backup that does not start the new sshd
ORIG=
if [ -f $INITD/_SK50sshd.wd-orig ]; then ORIG=$INITD/_SK50sshd.wd-orig
else
	for f in `ls -t $INITD/_SK50sshd.bak-* 2>/dev/null`; do
		grep -q "$MARK" $f || { ORIG=$f; break; }
	done
fi
[ -n "$ORIG" ] || die "no original _SK50sshd backup found (_SK50sshd.wd-orig / _SK50sshd.bak-*)"
grep -q '/usr/sbin/sshd' $ORIG || die "$ORIG does not look like the WD sshd script"
echo "==> restoring $INITD/_SK50sshd from $ORIG"
OLDPORT=`sed -n 's/^[Pp]ort[ 	]*\([0-9]*\).*/\1/p' /etc/sshd_config | sed -n 1p`; [ -n "$OLDPORT" ] || OLDPORT=22   # digits only (WD config has trailing blanks)

LOG=/var/log/openssh-switch.log
RUNLOG=/var/log/openssh-switch.last
(
	trap '' HUP
	echo "--- `date` rollback"
	if [ -f /var/run/sshd.pid ]; then kill `cat /var/run/sshd.pid` 2>/dev/null; sleep 1; fi
	[ -f /var/run/sshd-test.pid ] && kill `cat /var/run/sshd-test.pid` 2>/dev/null
	rm -f /var/run/sshd-test.pid $PREFIX/sbin/sshd-test
	cp -p $ORIG $INITD/_SK50sshd && chmod 755 $INITD/_SK50sshd
	if [ -L $INITD/S50sshd ]; then
		$INITD/S50sshd stop; $INITD/S50sshd start
	else
		echo "SSH is disabled in the web GUI - not starting sshd"
	fi
	sleep 2
	netstat -ltn | grep -E ":(22|443|2222|$OLDPORT) "
	cat $RUNLOG >> $LOG
) </dev/null >$RUNLOG 2>&1 &
sleep 6
cat $RUNLOG

if netstat -ltn | grep -q ":$OLDPORT "; then
	echo "==> stock sshd is listening on port $OLDPORT again (clients need the legacy options)."
elif [ -L $INITD/S50sshd ]; then
	echo "WARNING: nothing listens on port $OLDPORT - check $LOG. Keep your current session open!"
	[ $PURGE = yes ] && die "not purging $PREFIX while no sshd is listening"
fi

if [ $PURGE = yes ]; then
	rm -rf $PREFIX && echo "==> removed $PREFIX (binaries, config and its host keys)"
fi

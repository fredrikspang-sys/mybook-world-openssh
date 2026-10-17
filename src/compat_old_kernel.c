/*
 * compat_old_kernel.c - link-time overrides for running static musl binaries on
 * Linux 2.6.24 ARM (WD My Book World Edition II), which lacks ppoll/pselect6
 * and getrandom. Linked as an object before libc, so these definitions win.
 *
 * ppoll(): emulated with poll() while keeping signals BLOCKED; every slice we
 * check sigpending() for signals the caller's mask would unblock. If one is
 * pending we briefly apply the caller's mask (so the handler runs) and return
 * -1/EINTR, exactly like real ppoll would. Max added signal latency = SLICE_MS.
 */
#define _GNU_SOURCE
#include <poll.h>
#include <signal.h>
#include <time.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/syscall.h>

#define SLICE_MS 250

static long long now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (long long)t.tv_sec * 1000 + t.tv_nsec / 1000000;
}

static int deliverable_pending(const sigset_t *mask)
{
	sigset_t pend;
	int s;
	if (sigpending(&pend) != 0)
		return 0;
	for (s = 1; s < _NSIG; s++)
		if (sigismember(&pend, s) == 1 && sigismember(mask, s) != 1)
			return 1;
	return 0;
}

int ppoll(struct pollfd *fds, nfds_t nfds, const struct timespec *ts, const sigset_t *mask)
{
	long long deadline = -1;
	int r, saved;

	if (ts) {
		long long ms = (long long)ts->tv_sec * 1000 + (ts->tv_nsec + 999999) / 1000000;
		deadline = now_ms() + ms;
	}
	if (!mask) {
		long long ms = ts ? deadline - now_ms() : -1;
		if (ms > 0x7fffffff) ms = 0x7fffffff;
		return poll(fds, nfds, ts ? (int)(ms < 0 ? 0 : ms) : -1);
	}
	for (;;) {
		int slice = SLICE_MS;
		if (deliverable_pending(mask)) {
			sigset_t old;
			sigprocmask(SIG_SETMASK, mask, &old);   /* handlers run here */
			sigprocmask(SIG_SETMASK, &old, NULL);
			errno = EINTR;
			return -1;
		}
		if (deadline >= 0) {
			long long left = deadline - now_ms();
			if (left <= 0)
				return poll(fds, nfds, 0);
			if (left < slice)
				slice = (int)left;
		}
		r = poll(fds, nfds, slice);
		if (r != 0)
			return r;    /* events, or a real error */
		if (deadline >= 0 && now_ms() >= deadline)
			return 0;
	}
	(void)saved;
}

/* getrandom()/getentropy(): try the syscall, fall back to /dev/urandom */
static int urandom_fill(void *buf, size_t len)
{
	unsigned char *p = buf;
	int fd = open("/dev/urandom", O_RDONLY | O_NOCTTY);
	if (fd < 0)
		return -1;
	while (len > 0) {
		ssize_t n = read(fd, p, len);
		if (n < 0 && errno == EINTR)
			continue;
		if (n <= 0) {
			close(fd);
			return -1;
		}
		p += n;
		len -= (size_t)n;
	}
	close(fd);
	return 0;
}

ssize_t getrandom(void *buf, size_t len, unsigned flags)
{
#ifdef SYS_getrandom
	long r = syscall(SYS_getrandom, buf, len, flags);
	if (r >= 0 || errno != ENOSYS)
		return r;
#endif
	(void)flags;
	return urandom_fill(buf, len) == 0 ? (ssize_t)len : -1;
}

/* getentropy() is provided by LibreSSL's getentropy_linux.c (ENOSYS -> /dev/urandom) */

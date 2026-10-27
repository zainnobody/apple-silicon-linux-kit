// LD_PRELOAD library: simulates the G15 kernel's sticky VM error after a GPU fault
// (docs/gpu-fault-2026-10-26.md). After LOST_AFTER_S seconds (default 5) from the first
// asahi ioctl, VM_BIND, GEM_CREATE and SUBMIT on the asahi render node fail with EIO, as they
// do for a VM that carries a sticky error. Other ioctls pass through.
// Build (needs Mesa's include/drm-uapi):
//   gcc -O2 -shared -fPIC -I ~/m3gpu/src/mesa/include/drm-uapi -o lost-context-inject.so \
//       tests/lost-context-inject.c -ldl
// Run:  LD_PRELOAD=./lost-context-inject.so LOST_AFTER_S=5 es2gears_wayland
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <time.h>
#include <drm.h>
#include "asahi_drm.h"

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

static int lost(void)
{
	static double start;
	static double after = -1;
	static int said;
	if (after < 0) {
		const char *e = getenv("LOST_AFTER_S");
		after = e ? atof(e) : 5;
		start = now();
	}
	if (now() - start < after)
		return 0;
	if (!said) {
		said = 1;
		fprintf(stderr, "lost-context-inject: VM_BIND, GEM_CREATE and SUBMIT now fail with EIO\n");
	}
	return 1;
}

int ioctl(int fd, unsigned long request, ...)
{
	static int (*real)(int, unsigned long, ...);
	if (!real)
		real = (int (*)(int, unsigned long, ...))dlsym(RTLD_NEXT, "ioctl");

	va_list ap;
	va_start(ap, request);
	void *arg = va_arg(ap, void *);
	va_end(ap);

	unsigned int req = (unsigned int)request;
	if (req == (unsigned int)DRM_IOCTL_ASAHI_VM_BIND || req == (unsigned int)DRM_IOCTL_ASAHI_GEM_CREATE ||
	    req == (unsigned int)DRM_IOCTL_ASAHI_SUBMIT) {
		if (lost()) {
			errno = EIO;
			return -1;
		}
	}
	return real(fd, request, arg);
}

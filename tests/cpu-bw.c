// CPU memory read bandwidth: threads sum a 1 GiB array, best and mean of the runs, in GB/s.
// Linux:  gcc -O3 -march=native -fopenmp tests/cpu-bw.c -o cpu-bw
// macOS:  clang -O3 -mcpu=native tests/cpu-bw.c -o cpu-bw   (pthreads, Apple clang has no OpenMP)
// Run:    OMP_NUM_THREADS=6 ./cpu-bw [runs]
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#ifdef _OPENMP
#include <omp.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec * 1e-9;
}

#ifndef _OPENMP
struct part { const uint64_t *a; size_t begin, end; uint64_t sum; };

static void *fill_part(void *arg)
{
	struct part *p = arg;
	uint64_t *a = (uint64_t *)p->a;
	for (size_t i = p->begin; i < p->end; i++) a[i] = i;
	return NULL;
}

static void *sum_part(void *arg)
{
	struct part *p = arg;
	/* Four chains: one chain is limited by add latency (about 20 GB/s), not by memory. */
	uint64_t a0 = 0, a1 = 0, a2 = 0, a3 = 0;
	size_t i = p->begin;
	for (; i + 4 <= p->end; i += 4) {
		a0 += p->a[i]; a1 += p->a[i + 1]; a2 += p->a[i + 2]; a3 += p->a[i + 3];
	}
	for (; i < p->end; i++) a0 += p->a[i];
	p->sum = a0 + a1 + a2 + a3;
	return NULL;
}

static uint64_t run_threads(void *(*fn)(void *), const uint64_t *a, size_t n, int threads)
{
	pthread_t tid[64];
	struct part parts[64];
	uint64_t total = 0;
	for (int t = 0; t < threads; t++) {
		parts[t] = (struct part){ a, n * t / threads, n * (t + 1) / threads, 0 };
		pthread_create(&tid[t], NULL, fn, &parts[t]);
	}
	for (int t = 0; t < threads; t++) {
		pthread_join(tid[t], NULL);
		total += parts[t].sum;
	}
	return total;
}
#endif

int main(int c, char **v)
{
	int runs = c > 1 ? atoi(v[1]) : 8;
	size_t n = (size_t)1 << 27; /* 128 Mi uint64 = 1 GiB */
	uint64_t *a = aligned_alloc(64, n * 8);
#ifdef _OPENMP
	int threads = omp_get_max_threads();
	#pragma omp parallel for
	for (size_t i = 0; i < n; i++) a[i] = i;
#else
	const char *env = getenv("OMP_NUM_THREADS");
	int threads = env ? atoi(env) : (int)sysconf(_SC_NPROCESSORS_ONLN);
	if (threads < 1) threads = 1;
	if (threads > 64) threads = 64;
	run_threads(fill_part, a, n, threads);
#endif
	double best = 1e9, total = 0;
	uint64_t s = 0;
	for (int r = 0; r < runs; r++) {
		double t0 = now();
		uint64_t acc = 0;
#ifdef _OPENMP
		#pragma omp parallel for reduction(+:acc)
		for (size_t i = 0; i < n; i += 4) acc += a[i] + a[i + 1] + a[i + 2] + a[i + 3];
#else
		acc = run_threads(sum_part, a, n, threads);
#endif
		double dt = now() - t0;
		if (dt < best) best = dt;
		total += dt;
		s += acc;
	}
	printf("threads %d, %d runs: best %.1f GB/s, mean %.1f GB/s (check %llu)\n", threads, runs,
	       n * 8 / best / 1e9, n * 8 / (total / runs) / 1e9, (unsigned long long)(s & 0xff));
	return 0;
}

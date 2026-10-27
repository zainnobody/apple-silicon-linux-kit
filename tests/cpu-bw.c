// CPU memory read bandwidth: OpenMP threads sum a 1 GiB array, best of 8 runs, in GB/s.
// Build: gcc -O3 -march=native -fopenmp tests/cpu-bw.c -o cpu-bw. Run: OMP_NUM_THREADS=6 ./cpu-bw
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <omp.h>
int main(int c, char **v) {
	size_t n = (size_t)1 << 27; /* 128 Mi uint64 = 1 GiB */
	uint64_t *a = aligned_alloc(64, n * 8);
	#pragma omp parallel for
	for (size_t i = 0; i < n; i++) a[i] = i;
	double best = 1e9; uint64_t s = 0;
	for (int r = 0; r < 8; r++) {
		struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
		uint64_t acc = 0;
		#pragma omp parallel for reduction(+:acc)
		for (size_t i = 0; i < n; i++) acc += a[i];
		clock_gettime(CLOCK_MONOTONIC, &t1);
		double dt = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) * 1e-9;
		if (dt < best) best = dt; s += acc;
	}
	printf("threads %d: best %.1f GB/s (check %llu)\n", omp_get_max_threads(), n * 8 / best / 1e9, (unsigned long long)(s & 0xff));
	return 0;
}

#ifndef NC_BENCHMARK_H
#define NC_BENCHMARK_H

#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <math.h>
#include <errno.h>

#define SKADI_BENCHMARK_DISCARD_FIRST 5

static inline void nc_benchmark_evaluate_samples(const int64_t *samples, size_t samples_num, size_t errors, const char *name){
	int64_t min_diff, max_diff, sum_diff = 0;
	double mean_diff, variance_diff=0, stddev_diff;
	const char *name_token;
	int less_than_0 = 0;

	// always discard first samples (warmup / caches still cold)
	if(samples_num > SKADI_BENCHMARK_DISCARD_FIRST){
		samples_num -= SKADI_BENCHMARK_DISCARD_FIRST;
		samples += SKADI_BENCHMARK_DISCARD_FIRST;
	}

	min_diff = samples[0];
	max_diff = samples[0];

	name_token = name;

	printf("======================\n");
	printf("Raw %s:\n", name_token);

	for(size_t num_sync = 0; num_sync < samples_num; num_sync ++){
		// invalid sample
		if(samples[num_sync] < 0){
			less_than_0++;
			continue;
		}
		if(min_diff > samples[num_sync]){
			min_diff = samples[num_sync];
		}
		if(max_diff < samples[num_sync]){
			max_diff = samples[num_sync];
		}
		sum_diff += samples[num_sync];

		printf("%"PRId64"\n",samples[num_sync]);
	}

	mean_diff = (double)sum_diff / (samples_num - less_than_0);
	for(size_t num_sync = 0; num_sync < samples_num; num_sync ++){
		if(samples[num_sync] >= 0){
			variance_diff += (mean_diff - samples[num_sync]) * (mean_diff - samples[num_sync]);
		}
	}

	errors += less_than_0;
	samples_num -= less_than_0;

	variance_diff /= samples_num;

	stddev_diff = sqrt(variance_diff);

	printf("======================\n");

	printf("%s discarded/min/max/avg/stddev ns: %zu/%"PRId64"/%"PRId64"/%f/%f\n", name_token, errors, min_diff, max_diff,mean_diff, stddev_diff);
}


#endif

#ifndef SKADI_RANDOM_H
#define SKADI_RANDOM_H

#include <zephyr/random/random.h>
#include <zephyr/skadi/skadi_subsystem.h>


static inline int skadi_sys_csrand_get(void *dst, size_t outlen){
   uint64_t rand_bits;
   size_t rand_bits_left = 0;
   uint8_t *dst_byte = dst;

   while(outlen){
		size_t bytes_this_iteration =  MIN(outlen, sizeof(rand_bits));
		if(!rand_bits_left){
			rand_bits = skadi_cap_ops_get_trng_bits();
		}
		memcpy(dst_byte, &rand_bits, bytes_this_iteration);
		outlen -= MIN(outlen, bytes_this_iteration);
		dst_byte += bytes_this_iteration;
   }
   /* cannot fail */
   return 0;
}

#define skadi_sys_rand_get(DST, OUTLEN) ((void)skadi_sys_csrand_get(DST, OUTLEN))

/* inlines copied from random.h */

/**
 * @brief Return a 8-bit random value that should pass general
 * randomness tests.
 *
 * @note The random value returned is not a cryptographically secure
 * random number value.
 *
 * @return 8-bit random value.
 */
static inline uint8_t skadi_sys_rand8_get(void)
{
	uint8_t ret;

	skadi_sys_rand_get(&ret, sizeof(ret));

	return ret;
}

/**
 * @brief Return a 16-bit random value that should pass general
 * randomness tests.
 *
 * @note The random value returned is not a cryptographically secure
 * random number value.
 *
 * @return 16-bit random value.
 */
static inline uint16_t skadi_sys_rand16_get(void)
{
	uint16_t ret;

	skadi_sys_rand_get(&ret, sizeof(ret));

	return ret;
}

/**
 * @brief Return a 32-bit random value that should pass general
 * randomness tests.
 *
 * @note The random value returned is not a cryptographically secure
 * random number value.
 *
 * @return 32-bit random value.
 */
static inline uint32_t skadi_sys_rand32_get(void)
{
	uint32_t ret;

	skadi_sys_rand_get(&ret, sizeof(ret));

	return ret;
}

/**
 * @brief Return a 64-bit random value that should pass general
 * randomness tests.
 *
 * @note The random value returned is not a cryptographically secure
 * random number value.
 *
 * @return 64-bit random value.
 */
static inline uint64_t skadi_sys_rand64_get(void)
{
	uint64_t ret;

	skadi_sys_rand_get(&ret, sizeof(ret));

	return ret;
}



#endif /* SKADI_RANDOM_H */

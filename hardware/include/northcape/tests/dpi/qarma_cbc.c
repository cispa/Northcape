/**
 * Reference implementation of Quarma-64, wraps C implementation.
 * Imported into Northcape Capability Operations Module testbench via DPI (Direct Programming Interface).
 */
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "dpi.h"

typedef uint8_t byte;

#define NORTHCAPE_BLOCK_SIZE_BYTES 256/8

#define QARMA64_BLOCK_SIZE_BYTES 8

#define QARMA64_KEY_SIZE_BYTES 16

typedef uint64_t const_t;
typedef uint64_t tweak_t;
typedef uint64_t text_t;
typedef uint64_t key_t;

#define QUARMA64_NUMBER_ROUNDS 7
#define CBC_NUMBER_ITERATIONS ((NORTHCAPE_BLOCK_SIZE_BYTES) / QARMA64_BLOCK_SIZE_BYTES)

text_t qarma64_enc(text_t plaintext, tweak_t tweak, key_t w0, key_t k0, int rounds);

DPI_LINKER_DECL DPI_DLLESPEC 
 void qarma_cbc_mac(
	svBitVecVal tag_in[SV_PACKED_DATA_NELEMS(256)] ,
	svBitVecVal in_key[SV_PACKED_DATA_NELEMS(128)] ,
	const svBitVecVal tweak[SV_PACKED_DATA_NELEMS(64)],
    svBitVecVal* tag_out){
    text_t in_block[CBC_NUMBER_ITERATIONS];
    // key partitioning in qarma
    key_t core_key, whitening_key;
    const byte *in_key_bytes = (byte *) in_key;
    
    text_t ciphertext;
    text_t tag;
    tweak_t in_tweak = *tweak;

    whitening_key = core_key = 0;

    memcpy(&core_key, in_key_bytes, sizeof(core_key));
    memcpy(&whitening_key, &in_key_bytes[QARMA64_BLOCK_SIZE_BYTES], sizeof(whitening_key));
    memcpy(in_block,tag_in,sizeof(in_block));

    tag = 0;
#ifdef DEBUG
    printf("Quarma CBC MAC has computed core key %"PRIx64" whitening key %"PRIx64" tweak %"PRIx64"\n",core_key,whitening_key,in_tweak);
#endif

    for(int i = 0; i < CBC_NUMBER_ITERATIONS; i++){
        text_t old_tag = tag;
        tag = tag ^ in_block[CBC_NUMBER_ITERATIONS - i - 1];

        tag = qarma64_enc(tag,in_tweak,whitening_key,core_key,QUARMA64_NUMBER_ROUNDS);

#ifdef DEBUG
        printf("Quarma CBC round %u message block %"PRIx64" input tag %"PRIx64" output tag %"PRIx64"\n",i,in_block[CBC_NUMBER_ITERATIONS - i - 1],old_tag,tag);
#endif
    }

#ifdef DEBUG
    printf("Qarma CBC computed tag %x for input {%"PRIx64",%"PRIx64",%"PRIx64",%"PRIx64"}\n",tag,in_block[0],in_block[1],in_block[2],in_block[3]);
#endif

    memcpy(tag_out,&tag,sizeof(tag));
}

DPI_LINKER_DECL DPI_DLLESPEC 
void qarma_wrapper(
    svBitVecVal in_data[SV_PACKED_DATA_NELEMS(64)] ,
	svBitVecVal in_key[SV_PACKED_DATA_NELEMS(128)] ,
	const svBitVecVal tweak[SV_PACKED_DATA_NELEMS(64)],
    svBitVecVal* block_out
){
    // key partitioning in qarma
    key_t core_key, whitening_key;
    const byte *in_key_bytes = (byte *) in_key;
    text_t encrypted_out;
    tweak_t in_tweak = *tweak;
    text_t data;
    

    memcpy(&core_key, in_key_bytes, sizeof(core_key));
    memcpy(&whitening_key, &in_key_bytes[QARMA64_BLOCK_SIZE_BYTES], sizeof(whitening_key));
    memcpy(&data,in_data,sizeof(data));


    encrypted_out = qarma64_enc(data,in_tweak,whitening_key,core_key, QUARMA64_NUMBER_ROUNDS);

#ifdef DEBUG
    printf("Qarma CBC computed tag %"PRIx64" for data %"PRIx64" tweak %"PRIx64" whitening key %"PRIx64" core key %"PRIx64"\n",encrypted_out,data,in_tweak,whitening_key,core_key);
#endif

    memcpy(block_out,&encrypted_out,sizeof(encrypted_out));
}

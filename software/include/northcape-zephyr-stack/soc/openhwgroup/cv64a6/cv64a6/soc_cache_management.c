#include <stddef.h>
#include <stdint.h>

#include <zephyr/toolchain.h>
#include <zephyr/sys/util_macro.h>

#include <zephyr/arch/cache.h>
#ifdef CONFIG_SKADI_OS
#include <zephyr/llext/symbol.h>
#endif

#define RISCV_MISC_MEM_OPCOPE 0b0001111
#define RISCV_FUNC3_CBO 0b010

#define RISCV_IMM_CBO_FLUSH 0b000000000010
#define RISCV_IMM_CBO_CLEAN 0b000000000001
#define RISCV_IMM_CBO_INVAL 0b000000000000

#define CBO_CLEAN_STR(REG) ".insn i " STRINGIFY(RISCV_MISC_MEM_OPCOPE) "," STRINGIFY(RISCV_FUNC3_CBO) ", zero," STRINGIFY(REG) "," STRINGIFY(RISCV_IMM_CBO_CLEAN)
#define CBO_INVAL_STR(REG) ".insn i " STRINGIFY(RISCV_MISC_MEM_OPCOPE) "," STRINGIFY(RISCV_FUNC3_CBO) ", zero," STRINGIFY(REG) "," STRINGIFY(RISCV_IMM_CBO_INVAL)

void arch_cache_init(void){
    /* nothing to do */
}

void arch_icache_enable(void){
    __asm__ volatile("csrwi 0x7C0, 0x01");
}

void arch_icache_disable(void){
    __asm__ volatile("csrwi 0x7C0, 0x00");
}

void arch_dcache_enable(void){
    __asm__ volatile("csrwi 0x7C1, 0x01");
}

void arch_dcache_disable(void){
    __asm__ volatile("csrwi 0x7C1, 0x00");
}

int arch_dcache_flush_all(void){
    arch_dcache_disable();
    arch_dcache_enable();
    return 0;
}

int arch_icache_invd_range(void *addr, size_t size){
    ARG_UNUSED(addr);
    ARG_UNUSED(size);
    return arch_icache_flush_all();
}

int arch_icache_flush_all(void){
    arch_icache_disable();
    arch_icache_enable();
    return 0;
}

#ifdef CONFIG_SOC_SERIES_CV64A6_HAS_CMO

#ifdef CONFIG_SKADI_OS
int arch_dcache_flush_range(void *addr, size_t size){

    size_t num_cachelines_affected;
    uint8_t *flush_addr = addr;
    uintptr_t mod = (uintptr_t) addr;

    mod = mod % CONFIG_DCACHE_LINE_SIZE;
    flush_addr -= mod;
    size += mod;

    num_cachelines_affected = (size + CONFIG_DCACHE_LINE_SIZE-1) / CONFIG_DCACHE_LINE_SIZE;

    /* wait for any previous stores to commit */
    __asm__ volatile("fence rw,rw");

    for(size_t cacheline = 0; cacheline < num_cachelines_affected; cacheline++){
        __asm__ volatile("mv t0, %0\n\t" CBO_CLEAN_STR (t0) "\n\t"::"r"(flush_addr):"t0");
        flush_addr += CONFIG_DCACHE_LINE_SIZE;
    }

    if(size % CONFIG_DCACHE_LINE_SIZE > sizeof(void*) ){
        /* last 8 bytes can potentially overhang into a new cache line */
        flush_addr -= CONFIG_DCACHE_LINE_SIZE;
        flush_addr += sizeof(void*);
        __asm__ volatile("mv t0, %0\n\t" CBO_CLEAN_STR (t0) "\n\t"::"r"(flush_addr):"t0");
    }

    /* need to wait for the CMO to commit */
    __asm__ volatile("fence rw,rw");

    return 0;
}

int arch_dcache_invd_range(void *addr, size_t size){

    size_t num_cachelines_affected;
    uint8_t *inval_addr = addr;
    uintptr_t mod = (uintptr_t) addr;

    mod = mod % CONFIG_DCACHE_LINE_SIZE;
    inval_addr -= mod;
    size += mod;

    num_cachelines_affected = (size + CONFIG_DCACHE_LINE_SIZE-1) / CONFIG_DCACHE_LINE_SIZE;

    for(size_t cacheline = 0; cacheline < num_cachelines_affected; cacheline++){
        __asm__ volatile("mv t0, %0\n\t" CBO_INVAL_STR (t0) "\n\t"::"r"(inval_addr):"t0");
        inval_addr += CONFIG_DCACHE_LINE_SIZE;
    }

    if(size % CONFIG_DCACHE_LINE_SIZE > sizeof(void*) ){
        /* last 8 bytes can potentially overhang into a new cache line */
        inval_addr -= CONFIG_DCACHE_LINE_SIZE;
        inval_addr += sizeof(void*);
        __asm__ volatile("mv t0, %0\n\t" CBO_INVAL_STR (t0) "\n\t"::"r"(inval_addr):"t0");
    }

    /* need to wait for the CMO to commit */
    __asm__ volatile("fence rw,rw");

    return 0;
}

#else

int arch_dcache_flush_range(void *addr, size_t size){

    const size_t num_cachelines_affected = (size + CONFIG_DCACHE_LINE_SIZE-1) / CONFIG_DCACHE_LINE_SIZE;
    uint8_t *flush_addr = addr;
	size_t cacheline;

    /* wait for any previous stores to commit */
     __asm__ volatile("fence rw,rw");

    for(cacheline = 0; cacheline < num_cachelines_affected; cacheline++){
        __asm__ volatile("mv t0, %0\n\t" CBO_CLEAN_STR (t0) "\n\t"::"r"(flush_addr):"t0");
        flush_addr += CONFIG_DCACHE_LINE_SIZE;
    }

	/* need to wait for the CMO to commit */
    __asm__ volatile("fence rw,rw");

    return 0;
}

int arch_dcache_invd_range(void *addr, size_t size){

    const size_t num_cachelines_affected = (size + CONFIG_DCACHE_LINE_SIZE-1) / CONFIG_DCACHE_LINE_SIZE;
    uint8_t *inval_addr = addr;

    for(size_t cacheline = 0; cacheline < num_cachelines_affected; cacheline++){
        __asm__ volatile("mv t0, %0\n\t" CBO_INVAL_STR (t0) "\n\t"::"r"(inval_addr):"t0");
        inval_addr += CONFIG_DCACHE_LINE_SIZE;
    }

    /* need to wait for the CMO to commit */
    __asm__ volatile("fence rw,rw");

    return 0;
}
#endif

#else /* CONFIG_SOC_SERIES_CV64A6_HAS_CMO */
int arch_dcache_flush_range(void *addr, size_t size){
    return arch_dcache_flush_all();
}

int arch_dcache_invd_range(void *addr, size_t size){
    return arch_dcache_flush_all();
}
#endif

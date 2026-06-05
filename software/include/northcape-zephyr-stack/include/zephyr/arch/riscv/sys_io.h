/*
 * Copyright (c) 2023 Meta
 *
 * SPDX-License-Identifier: Apache-2.0
 */

/* Memory mapped registers I/O functions in riscv arch C code */

#ifndef ZEPHYR_INCLUDE_ARCH_RISCV_SYS_IO_H_
#define ZEPHYR_INCLUDE_ARCH_RISCV_SYS_IO_H_

#ifndef _ASMLANGUAGE

#include <zephyr/toolchain.h>
#include <zephyr/types.h>
#include <zephyr/sys/sys_io.h>

#if !defined(CONFIG_RISCV_SOC_HAS_CUSTOM_SYS_IO) && !defined(CONFIG_SKADI_LOADER)
#include <zephyr/arch/common/sys_io.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

#ifdef CONFIG_RISCV_SOC_HAS_CUSTOM_SYS_IO

extern uint8_t z_soc_sys_read8(mem_addr_t addr);
extern void z_soc_sys_write8(uint8_t data, mem_addr_t addr);
extern uint16_t z_soc_sys_read16(mem_addr_t addr);
extern void z_soc_sys_write16(uint16_t data, mem_addr_t addr);
extern uint32_t z_soc_sys_read32(mem_addr_t addr);
extern void z_soc_sys_write32(uint32_t data, mem_addr_t addr);
extern uint64_t z_soc_sys_read64(mem_addr_t addr);
extern void z_soc_sys_write64(uint64_t data, mem_addr_t addr);

static ALWAYS_INLINE uint8_t sys_read8(mem_addr_t addr)
{
	return z_soc_sys_read8(addr);
}

static ALWAYS_INLINE void sys_write8(uint8_t data, mem_addr_t addr)
{
	return z_soc_sys_write8(data, addr);
}

static ALWAYS_INLINE uint16_t sys_read16(mem_addr_t addr)
{
	return z_soc_sys_read16(addr);
}

static ALWAYS_INLINE void sys_write16(uint16_t data, mem_addr_t addr)
{
	return z_soc_sys_write16(data, addr);
}

static ALWAYS_INLINE uint32_t sys_read32(mem_addr_t addr)
{
	return z_soc_sys_read32(addr);
}

static ALWAYS_INLINE void sys_write32(uint32_t data, mem_addr_t addr)
{
	return z_soc_sys_write32(data, addr);
}

static ALWAYS_INLINE uint64_t sys_read64(mem_addr_t addr)
{
	return z_soc_sys_read64(addr);
}

static ALWAYS_INLINE void sys_write64(uint64_t data, mem_addr_t addr)
{
	return z_soc_sys_write64(data, addr);
}

#endif /* CONFIG_RISCV_SOC_HAS_CUSTOM_SYS_IO */

#ifdef CONFIG_SKADI_LOADER
static ALWAYS_INLINE uint8_t sys_read8(mem_addr_t addr)
{
	uint8_t ret;
	__asm__ volatile("lbu %0, 0(%1)\n\t" : "=&r"(ret):"r"(addr):"memory");
	return ret;
}

static ALWAYS_INLINE void sys_write8(uint8_t data, mem_addr_t addr)
{
	__asm__ volatile("sb %0, 0(%1)\n\t" ::"r"(data),"r"(addr):"memory");
}

static ALWAYS_INLINE uint16_t sys_read16(mem_addr_t addr)
{
	uint16_t ret;
	__asm__ volatile("lhu %0, 0(%1)\n\t" : "=&r"(ret):"r"(addr):"memory");
	return ret;
}

static ALWAYS_INLINE void sys_write16(uint16_t data, mem_addr_t addr)
{
	__asm__ volatile("sh %0, 0(%1)\n\t" ::"r"(data),"r"(addr):"memory");
}

static ALWAYS_INLINE uint32_t sys_read32(mem_addr_t addr)
{
	uint32_t ret;
	__asm__ volatile("lw %0, 0(%1)\n\t" : "=&r"(ret):"r"(addr):"memory");
	return ret;
}

static ALWAYS_INLINE void sys_write32(uint32_t data, mem_addr_t addr)
{
	__asm__ volatile("sw %0, 0(%1)\n\t" ::"r"(data),"r"(addr):"memory");
}

static ALWAYS_INLINE uint64_t sys_read64(mem_addr_t addr)
{
	uint64_t ret;
	__asm__ volatile("ld %0, 0(%1)\n\t" : "=&r"(ret):"r"(addr):"memory");
	return ret;
}

static ALWAYS_INLINE void sys_write64(uint64_t data, mem_addr_t addr)
{
	__asm__ volatile("sd %0, 0(%1)\n\t" ::"r"(data),"r"(addr):"memory");
}
#endif

#ifdef __cplusplus
}
#endif

#endif /* _ASMLANGUAGE */

#endif /* ZEPHYR_INCLUDE_ARCH_RISCV_SYS_IO_H_ */

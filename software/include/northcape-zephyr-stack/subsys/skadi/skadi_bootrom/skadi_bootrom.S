
.section .rodata

.global .skadi_loader_elf
.type .skadi_loader_elf, @object
.p2align 3

.skadi_loader_elf:
.incbin "zephyr.bin"

.global .skadi_loader_elf_size
.type .skadi_loader_elf_size, @object
.p2align 3

.skadi_loader_elf_size:
.dword .skadi_loader_elf_size - .skadi_loader_elf

.section .text
.global _start
.type _start, @function

_start:

/* RAM address */
li t0, 0x80000000
ld t1, .skadi_loader_elf_size

la a0, .skadi_loader_elf

_loop:
beqz t1, _loop_done

ld a1, 0(a0)
sd a1, 0(t0)

addi t0, t0, 8
addi a0, a0, 8
addi t1, t1, -8

j _loop

_loop_done:

/* RAM address */
li t0, 0x80000000

/* hope for the best and commence execution! */
jr t0

/* Minimal RISC-V bare-metal linker script
 * https://copilot.microsoft.com/shares/UjTZbPuLrEFJzGZq9kxnZ
 */

ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x1000, LENGTH = 128M
}

SECTIONS
{
    /* Program entry at the beginning of RAM */
    .text : ALIGN(4)
    {
        KEEP(*(.init))
        KEEP(*(.text.start))
        *(.text*)
        *(.rodata*)
    } > RAM
}

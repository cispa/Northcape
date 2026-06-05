// Copyright OpenHW Group contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "uart.h"
#include "spi.h"
#include "sd.h"
#include "gpt.h"

#define PRINT_WORDS_OF_IMAGE 16

int main()
{
    uint8_t *bootimage = (uint8_t *) 0x80000000UL;
    init_uart(CLOCK_FREQUENCY, UART_BITRATE);
    print_uart("Hello World!\r\n");

    int res = gpt_find_boot_partition(bootimage, 2 * 16384);

    if (res == 0)
    {
        print_uart("Loaded boot image successfully!\r\nFirst instructions in the image:\r\n");

        for(int i = 0; i < PRINT_WORDS_OF_IMAGE; i++){
            print_uart_byte(bootimage[i*4]);
            print_uart_byte(bootimage[i*4+1]);
            print_uart_byte(bootimage[i*4+2]);
            print_uart_byte(bootimage[i*4+3]);
            print_uart("\r\n");
        }
        // jump to the address
        // fence needed to ensure written data are visible to instruction cache
        __asm__ volatile(
            "fence.I;"
            "li s0, 0x80000000;"
            "la a1, _dtb;"
            "jr s0");
    }

    while (1)
    {
        // do nothing
    }
}

void handle_trap(void)
{
    // print_uart("trap\r\n");
}

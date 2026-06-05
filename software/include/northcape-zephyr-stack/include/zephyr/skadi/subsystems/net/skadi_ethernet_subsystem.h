#ifndef SKADI_ETHERNET_SUBSYSTEM_H
#define SKADI_ETHERNET_SUBSYSTEM_H
    #include <zephyr/net/net_if.h>
    #include <zephyr/skadi/skadi_subsystem.h>
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_ethernet_init, struct net_if *iface);

    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_net_eth_carrier_on, struct net_if *iface);
    SKADI_SUBSYSTEM_CALLER_TRAMPOLINE_VOID(skadi_net_eth_carrier_off, struct net_if *iface);
#endif

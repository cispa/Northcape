# SPDX-License-Identifier: Apache-2.0

zephyr_library_sources_ifdef(CONFIG_PHY_ADIN2111	phy_adin2111.c)
zephyr_library_sources_ifdef(CONFIG_PHY_TJA1103	        phy_tja1103.c)
zephyr_library_sources_ifdef(CONFIG_PHY_MICROCHIP_KSZ8081	phy_microchip_ksz8081.c)
zephyr_library_sources_ifdef(CONFIG_PHY_REALTEK_RTL8211F phy_realtek_rtl8211f.c)
zephyr_library_sources_ifdef(CONFIG_PHY_QUALCOMM_AR8031 phy_qualcomm_ar8031.c)

if(CONFIG_SKADI_OS)
    if(CONFIG_PHY_GENERIC_MII)
        create_skadi_subsystem_phy_driver(EXT_NAME phy_mii APP zephyr COMPATIBLE ethernet_phy SRCS phy_mii_skadi.c)
    endif()
else()
    zephyr_library_sources_ifdef(CONFIG_PHY_GENERIC_MII	phy_mii.c) 
endif()

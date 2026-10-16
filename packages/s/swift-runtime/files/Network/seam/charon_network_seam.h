/*
 * The interface-by-name seam of Foundation/NWPathMonitor.m (charonInterfaceNamed), declared for the Swift address types.
 * The header of Network has no lookup of an interface by its name, and an address's zone names one (`en0` in `fe80::1%en0`).
 * The seam answers with the interface the kernel has under the name, and nil when it has none.
 */

#include <Network/Network.h>

nw_interface_t charonInterfaceNamed(const char *name);

# The path, the gateways and what this release cannot say

The path itself and the monitor that reports it are in `NWPathMonitor.md`. What is here is the four
calls of iOS 13 to 26 that are about a path, each of which asks this release something it does not have:

- `nw_path_is_constrained` (iOS 13) is Low Data Mode, which this release has not got: no path of it is
  ever constrained, which is the answer a device with the mode switched off gives.
- `nw_path_enumerate_gateways` (iOS 13) names the routers a packet leaves by. The one ioctl that needs
  no privilege and answers it is `SIOCGIFDSTADDR`, and it answers for a **point-to-point** interface -
  which is what `pdp_ip0` is, the cellular data connection of this release. A Wi-Fi interface is not
  point-to-point and has no such answer, so the enumeration is empty for a path over Wi-Fi. The next
  step, a route socket, is what a release with no such socket would refuse, and whether iOS 6.1.3 opens
  one is a device measurement still to be taken; the ioctl here is the part that needs no privilege and
  is the whole of the enumeration that can be had without one.
- `nw_path_get_unsatisfied_reason` (iOS 14.2) answers one of the system's own policies - a permission the
  user denied, a network the user turned off. This release's reachability says whether the network is
  there and never why it is not, so an unsatisfied path is unsatisfied for a reason the release does not
  name, which is what `nw_path_unsatisfied_reason_not_available` says.
- `nw_path_get_link_quality` and `nw_path_is_ultra_constrained` (iOS 26) are about a measurement and
  about a kind of network this release has not got: the link quality is `nw_link_quality_unknown`,
  which is the documented "no measurement available", and no path is ultra-constrained.

`nw_path_monitor_prohibit_interface_type` (iOS 14) is the other way round: a kind of interface the
monitor will not report a path over, which the monitor keeps and leaves out of the interface list it
works out for every path it reports - a path over a prohibited interface is then reported with no
interface, which is what a monitor not allowed to use that interface can honestly say about it. It is in
the Foundation library, in a file of its own (`NWPathMonitor14.m`) because an object that exports the
symbols of two introductions is split by the build.

## How an interface's type is decided, and what the name was wrong about

`charon_type_of()` used to read the interface's **name**: `lo` for the loopback, `pdp_ip` for the
cellular radio, `en` for Wi-Fi, everything else `other`. A device run showed four of twenty checks
failing on the untyped cases, and the two halves of it were wrong in the same way:

- `NWPathMonitor.m` dropped every interface it had typed `other` from a monitor that asked for `other`,
  so the interfaces the kernel itself names as a tunnel or a bridge never appeared on a path at all -
  and those are the interfaces a VPN and a Personal Hotspot put a path on;
- a name cannot tell those apart from anything: `utun*` and `bridge*` both fell through to `other`
  because there was no branch for either, and a `pdp_ip*`-named interface was called cellular whatever
  it carried, which a tunnel over Wi-Fi is not.

It reads the kernel's own answers now, none of which is a name:

- `IFF_LOOPBACK` on the flags says a loopback;
- `SIOCGIFDSTADDR` answering for the interface says a point-to-point link **with a gateway**, which on
  this release is the cellular radio. A tunnel is point-to-point too and has no gateway, and that is
  what separates the two;
- anything else is a broadcast-capable link or a bridge, which on this release - which has no wired
  Ethernet - is the Wi-Fi radio.

The `struct if_data` behind the `AF_LINK` entry carries the kernel's `ifi_type` as well, and that is
what the release itself reads, but the `IFTYPE_*` names for it are in XNU's `net/if_types.h` and in
**no Apple SDK** - this port's 16.4 SDK has a `net/if_types.h` with none of them in it (measured: the
grep for `IFTYPE` in it answers nothing). Spelling those numbers out would be a mapping of constants no
SDK on this port carries, and the three answers above are all measurable on a device.

**What this does not settle:** the four checks that failed are the device harness's, and they are
re-measured on a device, which is not mine to run. What is measured here is that the four interfaces
the review names are now distinguished by mechanism rather than by name, that both targets compile with
the change (0 errors at armv7-apple-ios6.1.3 and 0 for either at 4.3), and that the light guard and
every host differential still pass. The `NWPathMonitor` rows stay as they were until a device run says
otherwise; if a case there cannot be reproduced, it is written into this file and those calls are not
marked `implemented`.

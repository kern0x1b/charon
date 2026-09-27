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

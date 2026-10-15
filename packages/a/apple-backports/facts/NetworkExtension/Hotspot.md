# NEHotspot: the network and configuration objects, what the host answers, and the join route

Three names of the family are strong-imported by applications in the crash corpus and die at load on
6.1.3: NEHotspotConfiguration, NEHotspotConfigurationManager and NEHotspotHelper
(`coordination/corpus/crash-demand-top.tsv`, rows 80, 81 and 174). This file covers the two data classes
that are carried, NEHotspotNetwork and NEHotspotConfiguration, and what the manager and the helper answer on
the host, and why they are not carried yet.

## What is carried

- `NetworkExtension/CharonNEHotspot.h`: the declarations, from the iOS 26.2 SDK's `NEHotspotNetwork.h`,
  `NEHotspotConfigurationManager.h` and the `(HotspotHelper)` category of `NEHotspotHelper.h`.
- `NetworkExtension/NEHotspotNetwork.m`: the state object, and `+fetchCurrentWithCompletionHandler:`.
- `NetworkExtension/NEHotspotConfiguration.m`: the four initializers, the properties, `-copy` and the keyed archive.
- `registry/NetworkExtension/hotspot9.json`: one entry per name, with its introduced, minimum and maximum release.
- `tests/backports/host/netext-hotspot/`: the differential, with one planted control per comparison.

Not carried: NEHotspotEAPSettings and NEHotspotHS20Settings, and the two initializers that take them (absent
in the registry, so they answer NO to respondsToSelector:). NEHotspotEAPSettings is a class of the family the
corpus does not strong-import yet, but the family is not complete while it is missing.

## What the host answers, measured

The host is Mac Catalyst: NEHotspotNetwork and NEHotspotConfiguration are `API_UNAVAILABLE(macos)` in the SDK,
and only the Catalyst image carries them. The probe is `tests/backports/host/netext-hotspot/probe.m`, built once
for the host with `-framework NetworkExtension` and once for the port with the port's sources, and each
operation runs in its own process.

NEHotspotNetwork, a fresh object built with `alloc` and `init`:

```
securityType 0, signalStrength 0, isSecure NO, didAutoJoin NO, didJustJoin NO, isChosenHelper NO
setConfidence: and setPassword: return, and the object keeps going
SSID: SIGSEGV (signal 11, exit 139) on the read. BSSID is not reached.
```

fetchCurrentWithCompletionHandler::

```
calls the handler once, on the main thread, after the call returned (fetch.beforeReturn 0)
answers nil on this Mac, which has no Wi-Fi network to name
```

NEHotspotConfiguration (the port's answers are the same line for line, `dladdr` aside):

```
initWithSSID:            SSID = the name, SSIDPrefix = "" (the empty string, not nil)
initWithSSIDPrefix:      SSID = "", SSIDPrefix = the prefix
defaults                 joinOnce NO, hidden NO, lifeTimeInDays nil
setters                  joinOnce, hidden and lifeTimeInDays keep what is set
-copy                    another object (isSameObject NO), with the same values
NSKeyedArchiver          data, no error; the round trip decodes the same values
```

The `dladdr` line names the image that answered each selector: `NetworkExtension` on the host and `port` on the
port. The harness checks both, so a comparison that a port answers with the host's own class cannot pass.

## Where the port does not match the host, and why

- **SSID and BSSID of an unmeasured network.** The host crashes on the read. A crash is not an answer, and the
  rule is that an API must never crash its caller, so the port answers nil and the harness asserts nil on the
  port alone. The host crash is recorded here and in the harness output, not reproduced.
- **fetchCurrent's network.** The port answers it from CaptiveNetwork (`CNCopySupportedInterfaces` and
  `CNCopyCurrentNetworkInfo`, SSID and BSSID), which the release has and which needs no entitlement. The host
  answers nil on a Mac with no network. The port answers nil on that same Mac, so the two agree here; on a
  device on a Wi-Fi network the port answers the network and the host, without the entitlement, would not.
- **The CaptiveNetwork declarations.** They are declared in `NEHotspotNetwork.m`, not imported: the SDK marks the
  functions deprecated from iOS 9.0 in favour of NEHotspotHelper, and a deprecation warning would need a pragma
  the house rule does not allow. The symbols are the release's own, and the library links SystemConfiguration.

## The fields CaptiveNetwork does not give

`securityType`, `signalStrength`, `secure`, `autoJoined`, `justJoined` and `chosenHelper` answer as the host
answers for a network it did not measure: 0, 0, NO, NO, NO, NO. That is what the brief asked for, and it is named
here so it is not silent. It is also the one place the port can be quietly wrong: an application that reads
`secure` on a WPA network from fetchCurrent gets NO. The coordinator should rule on whether these should answer
something else; the port does not know the security of a network CaptiveNetwork names.

## The manager and the helper: the join route

The manager (`applyConfiguration:completionHandler:`, `removeConfigurationForSSID:`,
`removeConfigurationForHS20DomainName:`, `getConfiguredSSIDsWithCompletionHandler:`, `joinAccessoryHotspot...`)
and the helper (`registerWithOptions:queue:handler:`, `logoff:`, `supportedNetworkInterfaces`, the command and
response classes) are not carried yet. The decision has two parts.

**(a) What the host answers to an application without the hotspot entitlement** (the probe is not entitled, and
the one configuration it applies names an SSID that does not exist; afterwards `networksetup
-listpreferredwirelessnetworks en0` does not list that SSID, so the refusal saved nothing):

```
applyConfiguration:completionHandler:   handler called once, on the main thread;
                                        NSError NEHotspotConfigurationErrorDomain, code 8
                                        (NEHotspotConfigurationErrorInternal)
getConfiguredSSIDsWithCompletionHandler: handler called once, with nil
registerWithOptions:queue:handler:      returns NO; the handler is never called in 3 seconds
supportedNetworkInterfaces              nil
logoff:                                 returns NO
```

removeConfigurationForSSID: and removeConfigurationForHS20DomainName: return nothing and take no handler, so
they are not measured here.

**(b) Whether the 6.1.3 release carries a Wi-Fi join interface an application can call.** The release's
Objective-C classes were read through `tools/corpus/objc-inventory.lua` over the 6.1.3 cache, names only. The
release has no NEHotspot class at all. It does have `WiFiUtils`, in
`/System/Library/PrivateFrameworks/AirPortAssistant.framework/AirPortAssistant`, whose selectors include:

```
-joinNetworkWithNameAsync:password:rememberChoice:
-joinNetworkWithScanInfoAsync:password:rememberChoice:
-joinNetworkWithScanInfo:password:rememberChoice:
-getCurrentAssociationInfo
-dissassociateSync
-asyncWiFiScan:
```

That is a join route. It is private: the framework is not in the SDK, and an application can reach the class only
by loading the framework at run time. `WiFiNetwork` in SkankKit is a user-interface class and is not a route.

So the join route exists and is reachable only through a private framework. Per the brief the port stops here:
it does not implement the join through a private class, and the manager and the helper stay absent until the
coordinator rules. If the coordinator rules that the route is not used, the port answers as (a) above, and that
is the answer to implement: applyConfiguration fails with NEHotspotConfigurationErrorInternal, the helper refuses
to register, and the other calls answer as the host does.

Until that ruling, applications that strong-import NEHotspotConfigurationManager or NEHotspotHelper still fail
to load on 6.1.3, which is rows 81 and 174 of the crash corpus.

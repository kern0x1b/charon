# UIImageAsset, iOS 8

Introduced in iOS 8.0 as the image set an asset catalogue gives for one name: an image registered for each trait
collection or each `UIImageConfiguration`, handed back for whichever variant fits. The SDK 16.4 header is the
contract: all eleven members are 8.0 in `declarations.tsv`.

The release has no asset catalogue to draw these from, and nothing in the release reads an asset on its own. The
class is carried so that an application can build and use one itself. The port keeps the variants in registration
order, matches each key with `isEqual:`, and answers the first variant when the key is not held.

## Measured on the host

Probes on Mac Catalyst. The port's code is written to these answers, but no port-side differential run has checked
it yet, so each line is a host measurement and not a port result.

- a fresh asset answers nil for every lookup, including `imageWithTraitCollection:nil`;
- `registerImage:withTraitCollection:` with a trait collection without a display scale, and with nil, raises
  `NSInternalInconsistencyException` with the reason `scale must be > 0`;
- `registerImage:withConfiguration:` with a nil configuration raises the same exception;
- a nil image registered for a key adds nothing and leaves a registered variant as it was;
- with one variant held, a lookup at any trait, any configuration, or nil answers that variant;
- `unregisterImageWithConfiguration:nil` and `unregisterImageWithTraitCollection:nil` remove nothing, with one variant held;
- `supportsSecureCoding` is YES.

Not measured: the keyed-archive round trip's lookup on a decoded asset, beyond that it returns an image.

## Not matched: several variants

Measured on the host, with a second variant registered, the answers do not follow the port's exact-key rule:

- after a variant is registered for a trait collection with display scale 2 next to one at scale 1, a lookup at scale 2
  still answers the scale 1 variant. The port answers the scale 2 variant;
- after a variant is registered for a trait collection, `unregisterImageWithTraitCollection:` of a trait collection
  the asset does not hold removed a configuration variant that was registered alone. The port removes nothing.

These are the open part of the class. How the host chooses among variants it cannot match exactly, and how it
decides that an unregistered trait collection matches a stored variant, is not measured yet. Until it is, the lookups
with more than one variant, and the unregister of a key the asset does not hold, are the divergence to read first.

## Device

Not run on a device. The asset that the release draws from its own catalogue is not the one a port keeps, so an
application that reads a catalogue image through an asset would see the release's own answer; this port's asset is
the application's own store.

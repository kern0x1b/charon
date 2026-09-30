# WebKit web extensions (iOS 18.4)

The web-extension API, family by family, and what each one's answers were read from. An extension is a
MANIFEST, and that is why the first family carries on a release with no WebKit at all: the manifest is
JSON, and `NSJSONSerialization` and `NSBundle` are on every release this port builds. Nothing here
needs a web view, and the families that DO need one say so.

## What the host answers, and where each answer is measured

Each of these was measured on this machine by making a real extension from a manifest and asking it,
rather than read off a header, which for this API declares the classes and says nothing about the
behaviour.

**`WKWebExtension`** — `supportsManifestVersion:` is YES for 0, 1, 2 and 3 and NO for 4 and 5. The
header does not say which versions are supported and the SDK declares version 3, so a port that
answered "anything below 4" would be guessing. `manifestVersion` is the manifest's own
`manifest_version`. The requested permissions come back **sorted**, not in manifest order: a manifest
asking for `tabs` and `storage` answers storage first. `allRequestedMatchPatterns` holds the
**requested** host patterns only — an optional host pattern stays in its own set, because it has not
been asked for. `defaultLocale` is nil unless the bundle carries the `_locales` messages the manifest
names, and `displayActionLabel` is nil unless the manifest sets one. `errors` is **not** empty for a
manifest that loaded: the host's own run of the probe manifest answers two.

**`WKWebExtensionMatchPattern`** — a pattern is a scheme, then `://`, then a host, then a path, with a
single star for "any" in each, and `<all_urls>` for every http and https URL. A pattern carrying a
**port** is refused, and so is one with no path, both in `WKWebExtensionMatchPatternErrorDomain`. Any
scheme parses, not only http and https. `<all_urls>` answers nil for scheme, host and path and YES
for both `matchesAllHosts` and `matchesAllURLs`; `http://*/*` answers `matchesAllHosts` YES and
`matchesAllURLs` NO. In matching, a **leading star in the host takes zero labels, not one** — so
`https://*.example.com/api/*` answers YES for `https://example.com/api/x` as well as for
`a.example.com` and `b.example.com`; and **neither the port nor the query is part of the match**, so
`a.example.com:8443` and `?q=1` both still match. `<all_urls>` answers NO for `about:blank` and for
`data:text/plain,hi`, and YES for https: it is the http and https URLs, not every URL a process can
name.

**`WKWebExtensionAction` and `WKWebExtensionCommand`** — neither can be made by a program: both
headers mark `-init` and `+new` `NS_UNAVAILABLE`, and the host agrees, both classes allocating and
neither initialiser reachable. A **context** hands them out, because a button and a shortcut only mean
something against a loaded extension and the tabs it acts on. Each keeps ALL of its state in a single
opaque storage ivar — 192 bytes for the action, 72 for the command — which is Apple's C++ storage and
not a shape a port should copy; the port keeps ordinary ivars.

## The manifest keys a context will read

Named here because the context family is where they are used, and the port does not read them itself:
an action's `label` is the action section's `default_title`, its `badgeText` is `default_badge` and its
icon comes from the action's icons; a command's `identifier` is its key in the `commands` object, its
`title` is that command's `name`, and its `activationKey` and modifiers come from `suggested_key`.

## What is not measured, and why

An action and a command only exist once a context has loaded an extension, and building a context needs
`WKWebExtensionController`, which is a later family and needs a web view this port does not have. The
two classes are carried with their members and take their values from the context that will build them;
what a member answers for a **real** extension is measured when that family lands. The same applies to
the three contour-derived members of Vision's `VNGeometryUtils` and to the body-pose observation's joint
filtering: named, not quietly implied.

## WKWebExtensionContext: carried, and every member measured off a real one

A context is **software state**, not a thing a machine has or lacks, so it is carried and callable.
The host hands one out for a real extension:

```
$ [WKWebExtensionContext contextForExtension:extension]      # an extension built from $D/ext/manifest.json
extension ok, errors=2
contextForExtension:ext  = 0x102e58330       a real object
```

and it raises on anything that is not an extension, which is worth carrying because it is the only
public way to make one:

```
NSInternalInconsistencyException, reason:
'Invalid parameter not satisfying: [extension isKindOfClass:WKWebExtension.class]'
3   WebKit   +[WKWebExtensionContext contextForExtension:]
```

The answers below are the host's, for a **fresh** context — one made from a manifest and never loaded
into a web view. This is the state the port carries, so each is a measurement and not a guess.

```
webExtension           the extension that was passed in
webExtensionController nil  -- no controller has it yet
uniqueIdentifier       a fresh UUID per call: two calls answered two different ones
baseURL                webkit-extension://40b2e76e-3b1b-4efb-bb0a-5597824e02b7/
optionsPageURL         webkit-extension://<the same UUID>/options.html
overrideNewTabPageURL  nil  for a manifest with no chrome_url_overrides
loaded 0    inspectable 0
errors                   the extension's own two -- NOT empty
unsupportedAPIs          0
every permission set     0
hasAccessToAllHosts 0  hasAccessToAllURLs 0  hasAccessToPrivateData 0  optionalAllHosts 0
webViewConfiguration     nil
openTabs 0   openWindows 0   focusedWindow nil
inspectionName           "Charon probe — Extension Background Page"
```

Three of those are worth stating separately, because they are not what the names suggest:

- **`commands` is not the manifest's.** The manifest asks for a command called `do-it`, and the host
  answers ONE command whose identifier is `_execute_action` and whose title is the action's
  `default_title`. A manifest with an `action` section has that command **synthesised** for it, and
  the manifest's own command is not in the list. A port that surfaced `do-it` would be answering the
  manifest rather than the release.
- **`inspectionName` carries an em dash** and a description of what the context is showing: the
  manifest's name, then ` — Extension Background Page` when the manifest has a background section.
- **`baseURL` and `optionsPageURL` share the context's own identifier**, so they change when a new
  context is made. A caller that caches a base URL across contexts holds a URL for a context that no
  longer exists.

`WKWebExtensionContextPermissionStatusUnknown` — the zero of the enum the 26.2 SDK declares — is what
a caller reads when nothing has been decided, and it is the value the port carries with no permission
granted or denied.

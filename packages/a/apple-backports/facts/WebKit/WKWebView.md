# WKWebView over the UIWebView of the release, iOS 8

iOS 8 introduced `WKWebView` and the classes around it: the configuration, the preferences, the user content
controller with its scripts and message handlers, the navigation delegate with its actions, and the back-forward
list. iOS 6 has `UIWebView`, which draws the same pages in the process of the application and tells its delegate much
less. The port is a `UIView` that holds a `UIWebView`, hands it what the application loads, and turns what the
`UIWebView` reports into what a `WKNavigationDelegate` is sent.

Source: the host's own WebKit under Mac Catalyst. `tests/backports/host/webkit/run.sh` runs
`tests/backports/device/webkit-cases.m` against a real `WKWebView` and writes what it did to
`webkit-expectations.h`; `tests/backports/device/webkit.m` runs the same cases against the port on the emulated
iOS 6.0 and an iPad 2 on iOS 6.1.3 and holds each answer to the host's. What the `UIWebView` of the release does with
its own delegate was read on the emulator with a plain `UIWebView`, which is where the rules below about the order of
its messages come from.

The port is a separate library, `libWebKitBackports.dylib`, built when the package is asked for `webkit = true`.

## What the port answers as WebKit does

Every record of the host is held on the device except three that differ for a stated reason (below).

- **The state of the view.** A new view has no URL, an empty title, is not loading, has progress 0 and an empty
  history. `loadRequest:`, `loadHTMLString:baseURL:`, `loadData:MIMEType:characterEncodingName:baseURL:` and
  `loadFileURL:allowingReadAccessToURL:` answer a `WKNavigation`, and `URL` and `loading` change before the call
  returns; a `nil` base URL is `about:blank`. `URL`, `title`, `loading`, `canGoBack`, `canGoForward` and
  `estimatedProgress` are observable with key-value observing, in the order WebKit changes them: `URL`, `loading`
  on, `loading` off, `title`.
- **The order of the delegate's messages.** For a load: `decidePolicyForNavigationAction` (type other), then
  `didStartProvisionalNavigation`, `didCommitNavigation`, `didFinishNavigation`, with `loading` on through all of
  them and progress 1 at the end. The title is empty at commit and reaches the view just after the navigation
  finishes, as the host's does. A link answers navigation type 0, going back or forward 2, a reload 3. A subframe is
  asked about with a target frame that is not the main frame, after the commit of the page that holds it.
- **The decision.** `Cancel` stops the navigation, leaves `URL` where it was and `loading` off, and sends nothing
  more. A decision handler called later, after the delegate method returned, is honoured: an `Allow` starts the load
  then, a `Cancel` takes the pending navigation back. A page that loads a URL of a scheme nobody handles fails with
  `didFailProvisionalNavigation`, `NSURLErrorDomain` -1002, after `didStartProvisionalNavigation`; the release's
  `UIWebView` reports that as `WebKitErrorDomain` 101 and the port names it as WebKit does.
- **History.** Going back or forward moves `canGoBack`, `canGoForward` and the back-forward list when the navigation
  starts, and takes the title of the item it goes to before it finishes. A fragment navigation changes the URL and
  sends the decision and nothing else. `backForwardList` has the items, their URLs and titles, and `currentItem`,
  `backItem`, `forwardItem`, `backList`, `forwardList` and `itemAtIndex:`.
- **JavaScript.** `evaluateJavaScript:completionHandler:` answers what WebKit answers for every case of the table in
  `webkit-cases.m`: numbers, strings, booleans, `null` as `NSNull`, `undefined` as `nil`, arrays and objects as
  `NSArray` and `NSDictionary`, dates as `NSDate`, `NaN` and infinities and negative zero as numbers, and a thrown
  exception as `WKErrorDomain` 4, a function, an array that holds one, or an `arguments` object as 5; a function that an object holds is left out of it, and a value that refers to itself comes back as the same cycle, in mutable collections. The script is evaluated in the global scope with
  the completion value of the script, so `var q = 5` is `nil`. The completion handler is called after the call
  returns, on the main queue.
- **Scripts and messages.** A `WKUserScript` at the end of the document runs in the main frame before the
  navigation finishes. `window.webkit.messageHandlers.<name>.postMessage(body)` reaches the handler added with
  `addScriptMessageHandler:name:` with the body as WebKit converts it (strings, numbers, booleans, `null`, arrays,
  dictionaries) and the name and `frameInfo`; messages arrive in the order they were posted; a name nobody added
  throws in the page; adding a name twice raises `NSInvalidArgumentException`; taking a handler away removes
  `window.webkit` from the page.
- **The configuration.** A view copies its configuration, and the copy shares the preferences, the user content
  controller, the process pool and the data store with the original, as the host's does. `WKWebsiteDataStore`
  clears the cookies and the cached responses of the process (`removeDataOfTypes:modifiedSince:`) and has no records
  to list.

## What the port cannot do

- **No document-start injection.** `UIWebView` has no hook before the first script of a page, so a user script at
  `WKUserScriptInjectionTimeAtDocumentStart` runs at the end of the document with the others, and a page whose
  inline scripts post a message while it loads finds no `window.webkit` yet; a message posted afterwards, from an
  event or a timer, arrives. A script for all frames runs in the main frame only.
- **No response policy, no redirects, no authentication, no UI delegate.** `UIWebView` tells its delegate about a
  request before it is made and never about the response, so `decidePolicyForNavigationResponse` is never sent
  (`WKNavigationResponse` is a class nothing hands out); a redirect, an authentication challenge and the death of the
  web content process are not reported; a JavaScript `alert`, `confirm` or `prompt` shows the release's own panel
  and a link that asks for a new window loads in the view, which is how `UIWebView` behaves and was not measured
  here. The registry lists each.
- **Settings the release cannot honour.** `allowsBackForwardNavigationGestures`, `customUserAgent`,
  `allowsLinkPreview`, `javaScriptEnabled`, `minimumFontSize`, `javaScriptCanOpenWindowsAutomatically`,
  `applicationNameForUserAgent`, `ignoresViewportScaleLimits`, `selectionGranularity` and
  `allowsPictureInPictureMediaPlayback` answer what was set and change nothing (`inert`). The media,
  data-detector and incremental-rendering settings are handed to the `UIWebView`.
- **The history is the port's own.** It follows the navigations the view reports, so a page that moves through its
  history with `history.go()` is followed, and a navigation the release does not report is not in it.
- **Progress is an estimate**: 0.1 when a navigation starts, 1 when it finishes.
- **Three records differ from the host's**, and are named in `tests/backports/device/webkit.m`: the scroll view is
  the release's private scroll view of the `UIWebView`; `customUserAgent` is `nil` where the host answers the user
  agent it sends; and the title of a page that has a frame reaches WebKit's view before the navigation finishes,
  which the port cannot see, so it comes just after.
- **`WKNavigation` objects are opaque handles**: each call that loads answers a new one.
- **A load can fail at the release's own limits**: a `file:` URL is read wherever the sandbox lets it, whatever
  `allowingReadAccessToURL:` says, and a message posted from a page travels in a URL, so a body of many hundreds of
  kilobytes is not delivered.

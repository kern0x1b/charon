# Signing in through a web page, iOS 12.0

`ASWebAuthenticationSession` came in iOS 12.0 as the successor of the iOS 11
`SFAuthenticationSession`: an application hands it the address of a login page and
the scheme its own redirect uses, and gets the redirect back as a URL.

Source: AuthenticationServices of the arm64 shared cache of iOS 12.0 -
`-[ASWebAuthenticationSession initWithURL:callbackURLScheme:completionHandler:]`
at `0x1aa076000` and its block at `0x1aa076128`, `-start` at `0x1aa076200`,
`-cancel` at `0x1aa076218`, and the string of the error domain at `0x1aa07c65e`. An
iPad 2 running 6.1.3, with the page and the redirect served from the loopback
address by `tests/backports/device/aswebauth.m`.

## What it is

The class is a wrapper. It holds one `SFAuthenticationSession`, made from the same
URL and scheme with a handler of its own, and `-start` and `-cancel` call the
session's. The handler of the wrapper does one thing to what it is given: the URL
goes on as it is, and if there is an error, whatever its code, the application
gets a new error of `ASWebAuthenticationSessionErrorDomain`
(`com.apple.AuthenticationServices.WebAuthenticationSession`) with the code 1,
`ASWebAuthenticationSessionErrorCodeCanceledLogin`, and no user info. A `nil`
handler is not called.

This package has `SFAuthenticationSession` already, in `libSafariServicesBackports`,
over a page that the `UIWebView` of the release draws in bars of its own, so the
wrapper is the same few lines over it, and it is built with the
`authenticationservices` config, which brings that library.

## Where iOS 6 differs

- iOS 12 starts the session through `-startASWebAuthenticationSession`, a method of
  the wrapped class that this release does not have. `-start` of the session is
  used, the one iOS 11 has. What that method does differently in iOS 12 is not
  read here.
- The session shows the page over the top view controller of the key window, as
  `SFAuthenticationSession` does. There is no system sheet, no
  "wants to use ... to sign in" prompt and no shared login state with Safari, so
  cookies of the page are the application's own.

## Not carried

The credential provider extension and the credential identity store of iOS 12
(`ASCredentialIdentityStore` and its state, `ASCredentialProviderViewController`,
`ASCredentialProviderExtensionContext`, `ASCredentialServiceIdentifier`,
`ASPasswordCredential` and `ASPasswordCredentialIdentity`, with their error
domains) are absent: there is no AutoFill of the system to consult them, and a
password that looked stored would mislead.

## What iOS 13 added to the session

- `presentationContextProvider` is kept and read back, weakly, as the release holds it, and is never asked:
  `presentationAnchorForWebAuthenticationSession:` is not sent. iOS 13 needs the provider to choose which
  window of which scene the page is presented over, and raises when a session is started without one; this
  release runs one application with one window, so the page has one place to go and a session with no
  provider still starts.
- `canStart` answers `YES` until the session has been started or cancelled and `NO` after. It is read from
  the port's own state: `SFAuthenticationSession`, which this session wraps, has nothing to ask. `-start`
  and `-cancel` behave exactly as they did before, and only record that the session has been spent.
- `prefersEphemeralWebBrowserSession` is **not** carried. It is absent rather than kept-and-ignored: the one
  thing the property promises is that the sign-in leaves no trace, and an application told that falsely is
  worse off than one told nothing. `respondsToSelector:` answers NO and the application can see what it is
  not getting.

## Why the ephemeral session is absent, and what it would take

This is written down so that the next person does not start from the beginning and pay the same price.

**The mechanism exists and would work.** This release has exactly one cookie jar per process and no store
per web view: the selector table of 6.1.3 has `_cookieStorage`, `_cf2nsCookies:` and `_ns2cfCookies:`, the
single CFNetwork-to-Foundation bridge, and has no `websiteDataStore`, no `ephemeralDataStore` and no
non-persistent web data store of any kind - the only `nonPersistent` names in the release are about keychain
credentials, not the web. There is therefore nothing for a `UIWebView` to read cookies from except that one
jar, and a session that emptied it would really be isolated from what was there before. The session is
modal and the phone runs one application at a time, so nothing else would be reading the jar meanwhile.

**What stops it is the cost, not the difficulty.** Save-the-jar, empty it, run the sign-in, put it back
makes every cookie the application owns depend on the process living to the end of a web login. On an
iPhone 4S the jetsam ceiling is 282 MB and being killed in the middle of a web view flow is ordinary, not
exotic. The failure is not that the privacy promise is unmet - it is that the user loses every session they
were signed into, in an application that was only trying to be careful. That is worse than not offering the
feature.

**It is fixable, and the fix is a journal.** Write the snapshot of the jar to disk atomically *before*
emptying it, and restore from that journal on the next launch if it is still there. A kill mid-session then
costs a restart, not the cookies. That is the design to build when this is picked up.

**Even with the journal it would be partial, and it must be called that.** The property promises an
ephemeral *browsing session*, not ephemeral cookies: `localStorage`, WebSQL databases and the URL cache are
part of what a sign-in leaves behind, and `UIWebView` keeps those in its own directories rather than in the
cookie jar. Isolating them means snapshotting and restoring those directories too - moving the
application's own web data on every sign-in - so the honest first step carries cookies and the URL cache
and says plainly that local and database storage are not isolated. A port that ships this must not describe
it as an ephemeral session without that sentence.

The work is planned rather than refused. It is not done now because the demand is a single application, the
journal and the measurement need a real `UIWebView` on a device, and that measurement has not been made.

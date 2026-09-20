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

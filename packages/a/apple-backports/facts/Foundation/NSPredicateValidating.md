# NSPredicateValidating and -allowEvaluationWithValidator:error:, iOS 26.4

Two rows of `registry/Foundation/ios26.json` that cannot be written yet, and the measurement that says why.
**Neither name is declared by the only iPhoneOS SDK on this machine**, so the contract is not readable:

    $ SDK=~/.xmake/packages/i/iphoneos-sdk/16.4/*/Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk
    $ grep -rl "NSPredicateValidating" "$SDK" | wc -l
    0
    $ grep -rl "allowEvaluationWithValidator" "$SDK" | wc -l
    0
    $ grep -rl "NSPredicate" "$SDK" | wc -l          # the control: the search does find headers
    95

and two more measurements, which say why no *newer* header can be read here either:

    $ ls ~/.xmake/packages/i/iphoneos-sdk/
    16.4
    $ xcrun --sdk iphoneos --show-sdk-version
    xcrun: error: SDK "iphoneos" cannot be located       # CommandLineTools only, no Xcode on this machine
    $ python3 tools/cache-index/first-rung.py --self-test | grep "rung in the table"
    ok   every rung in the table is held (53 rungs)
    $ ls ~/.charon/dyld | tail -1
    18.0

So: 16.4 declares neither name, 16.4 is the newest iPhoneOS SDK here, and the held release ladder stops at
18.0 - older than this pair, so the release's own metadata cannot say what either name declares either. The
rows' own `source` field read `SDK 26.5, Mac Catalyst, Foundation`, and neither half of that can be
checked from here: there is no 26.5 SDK on this machine, and this package carries iOS releases, so
nothing here could read a Catalyst annotation even if one SDK had it.

What that costs the port:

- `NSPredicateValidating` names a protocol whose **required selector** is the whole contract. Writing it
  from the name would be inventing a method signature, which is the one thing a row must not do.
- `-[NSPredicate allowEvaluationWithValidator:error:]` returns something and takes an `NSError **`. The return
  is `BOOL` by the shape of the name and nothing here confirms it.

Both stay `absent`, and each row's effect says what a program sees: the protocol is not declared, so a class
cannot be said to conform to it and the compiler is told so; the method is not declared, so
`respondsToSelector:` answers NO and an unchecked call raises. **What would close them** is one SDK that
declares the pair. That is a fetch, not an implementation, and it is the whole of what these two rows owe.

This is not the row `NSAllowEvaluation.md` is about, which is the iOS 7 `-allowsEvaluation` of a securely
decoded predicate: there the port is the provider, `registry/Foundation/nz-accessors.json` reads
`implemented` with `maximum: "7.0"`, and that file carries the measurement. These two are the opposite
shape - no provider, no declaration, and no contract to write down.
"""WHICH IOS RELEASE DECLARES A CLASS, read from the SDK's own headers.

One function, because a class's introduction is a property of its DECLARATION and four different
spellings of that declaration exist in these headers:

    API_AVAILABLE(macos(15.4), ios(26.0), tvos(26.0), visionos(26.0)) API_UNAVAILABLE(watchos)
    @interface VTLowLatencyFrameInterpolationConfiguration : NSObject <...>          shape 1, the line above

    /// a documentation block, and a blank line
    API_AVAILABLE(macos(26.0), ios(26.0), tvos(26.0), visionos(26.0)) API_UNAVAILABLE(watchos)
                                                                                   shape 2
    @interface VTTemporalNoiseFilterConfiguration : NSObject <...>

    API_AVAILABLE(macos(15.4), ios(26.0)) API_UNAVAILABLE(tvos, visionos, watchos)
    NS_SWIFT_SENDABLE                                                                    shape 3
    @interface VTFrameRateConversionConfiguration : NSObject <...>

    API_AVAILABLE(macos(26.0), ios(26.0)) API_UNAVAILABLE(visionos) API_UNAVAILABLE(tvos, watchos)
    NS_SWIFT_SENDABLE                                                                    shape 4
    VT_EXPORT @interface VTTemporalNoiseFilterConfiguration : NSObject <...>

Two rules that each covered three of the four failed in OPPOSITE directions: a walk back from the
@interface that skips blanks and comments lands on NS_SWIFT_SENDABLE, and a caller that looks for
"@interface" at the START of a line never sees the VT_EXPORT classes at all. So there is no walk-back and
no anchor: the class is found ANYWHERE in the text, and the availability is the LAST API_AVAILABLE in
the window between the previous declaration and that position - which is why nothing sitting on the
@interface's own line, or between it and the macro, can matter.

And the macro's parentheses are counted, not found by a character class: API_AVAILABLE(macos(15.4), …)
has a ')' of its own inside the argument list, and a [^)]* pattern stops there and never reaches ios().
"""
import re


def find_interface(text, name):
    """Where this class's @interface is - anywhere in the text, because shape 4 prefixes VT_EXPORT."""
    m = re.search(r'@interface\s+' + re.escape(name) + r'\b', text)
    if not m:
        raise ValueError('no @interface ' + name)
    return m.start()


def _balanced(text, start):
    """The parenthesised group beginning at `start`, to its matching ')' - counting depth, because the
    SDK's own availability list carries parentheses of its own."""
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return text[start:i + 1]
    raise ValueError('unbalanced parentheses')


def availability_of(text, name):
    """(ios version, the line the macro is on) for this class, or raise naming it and printing the window."""
    pos = find_interface(text, name)
    head = text[:pos]
    bound = max(head.rfind('@end'), head.rfind('@interface'))
    window = head[bound + 1:]
    hits = [m.start() for m in re.finditer(r'API_AVAILABLE\(', window)]
    if not hits:
        raise ValueError(name + ': no API_AVAILABLE above its @interface; window:\n' + window)
    macro = _balanced(window, hits[-1] + len('API_AVAILABLE'))
    v = re.search(r'\bios\(\s*([0-9]+(?:\.[0-9]+)*)\s*\)', macro)
    if not v:
        raise ValueError(name + ': no ios() in ' + macro)
    line = head[:bound + 1 + hits[-1]].count('\n') + 1
    return v.group(1), line

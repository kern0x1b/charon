//
//  CharonAXMathExpression.m
//  Accessibility
//
//  The fifteen AXMathExpression classes of iOS 18.2, on the object graph the header declares and
//  nothing else. CharonAXMathExpression.h carries the declarations and the two places the header
//  disagrees with itself; the rules this file follows are:
//
//  * **An initialiser stores what it was given and a property answers it unchanged, identity
//    preserved.** There is no validation and no exception: the header's `NS_ASSUME_NONNULL` is a
//    promise the caller makes, not a check the class performs, and the host keeps the promise the
//    same way - a nil content, a nil expression array and a nil string all come back as nil rather
//    than raising (measured on the host's own Accessibility.framework, four cases, none raised).
//  * **Nothing here is parsed and nothing is evaluated.** The application builds the tree; the
//    assistive technology reads it and turns it into speech or Braille. That half is the system's and
//    this release has none, which is why the class is the whole of the work: the value the caller
//    built is the value the system would have been handed.
//  * `isEqual:` is NSObject's own, by identity, because no class in this header declares NSCopying.
//    The host answers the same: two contents built from the same string are not equal (measured).
//

#import "CharonAXMathExpression.h"

#pragma mark - AXMathExpression

// The base class has no state and no member of its own, and this @implementation is what makes it
// exist: a class with no @implementation emits no `_OBJC_CLASS_$_` symbol, so nothing could subclass
// it at link time and the registry's own row for it would read as a name nothing is built. It is
// NSObject's subclass with nothing added, which is what the header declares and what the host answers
// (`[AXMathExpression superclass]` is NSObject, measured).
@implementation AXMathExpression
@end

#pragma mark - the four contents

// Number, Identifier, Operator and Text are the same class with a different name, which is why the
// header writes them out four times: they are the leaves of the graph, and a leaf is a string. Each
// one keeps that string and answers it, so the four are written out rather than shared through a
// class of the port's own - a superclass the SDK does not declare would be a name the release's own
// runtime has never heard of, and the corpus asks for these four classes by name.
#define CHARON_AX_MATH_CONTENT(CLASS)                                                    \
    @implementation CLASS {                                                              \
        NSString *_content;                                                              \
    }                                                                                    \
    - (instancetype)initWithContent:(NSString *)content                                   \
    {                                                                                    \
        self = [super init];                                                             \
        if (self) {                                                                      \
            _content = [content copy];                                                   \
        }                                                                                \
        return self;                                                                     \
    }                                                                                    \
    - (NSString *)content                                                                \
    {                                                                                    \
        return _content;                                                                 \
    }                                                                                    \
    @end

CHARON_AX_MATH_CONTENT(AXMathExpressionNumber)
CHARON_AX_MATH_CONTENT(AXMathExpressionIdentifier)
CHARON_AX_MATH_CONTENT(AXMathExpressionOperator)
CHARON_AX_MATH_CONTENT(AXMathExpressionText)

#pragma mark - AXMathExpressionFenced

@implementation AXMathExpressionFenced {
    NSArray<AXMathExpression *> *_expressions;
    NSString *_openString;
    NSString *_closeString;
}

- (instancetype)initWithExpressions:(NSArray<AXMathExpression *> *)expressions
                         openString:(NSString *)openString
                        closeString:(NSString *)closeString
{
    self = [super init];
    if (self) {
        // Not copied and not retained into a new array: the host answers the very array it was given
        // (measured, `expressions == the array` on the host), and a caller that mutates the array it
        // built sees the mutation here as it would on the host. The property is readonly, so this is
        // not a way to change a built expression - it is the same sharing the host does.
        _expressions = expressions;
        _openString = [openString copy];
        _closeString = [closeString copy];
    }
    return self;
}

- (NSArray<AXMathExpression *> *)expressions
{
    return _expressions;
}

- (NSString *)openString
{
    return _openString;
}

- (NSString *)closeString
{
    return _closeString;
}

@end

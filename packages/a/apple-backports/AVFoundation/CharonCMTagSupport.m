#import "CharonCMTagSupport.h"
#import <CoreMedia/CoreMedia.h>
#include <stdlib.h>
#include <string.h>

// The comparison rules CMTagCollection and CMTaggedBufferGroup both need, in one place.
//
// A C function shared between two backport objects is the trap in charon/AGENTS.md: the band machinery
// keys an object on the API it exports, so an object calling another's public function links a
// dependency between two objects that are dropped independently. Everything here is charon_-prefixed and
// therefore not an API symbol, so the object that compiles this file exports nothing of it and both
// CMTagCollection17.m and CMTaggedBufferGroup17.m can use it without either calling the other.

BOOL charon_tag_equal(CMTag left, CMTag right)
{
    return left.category == right.category && left.dataType == right.dataType && left.value == right.value;
}

BOOL charon_tag_is_less(CMTag left, CMTag right)
{
    if (left.category != right.category)
        return left.category < right.category;
    if (left.dataType != right.dataType)
        return left.dataType < right.dataType;
    return left.value < right.value;
}

// The rule the host's own ContainsSpecifiedTags and the group's six lookups both use: every one of the
// wanted tags is carried. The empty set is carried by everything, and neither argument is dereferenced
// when it is NULL.
BOOL charon_tag_carries(const CMTag *held, CMItemCount heldCount, const CMTag *wanted, CMItemCount wantedCount)
{
    for (CMItemCount index = 0; index < wantedCount; index++) {
        BOOL seen = NO;
        for (CMItemCount other = 0; other < heldCount; other++)
            if (charon_tag_equal(held[other], wanted[index])) {
                seen = YES;
                break;
            }
        if (!seen)
            return NO;
    }
    return YES;
}


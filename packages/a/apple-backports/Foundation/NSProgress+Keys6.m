#import <Foundation/Foundation.h>

// The five NSProgress userInfo keys the release exports from 6.0 (armv7 caches of 6.0-6.1.6: absent; of 7.0: exported, and
// unchanged in the arm64 caches through 18.0, each the string of its own name, read through tools/cfconst.py against the
// 12.0 arm64 cache's Foundation), kept apart from NSProgress+Additions.m's own two constants (7.0, 6.0) so no object mixes a
// release its symbols are present at with one they are not (modules/apple/backports.lua's band(), "split it").
NSProgressUserInfoKey const NSProgressThroughputKey = @"NSProgressThroughputKey";
NSProgressUserInfoKey const NSProgressFileOperationKindKey = @"NSProgressFileOperationKindKey";
NSProgressUserInfoKey const NSProgressFileURLKey = @"NSProgressFileURLKey";
NSProgressUserInfoKey const NSProgressFileTotalCountKey = @"NSProgressFileTotalCountKey";
NSProgressUserInfoKey const NSProgressFileCompletedCountKey = @"NSProgressFileCompletedCountKey";

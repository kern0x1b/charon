#import <Foundation/Foundation.h>

// The order in which a view asks its own drop delegate. It lives in the port, in
// CharonDropSequence11.m, next to the code that asks in that order, so the sequence a test asserts
// and the sequence the routing drives are read from the same place. Swapping two entries there is
// the mutation that must turn the test red.
NSArray *charon_collection_drop_order(void);
NSArray *charon_table_drop_order(void);

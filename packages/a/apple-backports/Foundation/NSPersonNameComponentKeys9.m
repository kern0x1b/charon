#import <Foundation/Foundation.h>

/* The attribute names the person name components formatter writes on the attributed string it hands
   back, and the key those names sit under. Their values are the ones the host's own formatter hands
   out, read through a formatted name: the key is NSPersonNameComponentKey, and the names are
   givenName, familyName, middleName, namePrefix, nameSuffix, nickname and delimiter (measured: an
   annotated name from the host answers exactly these, one run per component and one for the
   separator). None of them is the symbol's own name, which is why they were read. */

/* The eight names the formatter writes, defined in NSPersonNameComponentsFormatter9.m beside the
   code that writes them, and declared here for the rest of the port to import. */
#import "NSPersonNameComponentKeys.h"

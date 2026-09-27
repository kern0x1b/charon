/*
 * The framer calls of iOS 15.4: the options of a framer, which a program can read and write an
 * object value on, and a copy of them.
 *
 * The object values are kept by name beside the numbers, so a value a program sets on the options
 * of a framer is the value it reads back, and the copy a framer hands out is a copy that does not
 * change when the original does.
 */

#import "CharonNW.h"

nw_protocol_options_t nw_framer_copy_options(nw_framer_t framer)
{
    CharonNWFramer *value = (CharonNWFramer *)framer;
    if (!value || !value->_options)
        return NULL;
    CharonNWProtocolOptions *copy = [[CharonNWProtocolOptions alloc] init];
    copy->_definition = value->_options->_definition;
    copy->_values = [value->_options->_values mutableCopy];
    copy->_objects = [value->_options->_objects mutableCopy];
    return copy;
}

void nw_framer_options_set_object_value(nw_protocol_options_t options, const char *key, id value)
{
    CharonNWProtocolOptions *held = (CharonNWProtocolOptions *)options;
    if (!held || !key)
        return;
    if (value)
        held->_objects[@(key)] = value;
    else
        [held->_objects removeObjectForKey:@(key)];
}

id nw_framer_options_copy_object_value(nw_protocol_options_t options, const char *key)
{
    CharonNWProtocolOptions *held = (CharonNWProtocolOptions *)options;
    if (!held || !key)
        return nil;
    return held->_objects[@(key)];
}

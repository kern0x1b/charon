/*
 * The two calls of iOS 26 about an ultra-constrained network: whether a connection may be made over
 * one.
 *
 * A network is ultra-constrained when it is a low-bandwidth link meant only for a device of its own -
 * a Bluetooth LE link, a LoRaWAN gateway - and a program that is not ready for one says so. The
 * release this port builds for has no such network, so no path of it is ever ultra-constrained and a
 * connection is never held back for it, which is the answer the system gives where the network does
 * not exist. A program that allows them still has the flag set, and the connection reads it as it
 * reads every other path setting.
 *
 * The declaration is the port's own: the SDK it compiles against is 16.4, which predates the call,
 * and the flag is the boolean the header of a release that has it says it is.
 */

#import "CharonNW.h"

bool nw_parameters_get_allow_ultra_constrained(nw_parameters_t parameters)
{
    CharonNWParameters *value = (CharonNWParameters *)parameters;
    return value ? value->_allowUltraConstrained : false;
}

void nw_parameters_set_allow_ultra_constrained(nw_parameters_t parameters, bool allow_ultra_constrained)
{
    CharonNWParameters *value = (CharonNWParameters *)parameters;
    if (value)
        value->_allowUltraConstrained = allow_ultra_constrained;
}

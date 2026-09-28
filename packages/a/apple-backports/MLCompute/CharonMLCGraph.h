// What the graph and its engine offer the rest of MLCompute, and what the differential asks of them.
//
// Everything here is named Charon*, so the gate weighs none of it against a release and asks the
// registry about none of it: the graph classes are MLCompute's own API and are in the registry, and the
// engine behind them is the port's own arithmetic. The measurements both are held to are in
// facts/MLCompute/Engine.md.

#pragma once

#import <Foundation/Foundation.h>
#import <MLCompute/MLCompute.h>

// One node of a graph computed on its own: the layer, one source and one result, and the values of the
// result written into the result tensor. YES when the layer is one this path computes. This is what
// CharonMLCElementwise covers today - the activation, which is the one layer with no parameters and no
// shape of its own - and what MLCGraph and MLCInferenceGraph will call once they are written.
BOOL CharonMLCElementwise(MLCLayer *layer, MLCTensor *input, MLCTensor *output);

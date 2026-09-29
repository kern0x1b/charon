// accessibilitychart - the chart and data classes of iOS 15.0 against the host's own.
//
// One source, two programs. The host half links the system's Accessibility.framework and gets Apple's
// classes; the port half is built with every class name remapped to a name the system does not use
// (so renaming one does not rename the system's declaration) and links only Foundation, and its
// classes are the port's own CharonChartDescriptors.m. Each prints "label<TAB>value" per case in the
// same order, and the two outputs are diffed by run.sh.
//
// Nothing printed here is an address: a pointer differs between the two programs and between two runs,
// so every value is a class name, a string, a number or a yes/no. What cannot be compared is not
// printed at all and is named in the script: the live audio graph produces sound, not a value, so
// what is held for its three methods is the shape of the class, which both sides can answer.
//
// AXLiveAudioGraph's three class methods also leave a line in the port's log the first time each is
// used, and a log line is not a value either. run.sh says where it looks for them.

#import <Foundation/Foundation.h>
#import <Accessibility/Accessibility.h>
#import <objc/runtime.h>

// The protocol names are looked up by string, and a string is not remapped by -D, so the port half is
// told its own spelling.
#ifndef AXCHART_PROTOCOL
#define AXCHART_PROTOCOL @"AXChart"
#endif
#ifndef AXDATAAXISDESCRIPTOR_PROTOCOL
#define AXDATAAXISDESCRIPTOR_PROTOCOL @"AXDataAxisDescriptor"
#endif

// The port half is built with every class name remapped to a name the system does not use, so a class
// name is the one thing the two halves cannot share. It is compared by the name both of them agree
// on, which is the one with the port's marker taken off the front - the classes are otherwise the same
// classes, and the rest of every line in this file is the behaviour rather than the spelling.
static NSString *name(NSString *spelling)
{
    if (spelling.length > [@"CharonPort" length] &&
        [[spelling substringToIndex:[@"CharonPort" length]] isEqualToString:@"CharonPort"]) {
        return [spelling substringFromIndex:[@"CharonPort" length]];
    }
    return spelling;
}

// One case per line: a value is folded onto one line before it is printed, because an attributed
// string's description carries the line break its (empty) attributes dictionary prints across two
// lines, and a case that is two lines cannot be lined up with the other side's. What is compared is
// the characters and the attribute dictionary, not where the line broke.
static void say(NSString *label, id value)
{
    NSString *text = [value description] ?: @"(nil)";
    text = [text stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    text = [text stringByReplacingOccurrencesOfString:@"\r" withString:@" "];
    text = [text stringByReplacingOccurrencesOfString:@"\t" withString:@" "];
    while ([text rangeOfString:@"  "].location != NSNotFound) {
        text = [text stringByReplacingOccurrencesOfString:@"  " withString:@" "];
    }
    printf("%s\t%s\n", label.UTF8String, text.UTF8String);
}

static void sayClass(NSString *label, Class value)
{
    say(label, name(NSStringFromClass(value)));
}

static void sayNumber(NSString *label, double value)
{
    printf("%s\t%g\n", label.UTF8String, value);
}

static void sayYes(NSString *label, BOOL value)
{
    printf("%s\t%s\n", label.UTF8String, value ? "yes" : "no");
}

static NSAttributedString *attributed(NSString *text)
{
    return [[NSAttributedString alloc] initWithString:text];
}

static NSString *(^describer(NSString *format))(double)
{
    return ^NSString *(double value) {
        return [NSString stringWithFormat:format, value];
    };
}

int main(void)
{
    @autoreleasepool {
        // --- AXDataPointValue: two independent faces, and the two factories.
        AXDataPointValue *number = [AXDataPointValue valueWithNumber:1.5];
        AXDataPointValue *category = [AXDataPointValue valueWithCategory:@"cat"];
        say(@"value.number.fromNumber", @(number.number));
        say(@"value.category.fromNumber", number.category ?: @"(nil)");
        sayNumber(@"value.number.fromCategory", category.number);
        say(@"value.category.fromCategory", category.category ?: @"(nil)");
        number.category = @"onANumber";
        say(@"value.category.set", number.category);
        sayNumber(@"value.number.afterCategorySet", number.number);
        category.number = 7.5;
        sayNumber(@"value.number.set", category.number);
        say(@"value.category.afterNumberSet", category.category);
        AXDataPointValue *numberCopy = [number copy];
        say(@"value.copy.number", @(numberCopy.number));
        say(@"value.copy.category", numberCopy.category ?: @"(nil)");
        sayClass(@"value.copy.class", [numberCopy class]);

        // --- AXDataPoint: three initialisers, and what each leaves nil.
        AXDataPoint *bare = [[AXDataPoint alloc] initWithX:number y:nil];
        say(@"point.bare.yValue", bare.yValue ? NSStringFromClass([bare.yValue class]) : @"(nil)");
        say(@"point.bare.additionalValues", bare.additionalValues ? @"present" : @"(nil)");
        say(@"point.bare.label", bare.label ?: @"(nil)");
        say(@"point.bare.attributedLabel", bare.attributedLabel ? @"present" : @"(nil)");
        AXDataPoint *withAdditional = [[AXDataPoint alloc] initWithX:number y:category
                                                 additionalValues:@[number, category]];
        say(@"point.withAdditional.count", @(withAdditional.additionalValues.count));
        say(@"point.withAdditional.label", withAdditional.label ?: @"(nil)");
        AXDataPoint *point = [[AXDataPoint alloc] initWithX:number y:category
                                          additionalValues:@[]
                                                     label:@"L"];
        say(@"point.label", point.label);
        say(@"point.attributedLabel", point.attributedLabel);
        point.label = @"L2";
        say(@"point.attributedLabel.afterLabelSet", point.attributedLabel);
        point.attributedLabel = attributed(@"L3");
        say(@"point.label.afterAttributedSet", point.label);
        point.label = nil;
        say(@"point.attributedLabel.afterLabelNilled", point.attributedLabel ? @"present" : @"(nil)");
        point.yValue = nil;
        say(@"point.yValue.nilled", point.yValue ? @"present" : @"(nil)");
        point.additionalValues = @[number];
        say(@"point.additionalValues.set", @(point.additionalValues.count));
        point.additionalValues = nil;
        say(@"point.additionalValues.nilled", point.additionalValues ? @"present" : @"(nil)");
        AXDataPoint *pointCopy = [point copy];
        sayClass(@"point.copy.xValue.class", [pointCopy.xValue class]);
        say(@"point.copy.label", pointCopy.label ?: @"(nil)");

        // --- AXDataSeriesDescriptor: two initialisers, one name in two faces.
        AXDataSeriesDescriptor *series = [[AXDataSeriesDescriptor alloc] initWithName:@"S" isContinuous:YES
                                                                             dataPoints:@[point, bare]];
        say(@"series.name", series.name);
        say(@"series.attributedName", series.attributedName);
        sayYes(@"series.isContinuous", series.isContinuous);
        say(@"series.dataPoints.count", @(series.dataPoints.count));
        AXDataSeriesDescriptor *attributedSeries = [[AXDataSeriesDescriptor alloc] initWithAttributedName:attributed(@"A")
                                                                                            isContinuous:NO
                                                                                               dataPoints:@[]];
        say(@"series.attributed.name", attributedSeries.name);
        say(@"series.attributed.attributedName", attributedSeries.attributedName);
        sayYes(@"series.attributed.isContinuous", attributedSeries.isContinuous);
        say(@"series.attributed.dataPoints.count", @(attributedSeries.dataPoints.count));
        series.name = @"S2";
        say(@"series.attributedName.afterNameSet", series.attributedName);
        series.attributedName = attributed(@"S3");
        say(@"series.name.afterAttributedSet", series.name);
        AXDataSeriesDescriptor *seriesCopy = [series copy];
        say(@"series.copy.name", seriesCopy.name);
        say(@"series.copy.dataPoints.count", @(seriesCopy.dataPoints.count));

        // --- AXNumericDataAxisDescriptor: both initialisers, every property, the block called.
        AXNumericDataAxisDescriptor *numeric = [[AXNumericDataAxisDescriptor alloc] initWithTitle:@"N"
                                                                                    lowerBound:1
                                                                                    upperBound:2
                                                                            gridlinePositions:@[@0, @1]
                                                                    valueDescriptionProvider:describer(@"%.2f")];
        say(@"numeric.title", numeric.title);
        say(@"numeric.attributedTitle", numeric.attributedTitle);
        sayNumber(@"numeric.scaleType", numeric.scaleType);
        sayNumber(@"numeric.lowerBound", numeric.lowerBound);
        sayNumber(@"numeric.upperBound", numeric.upperBound);
        say(@"numeric.gridlinePositions.count", @(numeric.gridlinePositions.count));
        say(@"numeric.valueDescriptionProvider(0.5)", numeric.valueDescriptionProvider(0.5));
        numeric.title = @"N2";
        say(@"numeric.attributedTitle.afterTitleSet", numeric.attributedTitle);
        numeric.attributedTitle = attributed(@"N3");
        say(@"numeric.title.afterAttributedSet", numeric.title);
        numeric.scaleType = 2;
        sayNumber(@"numeric.scaleType.set", numeric.scaleType);
        numeric.lowerBound = -5;
        numeric.upperBound = 5;
        sayNumber(@"numeric.lowerBound.set", numeric.lowerBound);
        sayNumber(@"numeric.upperBound.set", numeric.upperBound);
        numeric.gridlinePositions = @[@(-1), @0, @1];
        say(@"numeric.gridlinePositions.set.count", @(numeric.gridlinePositions.count));
        numeric.gridlinePositions = nil;
        say(@"numeric.gridlinePositions.nilled", numeric.gridlinePositions ? @"present" : @"(nil)");
        numeric.valueDescriptionProvider = describer(@"%.3f");
        say(@"numeric.valueDescriptionProvider.set(0.5)", numeric.valueDescriptionProvider(0.5));
        AXNumericDataAxisDescriptor *numericNoGridlines = [[AXNumericDataAxisDescriptor alloc]
            initWithAttributedTitle:attributed(@"M") lowerBound:0 upperBound:0 gridlinePositions:nil
               valueDescriptionProvider:describer(@"%.1f")];
        say(@"numericNoGridlines.title", numericNoGridlines.title);
        say(@"numericNoGridlines.gridlinePositions", numericNoGridlines.gridlinePositions ? @"present" : @"(nil)");
        sayNumber(@"numericNoGridlines.lowerBound", numericNoGridlines.lowerBound);
        AXNumericDataAxisDescriptor *numericCopy = [numeric copy];
        say(@"numeric.copy.title", numericCopy.title);
        say(@"numeric.copy.scaleType", @(numericCopy.scaleType));
        say(@"numeric.copy.lowerBound", @(numericCopy.lowerBound));
        say(@"numeric.copy.gridlinePositions.count", @(numericCopy.gridlinePositions.count));
        say(@"numeric.copy.valueDescriptionProvider(0.5)", numericCopy.valueDescriptionProvider(0.5));

        // --- AXCategoricalDataAxisDescriptor: both initialisers, the order, the copy.
        AXCategoricalDataAxisDescriptor *ordered = [[AXCategoricalDataAxisDescriptor alloc] initWithTitle:@"C"
                                                                                            categoryOrder:@[@"a", @"b"]];
        say(@"categorical.title", ordered.title);
        say(@"categorical.attributedTitle", ordered.attributedTitle);
        say(@"categorical.categoryOrder.count", @(ordered.categoryOrder.count));
        say(@"categorical.categoryOrder.first", ordered.categoryOrder.firstObject);
        AXCategoricalDataAxisDescriptor *attributedOrdered = [[AXCategoricalDataAxisDescriptor alloc]
            initWithAttributedTitle:attributed(@"D") categoryOrder:@[@"x"]];
        say(@"categorical.attributed.title", attributedOrdered.title);
        say(@"categorical.attributed.order.count", @(attributedOrdered.categoryOrder.count));
        ordered.categoryOrder = @[@"a", @"b", @"c"];
        say(@"categorical.categoryOrder.set.count", @(ordered.categoryOrder.count));
        AXCategoricalDataAxisDescriptor *orderedCopy = [ordered copy];
        say(@"categorical.copy.order.count", @(orderedCopy.categoryOrder.count));

        // --- AXChartDescriptor: the four initialisers, and the two values none of them takes.
        AXChartDescriptor *chart = [[AXChartDescriptor alloc] initWithTitle:@"Ch" summary:@"S"
                                                            xAxisDescriptor:ordered
                                                           yAxisDescriptor:numeric
                                                                      series:@[series]];
        say(@"chart.title", chart.title);
        say(@"chart.attributedTitle", chart.attributedTitle);
        say(@"chart.summary", chart.summary);
        sayNumber(@"chart.contentDirection", chart.contentDirection);
        say(@"chart.contentFrame", NSStringFromRect(chart.contentFrame));
        say(@"chart.series.count", @(chart.series.count));
        sayClass(@"chart.xAxis.class", object_getClass(chart.xAxis));
        sayClass(@"chart.yAxis.class", object_getClass(chart.yAxis));
        say(@"chart.additionalAxes", chart.additionalAxes ? @"present" : @"(nil)");
        chart.title = @"Ch2";
        say(@"chart.attributedTitle.afterTitleSet", chart.attributedTitle);
        chart.attributedTitle = attributed(@"Ch3");
        say(@"chart.title.afterAttributedSet", chart.title);
        chart.title = nil;
        say(@"chart.attributedTitle.afterTitleNilled", chart.attributedTitle ? @"present" : @"(nil)");
        chart.summary = @"S2";
        say(@"chart.summary.set", chart.summary);
        chart.summary = nil;
        say(@"chart.summary.nilled", chart.summary ?: @"(nil)");
        chart.contentDirection = 5;
        sayNumber(@"chart.contentDirection.set", chart.contentDirection);
        chart.contentFrame = CGRectMake(1, 2, 3, 4);
        say(@"chart.contentFrame.set", NSStringFromRect(chart.contentFrame));
        chart.series = @[attributedSeries];
        say(@"chart.series.set.count", @(chart.series.count));
        chart.series = nil;
        say(@"chart.series.nilled", chart.series ? @"present" : @"(nil)");
        chart.xAxis = numeric;
        sayClass(@"chart.xAxis.afterSet.class", object_getClass(chart.xAxis));
        chart.yAxis = numeric;
        sayClass(@"chart.yAxis.afterSet.class", object_getClass(chart.yAxis));
        chart.additionalAxes = @[ordered, numeric];
        say(@"chart.additionalAxes.set.count", @(chart.additionalAxes.count));
        chart.additionalAxes = nil;
        say(@"chart.additionalAxes.nilled", chart.additionalAxes ? @"present" : @"(nil)");
        AXChartDescriptor *attributedChart = [[AXChartDescriptor alloc] initWithAttributedTitle:attributed(@"AC")
                                                                                       summary:@"AS"
                                                                              xAxisDescriptor:numeric
                                                                             yAxisDescriptor:numeric
                                                                             additionalAxes:@[ordered]
                                                                                        series:@[attributedSeries]];
        say(@"chart.attributed.title", attributedChart.title);
        say(@"chart.attributed.attributedTitle", attributedChart.attributedTitle);
        say(@"chart.attributed.additionalAxes.count", @(attributedChart.additionalAxes.count));
        say(@"chart.attributed.series.count", @(attributedChart.series.count));
        AXChartDescriptor *axesChart = [[AXChartDescriptor alloc] initWithTitle:@"AC" summary:nil
                                                              xAxisDescriptor:ordered yAxisDescriptor:numeric
                                                             additionalAxes:@[ordered, numeric] series:@[]];
        say(@"chart.axes.additionalAxes.count", @(axesChart.additionalAxes.count));
        say(@"chart.axes.summary", axesChart.summary ?: @"(nil)");
        say(@"chart.axes.series.count", @(axesChart.series.count));
        AXChartDescriptor *chartCopy = [chart copy];
        say(@"chart.copy.title", chartCopy.title);
        say(@"chart.copy.series.count", @(chartCopy.series.count));
        sayClass(@"chart.copy.xAxis.class", object_getClass(chartCopy.xAxis));
        say(@"chart.copy.contentDirection", @(chartCopy.contentDirection));
        say(@"chart.copy.contentFrame", NSStringFromRect(chartCopy.contentFrame));

        // --- The two protocols: the declaration itself, and the members it names.
        Protocol *chartProtocol = objc_getProtocol(AXCHART_PROTOCOL.UTF8String);
        say(@"protocol.AXChart.found", chartProtocol ? @"yes" : @"no");
        say(@"protocol.AXChart.name", name([NSString stringWithUTF8String:protocol_getName(chartProtocol)]));
        if (chartProtocol) {
            unsigned count = 0;
            struct objc_method_description *members = protocol_copyMethodDescriptionList(chartProtocol, YES, YES, &count);
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned i = 0; i < count; i++) [names addObject:NSStringFromSelector(members[i].name)];
            [names sortUsingSelector:@selector(compare:)];
            // Sorted and numbered, so each member is a case of its own and the order is the same on
            // both sides; a repeated label would leave the two outputs impossible to line up.
            for (unsigned i = 0; i < names.count; i++)
                say([NSString stringWithFormat:@"protocol.AXChart.member.%u", i], names[i]);
            free(members);
        }
        Protocol *axisProtocol = objc_getProtocol(AXDATAAXISDESCRIPTOR_PROTOCOL.UTF8String);
        say(@"protocol.AXDataAxisDescriptor.found", axisProtocol ? @"yes" : @"no");
        sayYes(@"protocol.AXDataAxisDescriptor.adoptsNSCopying",
               protocol_conformsToProtocol(axisProtocol, @protocol(NSCopying)));
        if (axisProtocol) {
            unsigned count = 0;
            struct objc_method_description *members = protocol_copyMethodDescriptionList(axisProtocol, YES, YES, &count);
            NSMutableArray *names = [NSMutableArray array];
            for (unsigned i = 0; i < count; i++) [names addObject:NSStringFromSelector(members[i].name)];
            [names sortUsingSelector:@selector(compare:)];
            for (unsigned i = 0; i < names.count; i++)
                say([NSString stringWithFormat:@"protocol.AXDataAxisDescriptor.member.%u", i], names[i]);
            free(members);
        }
        // The two axis classes of the port answer the protocol's own members, so the two are held
        // together here rather than only through the class's own property names.
        id<AXDataAxisDescriptor> asProtocol = numeric;
        say(@"protocol.AXDataAxisDescriptor.title", asProtocol.title);
        say(@"protocol.AXDataAxisDescriptor.attributedTitle", asProtocol.attributedTitle);
        sayYes(@"protocol.AXDataAxisDescriptor.conforms",
               [numeric conformsToProtocol:@protocol(AXDataAxisDescriptor)]);

        // --- AXLiveAudioGraph: the shape of the class, and that its three calls do not raise.
        // The values it publishes are sound, which a program cannot read, so nothing about them is
        // compared; what is compared is the class both sides expose and the absence of any state.
        sayYes(@"graph.start.isClassMethod", class_getClassMethod([AXLiveAudioGraph class], @selector(start)) != NULL);
        sayYes(@"graph.updateValue.isClassMethod",
               class_getClassMethod([AXLiveAudioGraph class], @selector(updateValue:)) != NULL);
        sayYes(@"graph.stop.isClassMethod", class_getClassMethod([AXLiveAudioGraph class], @selector(stop)) != NULL);
        unsigned ivars = 0;
        class_copyIvarList([AXLiveAudioGraph class], &ivars);
        say(@"graph.ivarCount", @(ivars));
        say(@"graph.instanceSize", @(class_getInstanceSize([AXLiveAudioGraph class])));
        sayClass(@"graph.instance.class", [[[AXLiveAudioGraph alloc] init] class]);
        [AXLiveAudioGraph start];
        [AXLiveAudioGraph start];
        [AXLiveAudioGraph updateValue:0.0];
        [AXLiveAudioGraph updateValue:0.5];
        [AXLiveAudioGraph updateValue:2.0];
        [AXLiveAudioGraph stop];
        [AXLiveAudioGraph updateValue:0.25];
        say(@"graph.calls.survived", @"yes");

        // --- The seven classes the registry rows name are all there, under the name both halves use.
        // A lookup by string would be nil in the port half, whose classes are the port's own names, so
        // the class object itself is what is named here and the lookup is on the other side of the gate
        // (the registry check reads the classes out of the built objects).
        sayClass(@"class.AXChartDescriptor", [AXChartDescriptor class]);
        sayClass(@"class.AXDataSeriesDescriptor", [AXDataSeriesDescriptor class]);
        sayClass(@"class.AXDataPoint", [AXDataPoint class]);
        sayClass(@"class.AXDataPointValue", [AXDataPointValue class]);
        sayClass(@"class.AXNumericDataAxisDescriptor", [AXNumericDataAxisDescriptor class]);
        sayClass(@"class.AXCategoricalDataAxisDescriptor", [AXCategoricalDataAxisDescriptor class]);
        sayClass(@"class.AXLiveAudioGraph", [AXLiveAudioGraph class]);
        say(@"class.superclass.AXChartDescriptor", [NSStringFromClass([AXChartDescriptor superclass]) copy]);
        say(@"class.superclass.AXDataPointValue", [NSStringFromClass([AXDataPointValue superclass]) copy]);
        say(@"class.superclass.AXLiveAudioGraph", [NSStringFromClass([AXLiveAudioGraph superclass]) copy]);
        sayYes(@"class.copies.AXChartDescriptor",
               [[AXChartDescriptor class] instancesRespondToSelector:@selector(copyWithZone:)]);
        sayYes(@"class.copies.AXDataPointValue",
               [[AXDataPointValue class] instancesRespondToSelector:@selector(copyWithZone:)]);
        sayYes(@"class.adopts.AXNumericDataAxisDescriptor",
               [[AXNumericDataAxisDescriptor class] conformsToProtocol:@protocol(AXDataAxisDescriptor)]);
        sayYes(@"class.adopts.AXCategoricalDataAxisDescriptor",
               [[AXCategoricalDataAxisDescriptor class] conformsToProtocol:@protocol(AXDataAxisDescriptor)]);
    }
    return 0;
}

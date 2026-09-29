#!/bin/sh
# accessibilitychart/mutants.sh - every mutant of the chart and data classes has to be told apart by
# the differential of run.sh.
#
# A differential that examines nothing says it passed, and a mutant that stops the build says nothing
# either. So each mutant here changes one line of the port's own source in a copy of it, rebuilds the
# case against that copy, and has to be held by one of the comparison's own verdicts - an undeclared
# difference, or a declared one that moved. A mutant that survives, and a mutant that dies of a build
# error, are both failures of the case, and the script exits on the count of each.
#
# The rules each mutant breaks, in the order of the file:
#   M1  a value built for a category answers 1 for its number, where the measured answer is 0
#   M2  a value built for a number answers an empty string for its category, where it answers nil
#   M3  setting a title leaves the attributed face of it behind
#   M4  the two-argument data point initialiser answers an empty array for its additional values,
#       where the measured answer is nil
#   M5  a copy of a chart does not carry the direction it was set to
#   M6  a numeric axis answers the same string for every value, where it calls the caller's block
#   M7  the live audio graph holds an ivar, where the host's instance has none
#   M8  the categorical axis' order is the reverse of what it was given
#
# Usage: sh tests/backports/host/accessibilitychart/mutants.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
package=$root/packages/a/apple-backports
sources=${ACCESSIBILITY_SRC:-$package/Accessibility}
work=${BUILD:-${TMPDIR:-/tmp}/charon-accessibilitychart-mutants}
rm -rf "$work"
mkdir -p "$work"
survived=0
ran=0
killed=0
died_wrong=0

mutant() {
    # name, which occurrence of the line, the line, what it becomes
    name=$1
    nth=$2
    old=$3
    new=$4
    if [ -z "$nth" ]; then
        echo "mutant $name does not say which occurrence of its line it changes" >&2
        return 1
    fi
    dir="$work/$name"
    # The copy keeps the package's own shape, because the source reaches its header by a relative path
    # (../CharonSayOnce.h). A copy that did not would stop the build, and a mutant that dies of a build
    # error has told nobody anything - which is what the kill below insists on.
    mkdir -p "$dir/pkg/Accessibility"
    cp "$sources/CharonChartDescriptors.m" "$dir/pkg/Accessibility/"
    cp "$package/CharonSayOnce.h" "$dir/pkg/"
    MUTATE="$dir/pkg/Accessibility/CharonChartDescriptors.m" MUTATE_OLD="$old" MUTATE_NEW="$new" \
        MUTATE_NTH="$nth" python3 "$here/mutate.py"
    ran=$((ran + 1))
    if ACCESSIBILITY_SRC="$dir/pkg/Accessibility" BUILD="$dir/build" sh "$here/run.sh" > "$dir/out.txt" 2>&1; then
        echo "MUTANT SURVIVED: $name"
        survived=$((survived + 1))
        return 0
    fi
    reason=$(grep -m1 -E 'UNDECLARED DIFFERENCE|DECLARED DIFFERENCE' "$dir/out.txt" || true)
    if [ -z "$reason" ]; then
        echo "MUTANT DIED FOR THE WRONG REASON: $name"
        tail -5 "$dir/out.txt"
        died_wrong=$((died_wrong + 1))
        return 0
    fi
    killed=$((killed + 1))
    echo "killed: $name: $reason"
}

mutant M1-category-number 1 \
    '    AXDataPointValue *value = [[AXDataPointValue alloc] init];
    value->_category = [category copy];' \
    '    AXDataPointValue *value = [[AXDataPointValue alloc] init];
    value->_number = 1;
    value->_category = [category copy];'

mutant M2-number-category 1 \
    '    AXDataPointValue *value = [[AXDataPointValue alloc] init];
    value->_number = number;' \
    '    AXDataPointValue *value = [[AXDataPointValue alloc] init];
    value->_number = number;
    value->_category = @"";'

# The same two lines are the title setter of the numeric axis, the categorical axis and the chart, so
# the mutant says which one it changes: the chart's, which is the third of them in the file.
mutant M3-title-faces 3 \
    '    _title = [title copy];
    _attributedTitle = title ? [[NSAttributedString alloc] initWithString:title] : nil;' \
    '    _title = [title copy];'

mutant M4-point-additional 1 \
    '    return [self initWithX:xValue y:yValue additionalValues:nil label:nil];' \
    '    return [self initWithX:xValue y:yValue additionalValues:@[] label:nil];'

mutant M5-chart-copy-direction 1 \
    '    copy->_contentDirection = _contentDirection;' \
    '    copy->_contentDirection = 0;'

# The caller's block is kept and called with the value it was given, so the mutant answers a constant
# instead. It is a block and not a nil: calling a nil block is a crash, and a mutant that dies of a
# crash has told the case nothing about the answer.
mutant M6-value-description 1 \
    '- (NSString *(^)(double))valueDescriptionProvider
{
    return _valueDescriptionProvider;
}' \
    '- (NSString *(^)(double))valueDescriptionProvider
{
    NSString *(^held)(double) = ^NSString *(double value) { return @"0"; };
    return held;
}'

mutant M7-graph-ivar 1 \
    '@implementation AXLiveAudioGraph

+ (void)start' \
    '@implementation AXLiveAudioGraph {
    int _held;
}

+ (void)start'

mutant M8-category-order 1 \
    '        _categoryOrder = [categoryOrder copy];
    }
    return self;
}

- (instancetype)initWithAttributedTitle:(NSAttributedString *)attributedTitle
                          categoryOrder:' \
    '        _categoryOrder = [[categoryOrder reverseObjectEnumerator] allObjects];
    }
    return self;
}

- (instancetype)initWithAttributedTitle:(NSAttributedString *)attributedTitle
                          categoryOrder:'

echo "mutants run: $ran, killed by the comparison: $killed, died for another reason: $died_wrong, survived: $survived"
[ "$survived" -eq 0 ] && [ "$died_wrong" -eq 0 ] && [ "$killed" -eq "$ran" ]

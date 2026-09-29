#!/usr/bin/env python3
"""The floor a fit's sample has to clear, in one place, because two fits read the same sample.

Both fits under this directory read the same file and both have to agree about whether it is a
measurement or not, and a disagreement between two copies of this decision would be silent: one fit
would refuse a sample, print its refusal and exit 1, the other would carry on and print a verdict of
it, and the runner - which stops on the first failure - would never see the two disagree. So the floor
lives here once and both fits import it.

The floor is the grid's own row count and nothing more. The probe writes a 17x17x17 sRGB grid first,
so a sample smaller than that is truncated or is not a fit sample at all, and every figure either fit
prints is over a sample of at least this size. A larger sample is not refused, and a large but
degenerate one - the right number of rows and the wrong contents - is caught by the known-answer
check in run.sh rather than here, because that is a question about the contents and this one is about
the size.

    GRID_ROWS, sample_rows(path), refuse_small_sample(path) -> bool
"""

GRID_ROWS = 17 * 17 * 17


def sample_rows(path):
    """How many rows of answers the sample holds.

    A row of answers is a line of five tab-separated fields - the kind, the three channels and the name -
    and the count is of those, not of lines. Counting lines instead let a file of nothing at all clear
    the floor and then kill both fits with a ValueError where they unpack a line, which is the same shape
    as the divide-by-zero this floor replaced, reached through a different door. The probe's own header
    line is not a row either, and neither is anything else that does not parse as one.
    """
    count = 0
    for line in open(path):
        if line.startswith("#"):
            continue
        if len(line.rstrip("\n").split("\t")) == 5:
            count += 1
    return count


def refuse_small_sample(path):
    """False, with the reason on stdout, when the sample is too small for anything below it to count."""
    rows = sample_rows(path)
    if rows < GRID_ROWS:
        print("refused: this sample has %d rows and the grid alone is %d, so nothing below is a "
              "measurement" % (rows, GRID_ROWS))
        return False
    return True

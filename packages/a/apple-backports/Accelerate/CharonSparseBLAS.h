// The storage behind every sparse_matrix_float and sparse_matrix_double of vecLib/Sparse/BLAS.h, and
// the arithmetic the sparse_* entry points are made of.
//
// The two types are opaque in the header (`typedef struct sparse_m_float *sparse_matrix_float`), so
// completing them here is what the header leaves to an implementation. One shape of row, kept sorted
// by column, for both scalar types: a sparse matrix of this library is exactly a list of rows of
// (column, value) pairs, and every operation below is expressed on that, which is what makes a
// per-row BLAS call possible.
//
// The two structures have one layout, and a static assertion says so, because every helper below
// reads a matrix through one of them: what a value is differs, and the element size says which.
//
// Every name here carries a Charon prefix or is static, so the gate weighs none of it against a
// release or asks the registry about it (modules/apple/backports.lua, internal_symbol).

#pragma once

#import <Accelerate/Accelerate.h>
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// A row of a sparse matrix: the columns of its stored entries in ascending order, and their values.
// Both arrays are one allocation each, so a row is freed in one step and a shift is one memmove.
typedef struct CharonSparseRow {
    sparse_index count;
    sparse_index capacity;
    sparse_index *column;
    void *value;
} CharonSparseRow;

// The body both matrix types share. rows and columns count elements, not blocks: measured on the
// host, a matrix built by sparse_matrix_block_create_float(3, 3, 2, 2) reports 6 rows and 6 columns.
#define CHARON_SPARSE_MATRIX_BODY                                                                              \
    uint32_t magic;                                                                                            \
    sparse_dimension rows;                                                                                      \
    sparse_dimension columns;                                                                                   \
    sparse_index blockRows;                                                                                     \
    sparse_index blockColumns;                                                                                  \
    sparse_dimension *blockHeight; /* blockRows of them, for a block matrix, NULL for a point-wise one */       \
    sparse_dimension *blockWidth;  /* blockColumns of them */                                                   \
    long property;                                                                                             \
    int inserted;                                                                                              \
    long nonzero;                                                                                              \
    CharonSparseRow *row; /* rows of them, each sorted by column */

struct sparse_m_float {
    CHARON_SPARSE_MATRIX_BODY
};

struct sparse_m_double {
    CHARON_SPARSE_MATRIX_BODY
};

// The two complex matrix types of Sparse/Types.h carry the same body, so that one row, one search and
// one growth serve all four, and so that the entry points the header takes a void * matrix for - the
// counts, the block dimensions, the properties, the commit and the destroy - accept a complex matrix on
// the same terms as a real one. Their magic words are the two below and say which of the four it is.
struct sparse_m_float_complex {
    CHARON_SPARSE_MATRIX_BODY
};

struct sparse_m_double_complex {
    CHARON_SPARSE_MATRIX_BODY
};

// The four bytes every matrix of ours begins with, one per scalar type. A pointer handed to one of
// these entry points that does not begin with them is not a matrix this port made - a stale pointer,
// a foreign object, or a matrix already destroyed - and is answered with the status the header names
// for an argument that is not a matrix rather than read. That is the same answer a NULL gets,
// measured on the host for every entry point of the family that checks.
#define CHARON_SPARSE_MAGIC_FLOAT 0x53504630u
#define CHARON_SPARSE_MAGIC_DOUBLE 0x53504644u
#define CHARON_SPARSE_MAGIC_FLOAT_COMPLEX 0x53504643u
#define CHARON_SPARSE_MAGIC_DOUBLE_COMPLEX 0x53504645u

static inline int CharonSparseIsMatrix(const void *matrix, uint32_t magic)
{
    return matrix && ((const struct sparse_m_float *)matrix)->magic == magic;
}

static inline int CharonSparseIsFloat(const void *matrix)
{
    return CharonSparseIsMatrix(matrix, CHARON_SPARSE_MAGIC_FLOAT);
}

static inline int CharonSparseIsDouble(const void *matrix)
{
    return CharonSparseIsMatrix(matrix, CHARON_SPARSE_MAGIC_DOUBLE);
}

static inline int CharonSparseIsFloatComplex(const void *matrix)
{
    return CharonSparseIsMatrix(matrix, CHARON_SPARSE_MAGIC_FLOAT_COMPLEX);
}

static inline int CharonSparseIsDoubleComplex(const void *matrix)
{
    return CharonSparseIsMatrix(matrix, CHARON_SPARSE_MAGIC_DOUBLE_COMPLEX);
}

// Any of the four. The entry points the header takes a void * matrix for answer on a matrix of any of
// them, because what they report - a count, a shape, a property, the commit, the destroy - does not
// depend on the type of the values.
static inline int CharonSparseIsAny(const void *matrix)
{
    return CharonSparseIsFloat(matrix) || CharonSparseIsDouble(matrix) || CharonSparseIsFloatComplex(matrix) ||
           CharonSparseIsDoubleComplex(matrix);
}

// The element of a dense matrix in the caller's own layout, so one loop covers both orders: a
// row-major matrix steps by one along a row, a column-major one by its leading dimension. It lives here
// and not in one of the two object files because both of them need it, and a function defined in a file
// that exports an API symbol is left out of a band the release already has, which is how a shared C
// function becomes an undefined symbol in a later band.
static inline long CharonSparseDenseAt(int order, sparse_dimension leading, sparse_dimension row, sparse_dimension column)
{
    return order == CblasRowMajor ? (long)(row * leading + column) : (long)(column * leading + row);
}

// The first stored column of a row that is not below the one looked for: where an entry for that
// column belongs, and where the search for it stops.
static inline sparse_index CharonSparseSearch(const CharonSparseRow *row, sparse_index column)
{
    sparse_index low = 0, high = row->count;
    while (low < high) {
        sparse_index middle = low + (high - low) / 2;
        if (row->column[middle] < column) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return low;
}

static inline int CharonSparseGrow(CharonSparseRow *row, sparse_index wanted, size_t size)
{
    if (wanted <= row->capacity) {
        return 1;
    }
    sparse_index capacity = row->capacity ? row->capacity : 4;
    while (capacity < wanted) {
        capacity *= 2;
    }
    sparse_index *column = (sparse_index *)realloc(row->column, (size_t)capacity * sizeof(sparse_index));
    if (!column) {
        return 0;
    }
    void *value = realloc(row->value, (size_t)capacity * size);
    if (!value) {
        free(column);
        return 0;
    }
    row->column = column;
    row->value = value;
    row->capacity = capacity;
    return 1;
}

// A[i, j] = value: an entry that is already there is replaced, a new one is put in its place in the
// row's order. A value of exactly zero is stored - measured on the host, inserting 0.0 into an empty
// matrix leaves its nonzero count at 1, and so does inserting over it - so a stored entry and a
// nonzero value are two different things and the count counts entries.
static inline sparse_status CharonSparsePut(CharonSparseRow *row, sparse_index column, double value, size_t size)
{
    sparse_index at = CharonSparseSearch(row, column);
    if (at < row->count && row->column[at] == column) {
        if (size == sizeof(float)) {
            ((float *)row->value)[at] = (float)value;
        } else {
            ((double *)row->value)[at] = value;
        }
        return SPARSE_SUCCESS;
    }
    if (!CharonSparseGrow(row, row->count + 1, size)) {
        return SPARSE_SYSTEM_ERROR;
    }
    memmove(row->column + at + 1, row->column + at, (size_t)(row->count - at) * sizeof(sparse_index));
    memmove((char *)row->value + (size_t)(at + 1) * size, (char *)row->value + (size_t)at * size,
            (size_t)(row->count - at) * size);
    row->column[at] = column;
    if (size == sizeof(float)) {
        ((float *)row->value)[at] = (float)value;
    } else {
        ((double *)row->value)[at] = value;
    }
    row->count++;
    return SPARSE_SUCCESS;
}

// The two complex matrix types below carry the same body, so a row, a search and a growth serve all four
// scalar types: what differs between them is the width a value occupies, and that is the last argument.

// A[i, j], read: the stored value, or zero for a column the row does not hold. A matrix of this
// library treats a column it has nothing for as a zero, which is what every operation below relies
// on and what the host's own answers show (a row with no entry in a column contributes nothing to a
// product and reads as a zero from a block extraction).
static inline double CharonSparseElementAt(const CharonSparseRow *row, sparse_index column, size_t size)
{
    sparse_index at = CharonSparseSearch(row, column);
    if (at >= row->count || row->column[at] != column) {
        return 0.0;
    }
    return size == sizeof(float) ? (double)((const float *)row->value)[at] : ((const double *)row->value)[at];
}

// The height of the block that holds element row, from the block heights and how many blocks there
// are. Measured on the host for a variable-block matrix built with row heights {2, 1, 3} and column
// widths {1, 2, 1}: sparse_get_block_dimension_for_row answers 2, 2, 1 for rows 0, 1 and 2, which is
// the height of the block the row is in and not the height of the block row i names, and 0 for a row
// past the last, for a point-wise matrix and for a NULL.
static inline sparse_dimension CharonSparseBlockAt(const sparse_dimension *sizes, sparse_index blocks, sparse_index element)
{
    sparse_dimension sum = 0;
    for (sparse_index b = 0; b < blocks; b++) {
        sum += sizes[b];
        if (element < sum) {
            return sizes[b];
        }
    }
    return 0;
}

/* A Core ML model read from its container: which kind of model it is, what its features are,
 * and the set of values a prediction is made from and answered in.
 *
 * The description is read out of the specification's own fields, so what a model says about
 * its inputs and outputs is what the model says -- not a guess from the layers, and not the
 * shape a particular converter happens to write.
 */
#ifndef CHARON_ML_MODEL_H
#define CHARON_ML_MODEL_H

#include <stddef.h>

#include "CharonMLProto.h"
#include "CharonMLValue.h"

/* The kinds of model the specification's Type oneof holds, by the name the specification gives
 * each case. A model is exactly one of them, and the interpreter dispatches on that name. */
typedef enum {
    CHARON_ML_KIND_NONE = 0,
    CHARON_ML_KIND_PIPELINE,
    CHARON_ML_KIND_PIPELINE_CLASSIFIER,
    CHARON_ML_KIND_PIPELINE_REGRESSOR,
    CHARON_ML_KIND_NEURAL_NETWORK,
    CHARON_ML_KIND_NEURAL_NETWORK_CLASSIFIER,
    CHARON_ML_KIND_NEURAL_NETWORK_REGRESSOR,
    CHARON_ML_KIND_TREE_ENSEMBLE_CLASSIFIER,
    CHARON_ML_KIND_TREE_ENSEMBLE_REGRESSOR,
    CHARON_ML_KIND_GLM_CLASSIFIER,
    CHARON_ML_KIND_GLM_REGRESSOR,
    CHARON_ML_KIND_SVM_CLASSIFIER,
    CHARON_ML_KIND_SVM_REGRESSOR,
    CHARON_ML_KIND_KNN_CLASSIFIER,
    CHARON_ML_KIND_ITEM_SIMILARITY,
    CHARON_ML_KIND_SCALER,
    CHARON_ML_KIND_IMPUTER,
    CHARON_ML_KIND_NORMALIZER,
    CHARON_ML_KIND_ONE_HOT_ENCODER,
    CHARON_ML_KIND_DICT_VECTORIZER,
    CHARON_ML_KIND_FEATURE_VECTORIZER,
    CHARON_ML_KIND_CATEGORICAL_MAPPING,
    CHARON_ML_KIND_ARRAY_FEATURE_EXTRACTOR,
    CHARON_ML_KIND_NON_MAXIMUM_SUPPRESSION,
    CHARON_ML_KIND_IDENTITY,
    CHARON_ML_KIND_MIL_PROGRAM,
    CHARON_ML_KIND_OTHER
} charon_ml_model_kind;

/* The feature types the specification's FeatureType oneof holds. */
typedef enum {
    CHARON_ML_FEATURE_NONE = 0,
    CHARON_ML_FEATURE_INT64,
    CHARON_ML_FEATURE_DOUBLE,
    CHARON_ML_FEATURE_STRING,
    CHARON_ML_FEATURE_IMAGE,
    CHARON_ML_FEATURE_MULTI_ARRAY,
    CHARON_ML_FEATURE_DICTIONARY,
    CHARON_ML_FEATURE_SEQUENCE,
    CHARON_ML_FEATURE_STATE
} charon_ml_feature_type;

/* The colour spaces the specification's ImageFeatureType.ColorSpace names. */
enum {
    CHARON_ML_COLOR_INVALID = 0,
    CHARON_ML_COLOR_GRAYSCALE = 10,
    CHARON_ML_COLOR_RGB = 20,
    CHARON_ML_COLOR_BGR = 30,
    CHARON_ML_COLOR_GRAYSCALE_FLOAT16 = 40
};

#define CHARON_ML_MAX_FEATURES 256

typedef struct {
    char *name;
    char *short_description;
    charon_ml_feature_type type;
    int optional;
    /* A multiArray, and an image, each of which the specification describes by a shape, a
     * range of shapes, or a list of the shapes it may take. All three are kept: a range
     * whose upper bound is -1 is the specification's "flexible", and a caller asking for the
     * shape of a feature has to be able to tell that from a shape. */
    int data_type;                 /* CHARON_ML_ARRAY_* for a multiArray */
    int rank;                      /* the dimensions a shape has, 0 when it has none */
    int64_t shape[8];              /* the one shape, CHARON_ML_FLEXIBLE for a flexible dim */
    int64_t shape_range[8][2];     /* per dimension: least and most, -1 for no upper bound */
    int has_shape_range;
    int image_width, image_height;
    int image_color_space;
    int image_width_range, image_height_range;
} charon_ml_feature;

typedef struct {
    char *name;
    charon_ml_value value;
} charon_ml_feature_value;

/* An ordered set of values by name, which is what a model is given and what it answers in.
 * Ordered, not hashed: a prediction's outputs come out in the order the description names
 * them, and that order is part of what the model says. */
typedef struct {
    charon_ml_feature_value entries[CHARON_ML_MAX_FEATURES];
    size_t count;
} charon_ml_features;

typedef struct {
    charon_ml_node document;
    charon_ml_model_kind kind;
    int specification_version;
    charon_ml_feature inputs[CHARON_ML_MAX_FEATURES];
    size_t input_count;
    charon_ml_feature outputs[CHARON_ML_MAX_FEATURES];
    size_t output_count;
    /* A classifier's own names: the feature its label comes out as, the feature its
     * probabilities come out as, and the labels themselves in the order of the classes. */
    char *predicted_feature_name;
    char *predicted_probabilities_name;
    char **class_labels;
    size_t class_label_count;
    char *author;
    char *license;
    char *short_description;
    char *version;
    /* The bundle a compiled model was read from, when it was one: a blob the specification
     * refers to by name is looked for there. NULL for a model read from a file. */
    char *bundle;
    /* The bytes the document was read out of. A node is a window into them rather than a copy,
     * so the model owns this buffer and frees it with the document: a weight matrix of a
     * megabyte is not duplicated to be held, and a node that outlived its bytes would read
     * freed memory. */
    char *bytes;
    /* A model read out of a document this does not own -- a pipeline's sub-models, each of
     * which is a whole model inside the one that was read. Its description and labels are
     * still copies, and are still freed; its document and the bytes behind it are not. */
    int borrowed;
} charon_ml_model;

/* --- the model ------------------------------------------------------------------------------ */

/* Reads a model from a path. `path` is either a .mlmodel file, which is the specification's
 * own container, or a .mlmodelc bundle, in which case its coremldata.bin is read. Returns 0
 * and writes a line an application can show into `error` (of `error_size` bytes) when the
 * container is not a model, or is one this specification does not describe. */
int charon_ml_model_read(charon_ml_model *model, const char *path, char *error, size_t error_size);
void charon_ml_model_release(charon_ml_model *model);

/* Reads the description, the two names a classifier answers under and the class labels out of
 * a model message this does not own -- the whole document for a model that was read from a
 * container, one of a pipeline's sub-models for a model inside one. The strings are copies
 * either way, so the model releases the same. Returns 0 and writes a line into `error` when
 * the message has no description, or names no kind the specification declares. */
int charon_ml_model_from_node(charon_ml_model *model, const charon_ml_node *document, const char *bundle,
                              char *error, size_t error_size);
/* The field of the specification's Type oneof this document carries, or NULL when it carries
 * none. The name is what the dispatch and the error messages read. */
const char *charon_ml_node_kind_name(const charon_ml_node *document);

const char *charon_ml_kind_name(charon_ml_model_kind kind);
/* Whether a model of this kind answers with a class label and a set of probabilities. */
int charon_ml_kind_is_classifier(charon_ml_model_kind kind);
const char *charon_ml_feature_type_name(charon_ml_feature_type type);

/* --- the feature set ------------------------------------------------------------------------ */

void charon_ml_features_init(charon_ml_features *features);
void charon_ml_features_release(charon_ml_features *features);
/* Adds a value, replacing one of the same name: a pipeline hands each sub-model's outputs on
 * by name, and a name that arrives twice is the later one. */
int charon_ml_features_put(charon_ml_features *features, const char *name, charon_ml_value value);
const charon_ml_value *charon_ml_features_get(const charon_ml_features *features, const char *name);
int charon_ml_features_remove(charon_ml_features *features, const char *name);

/* Moves the values whose names are the outputs of `model` out of `inputs` and into
 * `outputs`, in the order the description names them, and drops the rest. This is what a
 * sub-model of a pipeline does, and what the last one does to answer. */
int charon_ml_features_take_outputs(const charon_ml_model *model, charon_ml_features *inputs,
                                    charon_ml_features *outputs);
/* Whether `features` holds a value of the right kind and shape for every input of `model`.
 * `missing`, when it is not NULL and not empty, is filled with the name of the first input
 * that is absent, and `mismatched` with the name of the first whose shape or type is wrong. */
int charon_ml_features_satisfy(const charon_ml_model *model, const charon_ml_features *features,
                               char *missing, size_t missing_size, char *mismatched, size_t mismatched_size);

/* --- strings out of the document ------------------------------------------------------------- */

/* The bytes of a string field of `node`, copied out as a NUL terminated string the caller
 * owns, or NULL when the field is not there or is not a string. */
char *charon_ml_copy_string(const charon_ml_node *node, const char *field);
/* A copy of at most `length` bytes, NUL terminated. The port's C is built as C99, where
 * strdup is not declared, and a label's bytes are of a length the document gives. */
char *charon_ml_strndup(const char *bytes, size_t length);

#endif /* CHARON_ML_MODEL_H */

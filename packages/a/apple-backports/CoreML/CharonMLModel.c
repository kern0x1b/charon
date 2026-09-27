/* A Core ML model read from its container: which kind of model it is, what its features are,
 * and the set of values a prediction is made from and answered in.
 * CharonMLModel.h says what it is for; this is the reading of it.
 *
 * Every field is read through the specification (CharonMLProto.h), so a model this port runs
 * is the model its container describes. Nothing here interprets a layer or a weight: it is
 * the document, its description and its class labels, and nothing more.
 */
#include "CharonMLModel.h"
#include "CharonMLValue.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

/* The cases of the specification's Type oneof, and the kind each is read as. A name the
 * specification has and this list does not is CHARON_ML_KIND_OTHER: the model loads, and the
 * interpreter refuses it with a message naming the kind, rather than the load being refused
 * for a kind that is real. */
static const struct {
    const char *field;
    charon_ml_model_kind kind;
} MODEL_KINDS[] = {
    {"pipelineClassifier", CHARON_ML_KIND_PIPELINE_CLASSIFIER},
    {"pipelineRegressor", CHARON_ML_KIND_PIPELINE_REGRESSOR},
    {"pipeline", CHARON_ML_KIND_PIPELINE},
    {"neuralNetworkClassifier", CHARON_ML_KIND_NEURAL_NETWORK_CLASSIFIER},
    {"neuralNetworkRegressor", CHARON_ML_KIND_NEURAL_NETWORK_REGRESSOR},
    {"neuralNetwork", CHARON_ML_KIND_NEURAL_NETWORK},
    {"treeEnsembleClassifier", CHARON_ML_KIND_TREE_ENSEMBLE_CLASSIFIER},
    {"treeEnsembleRegressor", CHARON_ML_KIND_TREE_ENSEMBLE_REGRESSOR},
    {"glmClassifier", CHARON_ML_KIND_GLM_CLASSIFIER},
    {"glmRegressor", CHARON_ML_KIND_GLM_REGRESSOR},
    {"supportVectorClassifier", CHARON_ML_KIND_SVM_CLASSIFIER},
    {"supportVectorRegressor", CHARON_ML_KIND_SVM_REGRESSOR},
    {"kNearestNeighborsClassifier", CHARON_ML_KIND_KNN_CLASSIFIER},
    {"itemSimilarityRecommender", CHARON_ML_KIND_ITEM_SIMILARITY},
    {"scaler", CHARON_ML_KIND_SCALER},
    {"imputer", CHARON_ML_KIND_IMPUTER},
    {"normalizer", CHARON_ML_KIND_NORMALIZER},
    {"oneHotEncoder", CHARON_ML_KIND_ONE_HOT_ENCODER},
    {"dictVectorizer", CHARON_ML_KIND_DICT_VECTORIZER},
    {"featureVectorizer", CHARON_ML_KIND_FEATURE_VECTORIZER},
    {"categoricalMapping", CHARON_ML_KIND_CATEGORICAL_MAPPING},
    {"arrayFeatureExtractor", CHARON_ML_KIND_ARRAY_FEATURE_EXTRACTOR},
    {"nonMaximumSuppression", CHARON_ML_KIND_NON_MAXIMUM_SUPPRESSION},
    {"identity", CHARON_ML_KIND_IDENTITY},
    {"mlProgram", CHARON_ML_KIND_MIL_PROGRAM},
    {NULL, CHARON_ML_KIND_NONE}};

const char *charon_ml_kind_name(charon_ml_model_kind kind)
{
    int index;
    for (index = 0; MODEL_KINDS[index].field != NULL; index++) {
        if (MODEL_KINDS[index].kind == kind) {
            return MODEL_KINDS[index].field;
        }
    }
    return kind == CHARON_ML_KIND_NONE ? "none" : "other";
}

int charon_ml_kind_is_classifier(charon_ml_model_kind kind)
{
    switch (kind) {
    case CHARON_ML_KIND_PIPELINE_CLASSIFIER:
    case CHARON_ML_KIND_NEURAL_NETWORK_CLASSIFIER:
    case CHARON_ML_KIND_TREE_ENSEMBLE_CLASSIFIER:
    case CHARON_ML_KIND_GLM_CLASSIFIER:
    case CHARON_ML_KIND_SVM_CLASSIFIER:
    case CHARON_ML_KIND_KNN_CLASSIFIER:
        return 1;
    default:
        return 0;
    }
}

const char *charon_ml_feature_type_name(charon_ml_feature_type type)
{
    switch (type) {
    case CHARON_ML_FEATURE_INT64:
        return "int64";
    case CHARON_ML_FEATURE_DOUBLE:
        return "double";
    case CHARON_ML_FEATURE_STRING:
        return "string";
    case CHARON_ML_FEATURE_IMAGE:
        return "image";
    case CHARON_ML_FEATURE_MULTI_ARRAY:
        return "multiArray";
    case CHARON_ML_FEATURE_DICTIONARY:
        return "dictionary";
    case CHARON_ML_FEATURE_SEQUENCE:
        return "sequence";
    case CHARON_ML_FEATURE_STATE:
        return "state";
    default:
        return "none";
    }
}

char *charon_ml_copy_string(const charon_ml_node *node, const char *field)
{
    const charon_ml_node *value = charon_ml_get(node, field);
    char *copy;
    if (value == NULL || value->field == NULL ||
        (value->field->kind != CHARON_ML_KIND_STRING && value->field->kind != CHARON_ML_KIND_BYTES)) {
        return NULL;
    }
    copy = (char *)malloc(value->value.text.length + 1);
    if (copy == NULL) {
        return NULL;
    }
    memcpy(copy, value->value.text.bytes, value->value.text.length);
    copy[value->value.text.length] = 0;
    return copy;
}

/* --- the description of one feature ----------------------------------------------------------- */

static void read_feature(charon_ml_feature *feature, const charon_ml_node *described)
{
    const charon_ml_node *type;
    int index;

    memset(feature, 0, sizeof *feature);
    feature->name = charon_ml_copy_string(described, "name");
    feature->short_description = charon_ml_copy_string(described, "shortDescription");
    feature->image_color_space = CHARON_ML_COLOR_INVALID;
    feature->image_width_range = feature->image_height_range = CHARON_ML_FLEXIBLE;
    for (index = 0; index < 8; index++) {
        feature->shape[index] = CHARON_ML_FLEXIBLE;
        feature->shape_range[index][0] = 0;
        feature->shape_range[index][1] = CHARON_ML_FLEXIBLE;
    }
    type = charon_ml_get(described, "type");
    if (type == NULL) {
        return;
    }
    /* The FeatureType oneof: which case is in the document is which field the node carries, so
     * the kind is asked of the field rather than matched by name against a list. */
    for (index = 0; index < (int)charon_ml_count(type); index++) {
        const charon_ml_node *entry = charon_ml_at(type, index);
        const char *name = entry->field->name;
        const charon_ml_node *body = entry;
        if (strcmp(name, "isOptional") == 0) {
            feature->optional = charon_ml_int(entry, 0) != 0;
            continue;
        }
        if (strcmp(name, "int64Type") == 0) {
            feature->type = CHARON_ML_FEATURE_INT64;
        } else if (strcmp(name, "doubleType") == 0) {
            feature->type = CHARON_ML_FEATURE_DOUBLE;
        } else if (strcmp(name, "stringType") == 0) {
            feature->type = CHARON_ML_FEATURE_STRING;
        } else if (strcmp(name, "imageType") == 0) {
            feature->type = CHARON_ML_FEATURE_IMAGE;
        } else if (strcmp(name, "multiArrayType") == 0) {
            feature->type = CHARON_ML_FEATURE_MULTI_ARRAY;
        } else if (strcmp(name, "dictionaryType") == 0) {
            feature->type = CHARON_ML_FEATURE_DICTIONARY;
        } else if (strcmp(name, "sequenceType") == 0) {
            feature->type = CHARON_ML_FEATURE_SEQUENCE;
        } else if (strcmp(name, "stateType") == 0) {
            feature->type = CHARON_ML_FEATURE_STATE;
        } else {
            continue;
        }
        if (feature->type == CHARON_ML_FEATURE_IMAGE) {
            feature->image_width = charon_ml_int(charon_ml_get(body, "width"), 0);
            feature->image_height = charon_ml_int(charon_ml_get(body, "height"), 0);
            feature->image_color_space = charon_ml_int(charon_ml_get(body, "colorSpace"), CHARON_ML_COLOR_INVALID);
            {
                const charon_ml_node *range = charon_ml_get(body, "imageSizeRange");
                if (range != NULL) {
                    const charon_ml_node *width = charon_ml_get(range, "widthRange");
                    const charon_ml_node *height = charon_ml_get(range, "heightRange");
                    feature->image_width_range = charon_ml_int(charon_ml_get(width, "lowerBound"), 0);
                    feature->image_width = charon_ml_int(charon_ml_get(width, "upperBound"), feature->image_width);
                    feature->image_height_range = charon_ml_int(charon_ml_get(height, "lowerBound"), 0);
                    feature->image_height = charon_ml_int(charon_ml_get(height, "upperBound"), feature->image_height);
                }
            }
        } else if (feature->type == CHARON_ML_FEATURE_MULTI_ARRAY) {
            const charon_ml_node *range = charon_ml_get(body, "shapeRange");
            feature->data_type = charon_ml_int(charon_ml_get(body, "dataType"), CHARON_ML_ARRAY_INVALID);
            feature->rank = (int)charon_ml_count_field(body, "shape");
            if (feature->rank > 8) {
                feature->rank = 8;
            }
            for (index = 0; index < feature->rank; index++) {
                feature->shape[index] = charon_ml_int_at(body, "shape", (size_t)index, CHARON_ML_FLEXIBLE);
            }
            if (range != NULL) {
                size_t sizes = charon_ml_count_field(range, "sizeRanges");
                if (sizes > 0) {
                    feature->has_shape_range = 1;
                    for (index = 0; index < (int)sizes && index < 8; index++) {
                        const charon_ml_node *bounds = charon_ml_node_at_field(range, "sizeRanges", (size_t)index);
                        /* SizeRange's lower bound is unsigned and its upper bound is signed,
                         * and -1 is the specification's "no upper bound": a dimension of no
                         * fixed length, which is flexible rather than absent. */
                        feature->shape_range[index][0] = charon_ml_int(charon_ml_get(bounds, "lowerBound"), 0);
                        feature->shape_range[index][1] = charon_ml_int(charon_ml_get(bounds, "upperBound"), CHARON_ML_FLEXIBLE);
                        if (feature->shape[index] == 0) {
                            feature->shape[index] = feature->shape_range[index][1];
                        }
                    }
                }
            }
        }
        break;
    }
}

static void release_feature(charon_ml_feature *feature)
{
    free(feature->name);
    free(feature->short_description);
    feature->name = NULL;
    feature->short_description = NULL;
}

static size_t read_feature_list(charon_ml_feature *into, size_t room, const charon_ml_node *description,
                                const char *field)
{
    size_t total = charon_ml_count_field(description, field), index, kept = 0;
    for (index = 0; index < total && kept < room; index++) {
        read_feature(&into[kept], charon_ml_node_at_field(description, field, index));
        kept++;
    }
    return kept;
}

/* --- the class labels ------------------------------------------------------------------------- */

/* A classifier's labels live in the oneof of the model kind, in a StringVector or an
 * Int64Vector, so which vector is asked of the oneof rather than by a name. */
static size_t read_class_labels(charon_ml_model *model, const charon_ml_node *kind_node)
{
    const charon_ml_node *labels = charon_ml_oneof(kind_node, "stringClassLabels");
    size_t count, index;
    if (labels == NULL) {
        labels = charon_ml_oneof(kind_node, "int64ClassLabels");
    }
    if (labels == NULL) {
        return 0;
    }
    count = charon_ml_count_field(labels, "vector");
    if (count == 0) {
        return 0;
    }
    model->class_labels = (char **)calloc(count, sizeof *model->class_labels);
    if (model->class_labels == NULL) {
        return 0;
    }
    for (index = 0; index < count; index++) {
        const charon_ml_node *entry = charon_ml_node_at_field(labels, "vector", index);
        if (entry != NULL && entry->value.text.length < 32) {
            model->class_labels[index] = charon_ml_strndup(entry->value.text.bytes, entry->value.text.length);
        } else {
            model->class_labels[index] = charon_ml_strndup("", 0);
        }
    }
    model->class_label_count = count;
    return count;
}

/* --- reading the container --------------------------------------------------------------------- */

static char *slurp(const char *path, size_t *length)
{
    FILE *file = fopen(path, "rb");
    char *bytes;
    long size;
    if (file == NULL) {
        return NULL;
    }
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0) {
        fclose(file);
        return NULL;
    }
    rewind(file);
    bytes = (char *)malloc((size_t)size + 1);
    if (bytes == NULL || (size > 0 && fread(bytes, 1, (size_t)size, file) != (size_t)size)) {
        free(bytes);
        fclose(file);
        return NULL;
    }
    fclose(file);
    bytes[size] = 0;
    *length = (size_t)size;
    return bytes;
}

static int is_directory(const char *path)
{
    struct stat info;
    return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static int file_exists(const char *path)
{
    struct stat info;
    return stat(path, &info) == 0 && S_ISREG(info.st_mode);
}

static void join(char *out, size_t size, const char *directory, const char *name)
{
    size_t used = strlen(directory);
    snprintf(out, size, "%s%s%s", directory, used > 0 && directory[used - 1] == '/' ? "" : "/", name);
}

/* The field of the Type oneof this document carries. The kind is asked of the document rather
 * than matched against a list of names at each call site, so the interpreter and the errors
 * read the same one. */
const char *charon_ml_node_kind_name(const charon_ml_node *document)
{
    int index;
    for (index = 0; MODEL_KINDS[index].field != NULL; index++) {
        if (charon_ml_get(document, MODEL_KINDS[index].field) != NULL) {
            return MODEL_KINDS[index].field;
        }
    }
    return NULL;
}

int charon_ml_model_from_node(charon_ml_model *model, const charon_ml_node *document, const char *bundle,
                              char *error, size_t error_size)
{
    const charon_ml_node *description, *kind_node, *metadata;
    const char *kind_field = charon_ml_node_kind_name(document);
    int index;

    memset(model, 0, sizeof *model);
    model->kind = CHARON_ML_KIND_NONE;
    model->borrowed = 1;
    model->bundle = bundle != NULL ? strdup(bundle) : NULL;
    model->document = *document;
    model->specification_version = charon_ml_int(charon_ml_get(document, "specificationVersion"), 0);
    kind_node = kind_field != NULL ? charon_ml_get(document, kind_field) : NULL;
    if (kind_node == NULL) {
        snprintf(error, error_size, "the model names no kind of model the specification declares, so there is nothing to run");
        return 0;
    }
    for (index = 0; MODEL_KINDS[index].field != NULL; index++) {
        if (strcmp(MODEL_KINDS[index].field, kind_field) == 0) {
            model->kind = MODEL_KINDS[index].kind;
            break;
        }
    }
    description = charon_ml_get(document, "description");
    if (description == NULL) {
        snprintf(error, error_size, "the model has no description, so it names no features");
        return 0;
    }
    model->input_count = read_feature_list(model->inputs, CHARON_ML_MAX_FEATURES, description, "input");
    model->output_count = read_feature_list(model->outputs, CHARON_ML_MAX_FEATURES, description, "output");
    model->predicted_feature_name = charon_ml_copy_string(description, "predictedFeatureName");
    model->predicted_probabilities_name = charon_ml_copy_string(description, "predictedProbabilitiesName");
    model->short_description = charon_ml_copy_string(description, "shortDescription");
    metadata = charon_ml_get(description, "metadata");
    if (metadata != NULL) {
        model->author = charon_ml_copy_string(metadata, "author");
        model->license = charon_ml_copy_string(metadata, "license");
        model->version = charon_ml_copy_string(metadata, "versionString");
        if (model->short_description == NULL) {
            model->short_description = charon_ml_copy_string(metadata, "shortDescription");
        }
    }
    if (charon_ml_kind_is_classifier(model->kind)) {
        read_class_labels(model, kind_node);
    }
    return 1;
}

int charon_ml_model_read(charon_ml_model *model, const char *path, char *error, size_t error_size)
{
    char container[1024];
    char *bytes;
    size_t length = 0;
    charon_ml_node document;

    memset(model, 0, sizeof *model);
    if (path == NULL) {
        snprintf(error, error_size, "no path to a model");
        return 0;
    }
    if (is_directory(path)) {
        /* A compiled model is a bundle, and its program is the coremldata.bin inside it. A
         * bundle that does not hold one is not a model this port can read, and the error says
         * so rather than reading whatever file is there. */
        join(container, sizeof container, path, "coremldata.bin");
        if (!file_exists(container)) {
            snprintf(error, error_size,
                     "the bundle at %s holds no coremldata.bin, which is where a compiled model keeps its program",
                     path);
            return 0;
        }
    } else {
        snprintf(container, sizeof container, "%s", path);
    }
    bytes = slurp(container, &length);
    if (bytes == NULL) {
        snprintf(error, error_size, "the model at %s could not be read", container);
        return 0;
    }
    if (length == 0 || !charon_ml_read(&document, bytes, length, "CoreML.Specification.Model")) {
        snprintf(error, error_size,
                 "the file at %s is not a Core ML model: it is not a message of the model type the specification declares",
                 container);
        free(bytes);
        return 0;
    }
    /* The buffer becomes the model's own: every node of the document is a window into it, so
     * the model frees the two together and a node never outlives the bytes it points into. */
    model->bytes = bytes;
    model->borrowed = 0;
    if (is_directory(path)) {
        model->bundle = strdup(path);
    }
    if (!charon_ml_model_from_node(model, &document, model->bundle, error, error_size)) {
        charon_ml_model_release(model);
        snprintf(error, error_size, "the model at %s cannot be run: %s", container, error);
        return 0;
    }
    model->document = document;
    model->borrowed = 0;
    return 1;
}

void charon_ml_model_release(charon_ml_model *model)
{
    size_t index;
    if (model == NULL) {
        return;
    }
    for (index = 0; index < model->input_count; index++) {
        release_feature(&model->inputs[index]);
    }
    for (index = 0; index < model->output_count; index++) {
        release_feature(&model->outputs[index]);
    }
    for (index = 0; index < model->class_label_count; index++) {
        free(model->class_labels[index]);
    }
    free(model->class_labels);
    free(model->predicted_feature_name);
    free(model->predicted_probabilities_name);
    free(model->author);
    free(model->license);
    free(model->short_description);
    free(model->version);
    free(model->bundle);
    if (!model->borrowed) {
        charon_ml_free(&model->document);
        free(model->bytes);
    }
    memset(model, 0, sizeof *model);
}

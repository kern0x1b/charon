/* coreml-cases.h -- what the Core ML host differential records.
 *
 * One recorder, and the cases file that fills it. The same cases file is compiled twice: once
 * against the Core ML of this host, and once against the port's own classes compiled under names
 * of their own (Charon<name>), so both answer the same questions about the same containers and
 * the two sets of answers can be compared name for name.
 */
#import <Foundation/Foundation.h>

typedef void (^CoreMLRecorder)(NSString *name, NSString *value);

void coreml_run(NSString *models, CoreMLRecorder record);

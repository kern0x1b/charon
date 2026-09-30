#import <ModelIO/ModelIO.h>
#import <ModelIO/MDLMaterial.h>
#import <objc/runtime.h>

// The rows the PER-CLASS check found naming a selector this class does not define. A union over
// every selector is not evidence: it cannot tell -[MDLAreaLight setAreaRadius:] from
// -[MDLTexture setAreaRadius:], so each is checked against its OWN class s method list.
@implementation MDLMaterialPropertyConnection (CharonPerClass100)
- (id)init { return nil; }
@end
@implementation MDLMaterialPropertyGraph (CharonPerClass100)
- (id)init { return nil; }
@end
@implementation MDLMaterialPropertyNode (CharonPerClass100)
- (id)init { return nil; }
@end

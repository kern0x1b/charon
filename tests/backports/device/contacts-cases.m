#import <Contacts/Contacts.h>
#import "contacts-cases.h"

// Every case here builds its objects in memory and never touches a real
// address book: no CNContactStore instance is ever asked for a permission,
// a fetch or a save. That is not a limitation of the harness, it is the
// point - the host runs under whoever is signed into this Mac, and this
// package promised never to read, log or write that person's own contacts.
// What is left is the whole of the value-object surface: CNContact and its
// values, the formatter, the vCard pair, groups before they are saved, and
// the plain value classes beside them - which is most of what an
// application does with Contacts before it ever calls the store.

static NSString *flag(BOOL value)
{
    return value ? @"1" : @"0";
}

static NSString *named(Class cls)
{
    NSString *name = NSStringFromClass(cls);
    return [name hasPrefix:@"Charon"] ? [name substringFromIndex:6] : name;
}

static void phoneNumbers(ContactsRecorder record)
{
    CNPhoneNumber *mobile = [CNPhoneNumber phoneNumberWithStringValue:@"+15551234"];
    CNPhoneNumber *same = [CNPhoneNumber phoneNumberWithStringValue:@"+15551234"];
    CNPhoneNumber *other = [CNPhoneNumber phoneNumberWithStringValue:@"+15559999"];
    record(@"phone.stringValue", mobile.stringValue);
    record(@"phone.equality", [NSString stringWithFormat:@"same=%@ isEqual=%@ hash=%@ other=%@",
                               flag(mobile == same), flag([mobile isEqual:same]), flag(mobile.hash == same.hash), flag([mobile isEqual:other])]);
    CNPhoneNumber *copied = [mobile copy];
    record(@"phone.copy", [NSString stringWithFormat:@"same=%@ equal=%@", flag(copied == mobile), flag([copied isEqual:mobile])]);
}

static void labeledValues(ContactsRecorder record)
{
    CNLabeledValue *home = [CNLabeledValue labeledValueWithLabel:CNLabelHome value:@"a@b.c"];
    record(@"labeled.values", [NSString stringWithFormat:@"label=%@ value=%@ identifierNonEmpty=%@", home.label, home.value, flag(home.identifier.length > 0)]);
    CNLabeledValue *relabeled = [home labeledValueBySettingLabel:CNLabelWork];
    record(@"labeled.relabel", [NSString stringWithFormat:@"label=%@ value=%@ sameIdentifier=%@", relabeled.label, relabeled.value, flag([relabeled.identifier isEqualToString:home.identifier])]);
    CNLabeledValue *revalued = [home labeledValueBySettingValue:@"x@y.z"];
    record(@"labeled.revalue", [NSString stringWithFormat:@"label=%@ value=%@ sameIdentifier=%@", revalued.label, revalued.value, flag([revalued.identifier isEqualToString:home.identifier])]);
    CNLabeledValue *copied = [home copy];
    record(@"labeled.copy", [NSString stringWithFormat:@"same=%@ equal=%@", flag(copied == home), flag([copied isEqual:home])]);
}

static void postalAddresses(ContactsRecorder record)
{
    CNMutablePostalAddress *address = [[CNMutablePostalAddress alloc] init];
    address.street = @"1 Infinite Loop";
    address.city = @"Cupertino";
    address.state = @"CA";
    address.postalCode = @"95014";
    address.country = @"United States";
    address.ISOCountryCode = @"us";
    record(@"postal.fields", [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@", address.street, address.city, address.state, address.postalCode, address.country, address.ISOCountryCode]);
    CNPostalAddress *copied = [address copy];
    record(@"postal.copy", [NSString stringWithFormat:@"class=%@ equal=%@", named([copied class]), flag([copied isEqual:address])]);
    CNMutablePostalAddress *mutableCopied = [address mutableCopy];
    mutableCopied.city = @"Elsewhere";
    record(@"postal.mutableCopyIndependent", [NSString stringWithFormat:@"original=%@ copy=%@", address.city, mutableCopied.city]);
}

static void postalAddressFormatter(ContactsRecorder record)
{
    CNMutablePostalAddress *address = [[CNMutablePostalAddress alloc] init];
    address.street = @"1 Infinite Loop";
    address.city = @"Cupertino";
    address.state = @"CA";
    address.postalCode = @"95014";
    address.country = @"United States";
    address.ISOCountryCode = @"us";
    record(@"postalFormatter.mailing", [CNPostalAddressFormatter stringFromPostalAddress:address style:CNPostalAddressFormatterStyleMailingAddress]);
    CNPostalAddressFormatter *formatter = [[CNPostalAddressFormatter alloc] init];
    record(@"postalFormatter.instance", [formatter stringFromPostalAddress:address]);
}

static void instantMessageAndSocial(ContactsRecorder record)
{
    CNInstantMessageAddress *aim = [[CNInstantMessageAddress alloc] initWithUsername:@"handle" service:CNInstantMessageServiceAIM];
    CNInstantMessageAddress *same = [[CNInstantMessageAddress alloc] initWithUsername:@"handle" service:CNInstantMessageServiceAIM];
    record(@"instantMessage.values", [NSString stringWithFormat:@"%@|%@|equal=%@", aim.username, aim.service, flag([aim isEqual:same])]);

    CNSocialProfile *twitter = [[CNSocialProfile alloc] initWithUrlString:@"https://twitter.com/handle" username:@"handle" userIdentifier:nil service:CNSocialProfileServiceTwitter];
    CNSocialProfile *sameTwitter = [[CNSocialProfile alloc] initWithUrlString:@"https://twitter.com/handle" username:@"handle" userIdentifier:nil service:CNSocialProfileServiceTwitter];
    record(@"social.values", [NSString stringWithFormat:@"%@|%@|%@|equal=%@", twitter.urlString, twitter.username, twitter.service, flag([twitter isEqual:sameTwitter])]);

    CNContactRelation *sister = [[CNContactRelation alloc] initWithName:@"Jane"];
    CNContactRelation *sameSister = [[CNContactRelation alloc] initWithName:@"Jane"];
    record(@"relation.values", [NSString stringWithFormat:@"%@|equal=%@", sister.name, flag([sister isEqual:sameSister])]);
}

static void contactProperty(ContactsRecorder record)
{
    CNContactProperty *empty = [[CNContactProperty alloc] init];
    record(@"contactProperty.plainInit", [NSString stringWithFormat:@"contact=%@ key=%@ value=%@ identifier=%@ label=%@",
                                          flag(empty.contact != nil), flag(empty.key != nil), flag(empty.value != nil), flag(empty.identifier != nil), flag(empty.label != nil)]);
}

static void contacts(ContactsRecorder record)
{
    CNMutableContact *contact = [[CNMutableContact alloc] init];
    contact.givenName = @"Jane";
    contact.familyName = @"Doe";
    contact.organizationName = @"Acme";
    contact.phoneNumbers = @[[CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMobile value:[CNPhoneNumber phoneNumberWithStringValue:@"+15551234"]]];
    contact.emailAddresses = @[[CNLabeledValue labeledValueWithLabel:CNLabelHome value:@"jane@example.com"]];
    record(@"contact.values", [NSString stringWithFormat:@"%@|%@|%@|phones=%ld|emails=%ld", contact.givenName, contact.familyName, contact.organizationName, (long)contact.phoneNumbers.count, (long)contact.emailAddresses.count]);
    record(@"contact.contactType", (long)contact.contactType == CNContactTypePerson ? @"person" : @"organization");
    record(@"contact.identifierNonEmpty", flag(contact.identifier.length > 0));

    NSDateComponents *birthday = [[NSDateComponents alloc] init];
    birthday.year = 1990; birthday.month = 5; birthday.day = 17;
    contact.birthday = birthday;
    record(@"contact.birthday", [NSString stringWithFormat:@"%ld-%ld-%ld", (long)contact.birthday.year, (long)contact.birthday.month, (long)contact.birthday.day]);

    CNContact *immutable = [contact copy];
    record(@"contact.copyClass", named([immutable class]));
    record(@"contact.copyEqual", flag([immutable isEqual:contact]));

    CNMutableContact *other = [contact mutableCopy];
    other.givenName = @"Other";
    record(@"contact.mutableCopyIndependent", [NSString stringWithFormat:@"original=%@ copy=%@", contact.givenName, other.givenName]);
    record(@"contact.notEqualAfterChange", flag(![contact isEqual:other]));
}

static void contactFormatter(ContactsRecorder record)
{
    CNMutableContact *contact = [[CNMutableContact alloc] init];
    contact.givenName = @"Jane";
    contact.familyName = @"Doe";
    CNContactFormatter *formatter = [[CNContactFormatter alloc] init];
    formatter.style = CNContactFormatterStyleFullName;
    record(@"formatter.fullName", [formatter stringFromContact:contact]);
    record(@"formatter.classFullName", [CNContactFormatter stringFromContact:contact style:CNContactFormatterStyleFullName]);
    record(@"formatter.nameOrder", (long)[CNContactFormatter nameOrderForContact:contact] == CNContactDisplayNameOrderGivenNameFirst ? @"given" : @"family");

    CNMutableContact *organization = [[CNMutableContact alloc] init];
    organization.organizationName = @"Acme";
    organization.contactType = CNContactTypeOrganization;
    record(@"formatter.organizationName", [CNContactFormatter stringFromContact:organization style:CNContactFormatterStyleFullName]);

    CNMutableContact *empty = [[CNMutableContact alloc] init];
    record(@"formatter.emptyContact", flag([CNContactFormatter stringFromContact:empty style:CNContactFormatterStyleFullName] == nil));
    record(@"formatter.nilContact", flag([CNContactFormatter stringFromContact:nil style:CNContactFormatterStyleFullName] == nil));

    id<CNKeyDescriptor> descriptor = [CNContactFormatter descriptorForRequiredKeysForStyle:CNContactFormatterStyleFullName];
    record(@"formatter.descriptorConforms", flag([descriptor conformsToProtocol:@protocol(CNKeyDescriptor)]));
}

static void vCard(ContactsRecorder record)
{
    CNMutableContact *contact = [[CNMutableContact alloc] init];
    contact.givenName = @"John";
    contact.familyName = @"Appleseed";
    contact.phoneNumbers = @[[CNLabeledValue labeledValueWithLabel:CNLabelPhoneNumberMobile value:[CNPhoneNumber phoneNumberWithStringValue:@"+15551234"]]];
    NSError *error = nil;
    NSData *data = [CNContactVCardSerialization dataWithContacts:@[contact] error:&error];
    record(@"vcard.encoded", data != nil ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil);
    NSArray<CNContact *> *decoded = data ? [CNContactVCardSerialization contactsWithData:data error:&error] : nil;
    CNContact *round = decoded.firstObject;
    record(@"vcard.roundtrip", [NSString stringWithFormat:@"count=%ld given=%@ family=%@ phones=%ld",
                                (long)decoded.count, round.givenName, round.familyName, (long)round.phoneNumbers.count]);

    NSError *badError = nil;
    NSArray *bad = [CNContactVCardSerialization contactsWithData:[@"not a vcard" dataUsingEncoding:NSUTF8StringEncoding] error:&badError];
    record(@"vcard.badData", [NSString stringWithFormat:@"result=%@ error=%@", flag(bad != nil), flag(badError != nil)]);
}

static void groups(ContactsRecorder record)
{
    CNGroup *plain = [[CNGroup alloc] init];
    record(@"group.plainInitNonEmptyIdentifier", flag(plain.identifier.length > 0));
    record(@"group.plainInitEmptyName", flag(plain.name.length == 0));

    CNMutableGroup *mutableGroup = [[CNMutableGroup alloc] init];
    mutableGroup.name = @"Friends";
    record(@"group.mutableName", mutableGroup.name);
    record(@"group.mutableIdentifierNonEmpty", flag(mutableGroup.identifier.length > 0));

    NSPredicate *byIdentifiers = [CNGroup predicateForGroupsWithIdentifiers:@[@"1", @"2"]];
    record(@"group.predicateByIdentifiersIsPredicate", flag([byIdentifiers isKindOfClass:[NSPredicate class]]));
    NSPredicate *inContainer = [CNGroup predicateForGroupsInContainerWithIdentifier:@"1"];
    record(@"group.predicateInContainerIsPredicate", flag([inContainer isKindOfClass:[NSPredicate class]]));
}

static void containers(ContactsRecorder record)
{
    NSPredicate *byIdentifiers = [CNContainer predicateForContainersWithIdentifiers:@[@"1"]];
    record(@"container.predicateByIdentifiersIsPredicate", flag([byIdentifiers isKindOfClass:[NSPredicate class]]));
    NSPredicate *ofContact = [CNContainer predicateForContainerOfContactWithIdentifier:@"1"];
    record(@"container.predicateOfContactIsPredicate", flag([ofContact isKindOfClass:[NSPredicate class]]));
    NSPredicate *ofGroup = [CNContainer predicateForContainerOfGroupWithIdentifier:@"1"];
    record(@"container.predicateOfGroupIsPredicate", flag([ofGroup isKindOfClass:[NSPredicate class]]));
    record(@"container.typeValues", [NSString stringWithFormat:@"%ld|%ld|%ld|%ld",
                                     (long)CNContainerTypeUnassigned, (long)CNContainerTypeLocal, (long)CNContainerTypeExchange, (long)CNContainerTypeCardDAV]);
}

static void userDefaults(ContactsRecorder record)
{
    CNContactsUserDefaults *defaults = [CNContactsUserDefaults sharedDefaults];
    record(@"defaults.sortOrderIsKnown", flag(defaults.sortOrder == CNContactSortOrderGivenName || defaults.sortOrder == CNContactSortOrderFamilyName));
    record(@"defaults.countryCodeIsTwoLetters", flag(defaults.countryCode.length == 2));
}

void contacts_run(ContactsRecorder record)
{
    phoneNumbers(record);
    labeledValues(record);
    postalAddresses(record);
    postalAddressFormatter(record);
    instantMessageAndSocial(record);
    contactProperty(record);
    contacts(record);
    contactFormatter(record);
    vCard(record);
    groups(record);
    containers(record);
    userDefaults(record);
}

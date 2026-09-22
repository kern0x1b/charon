# The values of a contact, iOS 9.0

Contacts came in iOS 9.0 as an Objective-C surface over the same local store
`AddressBook` had kept since iPhone OS 2.0. The C API of that store is whole in
iOS 6.1.3 - `ABAddressBookCreate`, `ABAddressBookCopyArrayOfAllPeople`,
`ABAddressBookSave`, `ABPersonCopyLocalizedPropertyName`, the multi-value family
and the vCard pair are all exported by the armv7 shared cache of the release - so
the classes here are a translation, not a new subsystem.

Source: `Contacts` of the arm64 shared cache of iOS 12.0 for the value of every
constant and for the shape of the classes (`+[CNLabeledValue makeIdentifier]` at
`0x18bc96fc0`, which asks `+identifierProvider` at `0x18bc96f3c` for a
`CNUuidIdentifierProvider`); the resources of `Contacts.framework` on an
iPhone4,1 running 9.3.6 - `English.lproj/CNContact.strings`,
`CNPostalAddress.strings`, `CNSocialProfile.strings`, `MessagingServices.strings`
and `SocialServices.strings` - for what the release displays; `AddressBook` of the
armv7 shared cache of 6.1.3 and `AddressBook.framework`'s own
`English.lproj/Localized.strings` and `ABAddressFormats.plist` on an iPhone4,1
running 6.1.3 for what the release under this port carries.

## The keys are the same strings

Every constant is defined with the string the release holds, read out of the
cache, not spelled from memory: `CNContactGivenNameKey` is `givenName`,
`CNContactStoreDidChangeNotification` is `CNContactStoreDidChangeNotification`,
`CNLabelHome` is `_$!<Home>!$_`, `CNContactPropertyNotFetchedExceptionName` is
`CNPropertyNotFetchedException`. The labels of `AddressBook` and of Contacts are
the same strings - `kABHomeLabel` is `_$!<Home>!$_` in the release too - so a
label needs no translation in either direction.

## How a property maps onto the book

| Contacts | AddressBook |
| --- | --- |
| `givenName`, `middleName`, `familyName` | `kABPersonFirstNameProperty`, `kABPersonMiddleNameProperty`, `kABPersonLastNameProperty` |
| `namePrefix`, `nameSuffix`, `nickname` | `kABPersonPrefixProperty`, `kABPersonSuffixProperty`, `kABPersonNicknameProperty` |
| `phoneticGivenName`, `phoneticMiddleName`, `phoneticFamilyName` | the three `…PhoneticProperty` |
| `organizationName`, `departmentName`, `jobTitle`, `note` | `kABPersonOrganizationProperty`, `kABPersonDepartmentProperty`, `kABPersonJobTitleProperty`, `kABPersonNoteProperty` |
| `contactType` | `kABPersonKindProperty` |
| `birthday`, `dates` | `kABPersonBirthdayProperty`, `kABPersonDateProperty` |
| `phoneNumbers`, `emailAddresses`, `urlAddresses` | `kABPersonPhoneProperty`, `kABPersonEmailProperty`, `kABPersonURLProperty` |
| `postalAddresses` | `kABPersonAddressProperty` |
| `contactRelations` | `kABPersonRelatedNamesProperty` |
| `socialProfiles`, `instantMessageAddresses` | `kABPersonSocialProfileProperty`, `kABPersonInstantMessageProperty` |
| `imageData`, `thumbnailImageData` | `ABPersonCopyImageDataWithFormat` |

A postal address is a dictionary in the book: `street` is `Street`, `city` is
`City`, `state` is `State`, `postalCode` is `ZIP`, `country` is `Country` and
`ISOCountryCode` is `CountryCode`. A social profile is a dictionary too, and its
`urlString` is `url` and its `userIdentifier` is `identifier`.

## Where iOS 6 differs, and it is written down rather than hidden

- **`previousFamilyName` and `nonGregorianBirthday` have nowhere to live.** The
  release exports no maiden-name property and no `kABPersonAlternateBirthdayProperty`
  at all. The two properties answer as the release's own empty value, a contact
  read out of the book never carries them, and the facts of the save request say
  what a write does with them.
- **`subLocality` and `subAdministrativeArea`** arrived in iOS 10.3 and the
  release's address dictionary has no such field, so they are always empty. Their
  keys are carried so that a `keysToFetch` naming them still links.
- **A labeled value's `identifier` is a UUID**, as it is in the release, which
  makes one through `CNUuidIdentifierProvider`. The release's book identifies an
  entry of a multi-value by an integer instead, so the entry's
  `ABMultiValueIdentifier` is kept beside the UUID and is what a save uses to find
  the entry again. Nothing hands that integer out.
- **The social service names differ in case.** Contacts writes `Twitter`,
  `Facebook`, `LinkedIn`, `MySpace`, `SinaWeibo`, `Flickr` and `Game Center`; the
  release's book writes `twitter`, `facebook`, `linkedin`, `myspace`, `sinaweibo`,
  `flickr` and `gamecenter`. The port translates the seven both ways and passes
  anything else through, so a profile written by iOS 6's own Contacts application
  reads back under the name Contacts uses. The instant-message services need no
  translation: both frameworks spell them `AIM`, `Facebook`, `GaduGadu`,
  `GoogleTalk`, `ICQ`, `Jabber`, `MSN`, `QQ`, `Skype` and `Yahoo`.
- **`+[CNContact localizedStringForKey:]` answers through
  `ABPersonCopyLocalizedPropertyName`**, which is the release's own localization
  in the user's language. Its English differs from the release that owns the API:
  iOS 9.3.6's `CNContact.strings` says `First name` where 6.1.3's
  `Localized.strings` says `First`, and `Company` for `organizationName` in both.
  A key the book has no property for answers with the key itself.
- **`+[CNPostalAddress localizedStringForKey:]`** answers with the token the
  release's own `ABAddressFormats.plist` names a component by - `Street`, `City`,
  `State`, `ZIP`, `Country`, `CountryCode` - and not with a localized string:
  6.1.3 carries no table that localizes them. iOS 9 answers `Street`, `City`,
  `State`, `ZIP`, `Country`, `Country code`, `District` and `County` out of
  `CNPostalAddress.strings`.
- **`+[CNSocialProfile localizedStringForService:]` and the instant-message pair
  answer the service itself**, because 6.1.3 carries no table of display names for
  them. iOS 9 answers `Sina Weibo`, `Tencent Weibo`, `Myspace` and `Google Talk`
  out of `SocialServices.strings` and `MessagingServices.strings`.
- **A comparator sorts by name with `localizedStandardCompare:`** over the given
  name and the family name in the order asked for, and `CNContactSortOrderUserDefault`
  reads the release's own `ABPersonGetSortOrdering()`. The release sorts with a
  collator of its own, so two names that differ only in how a collation orders
  them can come out in a different order than under iOS 9.
- **`CNContactVCardSerialization` writes the platform it runs on into `PRODID`.**
  `dataWithContacts:error:` delegates straight to `ABPersonCreateVCardRepresentationWithPeople`,
  so the line reads `-//Apple Inc.//iOS 6.1.3//EN` on the device and
  `-//Apple Inc.//macOS 27.0//EN` from a host oracle built for Mac Catalyst - each
  side honestly reporting its own `AddressBook.framework`, not a bug in either. A
  device check holding `vcard.encoded` to a host-generated expectation normalizes
  that one token before comparing; every other byte of the vCard still has to
  match exactly. `tests/backports/device/contacts.m` does this.

## Key availability

A contact remembers the keys the fetch asked for. Reading a property whose key
was not among them raises `CNPropertyNotFetchedException` under the name
`CNContactPropertyNotFetchedExceptionName`, which is what the release does, and
`isKeyAvailable:` and `areKeysAvailable:` answer honestly. A contact an
application makes itself has every key available, and setting a value makes its
key available.

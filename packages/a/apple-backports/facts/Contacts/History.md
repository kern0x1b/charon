# CNFetchResult and the change history classes, iOS 13.0

`CNFetchResult`, `CNChangeHistoryEvent` and its eleven concrete subclasses are
real classes here, carried so that a strong reference to any of them does not
crash dyld. What stays `absent` is one selector and one property -
`-[CNContactStore enumeratorForChangeHistoryFetchRequest:error:]` and
`CNContactStore.currentHistoryToken` - because both would have to walk a
change history the release's `AddressBook` never recorded. The wall is at
that seam, not on the classes the walk would have handed back.

Source: the headers of SDK 16.4 for the declarations; `Contacts` of the arm64
shared cache of iOS 12.0 for the shape of the classes; `AddressBook` of the
armv7 shared cache of 6.1.3 for what the store underneath can and cannot
answer.

## CNFetchResult

A plain generic container of a `value` and a `currentHistoryToken`. Nothing
about it needs history: `-[CNContactStore enumeratorForContactFetchRequest:error:]`
(also iOS 13) runs the same fetch `unifiedContactsMatchingPredicate:keysToFetch:error:`
already does, wraps the result array in an `NSEnumerator`, and hands it back
inside a real `CNFetchResult` whose `currentHistoryToken` is nil - there is no
token because there is no history, not because the container is fake.

## CNChangeHistoryEvent and its subclasses

The base class and its eleven documented subclasses
(`CNChangeHistoryDropEverythingEvent`, `..AddContactEvent`,
`..UpdateContactEvent`, `..DeleteContactEvent`, `..AddGroupEvent`,
`..UpdateGroupEvent`, `..DeleteGroupEvent`, `..AddMemberToGroupEvent`,
`..RemoveMemberFromGroupEvent`, `..AddSubgroupToGroupEvent` and
`..RemoveSubgroupFromGroupEvent`) exist with their documented readonly
properties and `-acceptEventVisitor:`, which dispatches to the matching
`CNChangeHistoryEventVisitor` method (the optional group/subgroup visit
methods are dispatched only when the visitor implements them, matching the
`@optional` methods of the real protocol). Nothing in this port ever
constructs one of these events, the same way nothing in a release with no
change history to report would either - the only path that could produce one,
`enumeratorForChangeHistoryFetchRequest:error:`, is the one selector this
package leaves `absent`.

`CNChangeHistoryAddSubgroupToGroupEvent` and
`..RemoveSubgroupFromGroupEvent` are carried as classes because the real SDK
declares them for iOS (only the `CNSaveRequest` methods that would produce
them, `addSubgroup:toGroup:`/`removeSubgroup:fromGroup:`, are marked
`API_UNAVAILABLE(ios)`); `AddressBook` has no group-nesting API either way, so
this is a class that exists and is simply never instantiated, on this port as
on the real release.

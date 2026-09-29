# The sec_protocol_* worklist: every absent row, where it is, and what is owed

Generated from the registry with each api's declaration read out of the 16.4 SDK, so this is a list
rather than a search. **48 rows: 17 `sec_protocol_metadata_*` and 31 `sec_protocol_options_*`,** and
every one of the 48 has a declaration in `SecProtocolMetadata.h` or `SecProtocolOptions.h` - none of
them is a name the headers do not have, which is why none of them is `absent` for that reason.

**Status at the tip of stack 17: 3 done, 41 built, 4 owed.** The list below was written at the start of the series,
when 45 rows were owed; the wrappers since written build 41 of them (`nm -gU` of the gated
`libSecurityBackports.dylib` defines each), marked **built**. **Built** means the entry point exists and answers what
its row says; only the three **done** ones are measured on the release. **Owed** is what is left: the four whose
entry point does not exist yet (`sec_protocol_options_set_local_identity` and the challenge, key-update and verify
block setters). The section "Why each group is owed" below is the plan those wrappers were written from.

| api | header | line | availability | file | state |
| --- | --- | --- | --- | --- | --- |
| `sec_protocol_metadata_get_negotiated_protocol` | Metadata | :79 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_copy_peer_public_key` | Metadata | :94 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_get_negotiated_tls_protocol_version` | Metadata | :109 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | ios13.json | **done** |
| `sec_protocol_metadata_get_negotiated_protocol_version` | Metadata | :125 | - | ios11.json | **built** |
| `sec_protocol_metadata_get_negotiated_tls_ciphersuite` | Metadata | :140 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | ios13.json | **done** |
| `sec_protocol_metadata_get_negotiated_ciphersuite` | Metadata | :156 | - | ios11.json | **built** |
| `sec_protocol_metadata_get_early_data_accepted` | Metadata | :171 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_access_peer_certificate_chain` | Metadata | :190 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_access_ocsp_response` | Metadata | :209 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_access_supported_signature_algorithms` | Metadata | :229 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_access_distinguished_names` | Metadata | :248 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_access_pre_shared_keys` | Metadata | :267 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | ios13.json | **done** |
| `sec_protocol_metadata_get_server_name` | Metadata | :287 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_peers_are_equal` | Metadata | :306 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_challenge_parameters_are_equal` | Metadata | :328 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_create_secret` | Metadata | :352 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_metadata_create_secret_with_context` | Metadata | :383 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_are_equal` | Options | :86 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_set_local_identity` | Options | :102 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **owed** |
| `sec_protocol_options_append_tls_ciphersuite` | Options | :118 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_add_tls_ciphersuite` | Options | :134 | - | ios11.json | **built** |
| `sec_protocol_options_append_tls_ciphersuite_group` | Options | :150 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_add_tls_ciphersuite_group` | Options | :166 | - | ios11.json | **built** |
| `sec_protocol_options_set_tls_min_version` | Options | :183 | - | ios11.json | **built** |
| `sec_protocol_options_set_min_tls_protocol_version` | Options | :199 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_get_default_min_tls_protocol_version` | Options | :211 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_get_default_min_dtls_protocol_version` | Options | :223 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_set_tls_max_version` | Options | :240 | - | ios11.json | **built** |
| `sec_protocol_options_set_max_tls_protocol_version` | Options | :256 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_get_default_max_tls_protocol_version` | Options | :268 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_get_default_max_dtls_protocol_version` | Options | :280 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_add_tls_application_protocol` | Options | :321 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_server_name` | Options | :338 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_diffie_hellman_parameters` | Options | :354 | - | ios11.json | **built** |
| `sec_protocol_options_add_pre_shared_key` | Options | :373 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_pre_shared_key_identity_hint` | Options | :390 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_set_pre_shared_key_selection_block` | Options | :439 | API_AVAILABLE(macos(10.15), ios(13.0), watchos(6.0), tvos(13.0)) | absent_Security.json | **built** |
| `sec_protocol_options_set_tls_tickets_enabled` | Options | :457 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_is_fallback_attempt` | Options | :479 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_resumption_enabled` | Options | :495 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_false_start_enabled` | Options | :511 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_ocsp_enabled` | Options | :527 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_sct_enabled` | Options | :543 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_tls_renegotiation_enabled` | Options | :559 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_peer_authentication_required` | Options | :575 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **built** |
| `sec_protocol_options_set_key_update_block` | Options | :729 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **owed** |
| `sec_protocol_options_set_challenge_block` | Options | :748 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **owed** |
| `sec_protocol_options_set_verify_block` | Options | :767 | API_AVAILABLE(macos(10.14), ios(12.0), watchos(5.0), tvos(12.0)) | ios11.json | **owed** |

## Why each group is owed, and what the answer will be

### `sec_protocol_options_*` - a settings holder

The port supplies its own class, `CharonSecProtocolOptions : NSObject <OS_sec_protocol_options>`, and
**the setter holds the value** - a version, a ciphersuite, an ALPN string, a block, copied and held -
while nothing in 6.1.3 ever reads it, because the release has no TLS stack that takes a
`sec_protocol_options_t`. Every row is therefore **`inert`**: callable, the value held, and the effect
stated as *the handshake ignores it*.

**The two that are NOT this shape** are the four `get_default_*_protocol_version` accessors, which take
no options object and are pure: they answer a documented default and are `implemented` rather than
`inert`, because the value they return is a fact rather than a setting nobody reads.

### `sec_protocol_metadata_*` beyond the three done

A `sec_protocol_metadata_t` is handed to a TLS callback by the handshake that negotiated it, and 6.1.3
has no such stack, so **nothing produces one**. Each accessor answers the header's documented absence,
or - where the header names none, as the two enum getters do - the only answer that is not a lie about
a negotiation, with the cost stated in the row.

## What is NOT on this list

`sec_identity_*`, `sec_certificate_*` and `sec_trust_*` are a different family and are in the
security-r3 series (`packages/a/apple-backports/facts/Security/SecObjectWrappers.md`), not here.

## The four defaults, and what they are worth

The `@return` above each reads *"The default minimum TLS version"*, *"The default maximum DTLS version"*
and so on: it **names the quantity and does not state a number**. So the classification is `implemented`
— the function answers the documented default — while the **number** is a decision from the release's
stack, not a reading:

| api | line | returns | value |
| --- | --- | --- | --- |
| `...get_default_min_tls_protocol_version` | `:211` | `tls_protocol_version_TLSv10` | `0x0301` |
| `...get_default_max_tls_protocol_version` | `:268` | `tls_protocol_version_TLSv12` | `0x0303` |
| `...get_default_min_dtls_protocol_version` | `:223` | `tls_protocol_version_DTLSv10` | `0xfeff` |
| `...get_default_max_dtls_protocol_version` | `:280` | `tls_protocol_version_DTLSv10` | `0xfeff` |

**`TLSv13` (0x0304) and `DTLSv12` (0xfefd) are never returned**, because 6.1.3 cannot negotiate them and
a caller asking what it would get by default must not be told about a version the release cannot honour.
The host case asserts that negatively as two rows of its own (`no-tls13`, `no-dtls12`), and the mutation
returns `TLSv13` so the difference names the value *and* the un-honourable version.

**This is recorded as a crutch.** The numbers come from the release's stack constants — `kTLSProtocol12`
as its top, DTLS 1.0 only — and **not** from a guest measurement. `SSLCreateContext` is iOS 5+ and needs
no identity, so the measurement is feasible; until it runs, these four are a decision, and the row says so.

**What was grepped for and came back empty**, recorded rather than omitted: `kSSLProtocol2` and
`kSSLProtocol3` in the 16.4 SDK's `CFNetwork.h`, and `kSSLProtocolTLSv1_2` in the same header. Both greps
returned nothing, so there was no release-side constant to defer to and the fallback stands.

## The comparator is implemented; the setters are not

`sec_protocol_options_are_equal` (`:86`) reads back the settings the port **holds**, so it is
`implemented` — it is the one thing the port can answer truthfully. The equality is its own state and
nothing else: a comparison against the release's stack would compare nothing, because there is no such
stack. The setters are built, each inert with the effect that the handshake ignores it, except the four named at the top, which remain owed.

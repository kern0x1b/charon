// The declarations of one framework, from clang's own AST through libclang: the source of the spec's Objective-C and C facts.
//
// usage: decls --version | --target | --digest TEXT | --list
//        decls [--doc] [--timeout SECONDS] <framework>
// The SDK is IR_SDK. <framework> is a name --list prints: a framework of System/Library/Frameworks (a nested one is Outer/Inner), or a
// usr/include module of the sweep (IR_USR_MODULES). decls resolves the framework's headers itself, from its module map, by the rule
// of ir.lua's sweep (module_headers below): the sweep and the doc mode share that one code path. The headers become one unsaved buffer
// of #import lines, so nothing is written to disk. IR_RESOURCE, if set, is the compiler's resource directory (default: libclang's).
// A framework's own declarations are those under its Headers/; a usr/include module's are those written in the directories of its
// headers. --target prints the target the rows are compiled for.
//
// --doc (the doc-time mode, for the doc generator): the same pass and the same keys, but the output is one row per declaration
// with ten cells instead of the IR's rows: framework, kind, usr, container, name, side (the IR's own values), the parameter names
// (separated by " | "), the brief of the doc comment and its raw text as clang parses them (libclang's brief and raw comment text),
// and the declaration as written. Each cell is escaped (a backslash, a tab, a line feed and a carriage return as \\, \t, \n, \r),
// so a declaration is one line; an empty cell has no such text. Nothing is written to a file, no IR row, conflict or census is
// written, and a module that does not parse is an error (status 1, its count on stderr, no output).
//
// The preprocessor evaluates every #if (TARGET_OS_*, __has_feature, availability macros) the way the iOS compile does, so the
// AST holds the declarations of the iOS branch and nothing else. A declaration is emitted when its spelling location (or, for a
// macro, its expansion) is under <framework-root>/Headers.
//
// Output: one TSV row per declaration on stdout, 18 columns: the 16 of design-foundation.md section 5.1, the declaration as written
// (decl, display only: it is not part of any hash) and the availability texts (message). A declaration that is repeated in the
// framework is resolved here (the rule of section 5.2 and ruling D3): the availability of the defining declaration counts, a forward
// declaration never does, a category's own availability overrides the class's only when it is later. A key whose declarations still
// disagree is written as a row of kind conflict and all its variants follow as rows: ir.lua merges them by the rule of avail.lua.
// "--digest TEXT" prints the availability hash of a text, the one the rows carry.
// The rows are written only when the parse has no error diagnostic: a header that does not parse yields one unparsed row, with the
// first diagnostic as its reason. Exit status 1 is a usage or parse failure; a timeout ends the process by SIGALRM.
#include <clang-c/Index.h>
#include <CommonCrypto/CommonDigest.h>

#include <unistd.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <map>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

namespace {

std::string text(CXString s) {
  const char* c = clang_getCString(s);
  std::string out = c ? c : "";
  clang_disposeString(s);
  return out;
}

// A TSV cell: a tab or a line break inside a cell would split the row, so each becomes a space.
std::string cell(std::string s) {
  for (char& ch : s) {
    if (ch == '\t' || ch == '\n' || ch == '\r') ch = ' ';
  }
  return s;
}

// An empty cell is "-": a class extension has no name, and "-" is what the IR writes for "none".
std::string filled(std::string s) {
  return s.empty() ? "-" : s;
}

std::string version(CXVersion v) {
  if (v.Major == -1) return "-";
  char buf[64];
  // a version written as ios(16) has no minor part: clang reports the minor as -1
  if (v.Minor == -1) std::snprintf(buf, sizeof buf, "%d", v.Major);
  else if (v.Subminor == -1) std::snprintf(buf, sizeof buf, "%d.%d", v.Major, v.Minor);
  else std::snprintf(buf, sizeof buf, "%d.%d.%d", v.Major, v.Minor, v.Subminor);
  return buf;
}

// platform=introduced/deprecated/obsoleted/unavailable, for every platform clang has a record for.
std::string availability(CXCursor c) {
  int always_deprecated = 0, always_unavailable = 0;
  CXString deprecated_message, unavailable_message;
  CXPlatformAvailability records[16];
  int n = clang_getCursorPlatformAvailability(c, &always_deprecated, &deprecated_message, &always_unavailable,
                                              &unavailable_message, records, 16);
  clang_disposeString(deprecated_message);
  clang_disposeString(unavailable_message);
  int count = n < 16 ? n : 16;
  // the platforms in name order: each entry begins with its platform name and '=', which sorts as the name does
  std::vector<std::string> entries;
  for (int i = 0; i < count; ++i) {
    // the record owns its platform string: it is read here and released by clang_disposeCXPlatformAvailability below
    entries.push_back(std::string(clang_getCString(records[i].Platform)) + "=" + version(records[i].Introduced) + "/" +
                      version(records[i].Deprecated) + "/" + version(records[i].Obsoleted) + "/" +
                      (records[i].Unavailable ? "1" : "0"));
  }
  for (int i = 0; i < count; ++i) clang_disposeCXPlatformAvailability(&records[i]);
  std::sort(entries.begin(), entries.end());
  std::string out;
  if (always_unavailable) out += "*unavailable";
  if (always_deprecated) out += std::string(out.empty() ? "" : " ") + "*deprecated";
  for (size_t i = 0; i < entries.size(); ++i) {
    out += (out.empty() ? "" : i == 0 ? " " : ",") + entries[i];
  }
  return out.empty() ? "-" : out;
}

// The iOS introduction of a declaration as major * 10000 + minor * 100 + subminor; 0 when it names no iOS version.
int introduced_ios(CXCursor c) {
  int always_deprecated = 0, always_unavailable = 0;
  CXString deprecated_message, unavailable_message;
  CXPlatformAvailability records[16];
  int n = clang_getCursorPlatformAvailability(c, &always_deprecated, &deprecated_message, &always_unavailable,
                                              &unavailable_message, records, 16);
  clang_disposeString(deprecated_message);
  clang_disposeString(unavailable_message);
  int intro = 0;
  int count = n < 16 ? n : 16;
  for (int i = 0; i < count; ++i) {
    const CXVersion& v = records[i].Introduced;
    if (std::strcmp(clang_getCString(records[i].Platform), "ios") == 0 && v.Major != -1) {
      intro = v.Major * 10000 + (v.Minor < 0 ? 0 : v.Minor) * 100 + (v.Subminor < 0 ? 0 : v.Subminor);
    }
  }
  for (int i = 0; i < count; ++i) clang_disposeCXPlatformAvailability(&records[i]);
  return intro;
}

// n = nonnull, l = nullable, u = unspecified, L = nullable result, - = no nullability written
std::string nullability(CXType t) {
  switch (clang_Type_getNullability(t)) {
    case CXTypeNullability_NonNull: return "n";
    case CXTypeNullability_Nullable: return "l";
    case CXTypeNullability_Unspecified: return "u";
    case CXTypeNullability_NullableResult: return "L";
    default: return "-";
  }
}

// The name of a declaration. An anonymous enum, struct or union has none in the header; libclang spells it with the location of
// its declaration in some versions and not in others, so it is "-" in every version.
std::string declared_name(CXCursor c) {
  if (clang_Cursor_isAnonymous(c)) return "-";
  return text(clang_getCursorSpelling(c));
}

// The type without the nullability written on it, which the nullability column holds. The parse keeps the attributed type of a written
// nullability (CXTranslationUnit_IncludeAttributedTypes); its modified type is the type the spelling names. An instancetype is also
// attributed, but it has no nullability, so it keeps its spelling.
CXType unqualified(CXType t) {
  while (t.kind == CXType_Attributed && clang_Type_getNullability(t) != CXTypeNullability_Invalid) t = clang_Type_getModifiedType(t);
  return t;
}

// clang spells an anonymous type with its location and sometimes its kind: "enum (unnamed at /abs/path/NSString.h:68:1)",
// "union (unnamed union at /abs/path/...)", and "union (unnamed)" in another version. The location is the host's SDK path and a
// line of the header, and the words inside the parentheses differ between versions, so every anonymous type is spelled
// "(unnamed)" (or "(anonymous)"); the kind outside the parentheses is kept.
std::string without_location(std::string s) {
  for (const char* open : {"(unnamed", "(anonymous"}) {
    for (size_t at = s.find(open); at != std::string::npos; at = s.find(open, at + 1)) {
      size_t close = s.find(')', at);
      if (close == std::string::npos) break;
      s.replace(at, close - at + 1, std::string(open) + ")");
    }
  }
  return s;
}

std::string spelled(CXType t) { return without_location(text(clang_getTypeSpelling(unqualified(t)))); }

// The name of the macro clang prints in front of a type it keeps as a macro-qualified type (CF_REFINED_FOR_SWIFT CFStringRef, API_AVAILABLE
// NSString *const): a leading word of capitals, then the type. A type name is not all capitals followed by a type, and clang prints a
// const after such a macro, never before it.
std::string without_macro_word(const std::string& s) {
  size_t space = s.find(' ');
  if (space == std::string::npos || space < 2 || s.size() == space + 1) return s;
  for (size_t i = 0; i < space; ++i) {
    unsigned char ch = (unsigned char)s[i];
    if (!(std::isupper(ch) || std::isdigit(ch) || ch == '_')) return s;
  }
  unsigned char next = (unsigned char)s[space + 1];
  if (!(std::isalpha(next) || next == '_')) return s;
  return s.substr(space + 1);
}

// The type of a declared variable or field, as the declaration has it. clang prints attribute sugar in front of the type (an
// availability macro such as API_AVAILABLE, a Swift attribute, the nullability word after it), and that sugar can drop the top-level
// const: CG_EXTERN const CFStringRef __nonnull kCGContentAverageLightLevel prints as CF_REFINED_FOR_SWIFT CFStringRef, though the
// variable is const. So the attributes are taken off, and the const is read from the canonical type (every top-level qualifier
// of the declared type is in it), not from the printed sugar. The nullability column holds the nullability; a pointer's const follows the star.
std::string declared_type(CXType t) {
  CXType bare = t;
  while (bare.kind == CXType_Attributed) bare = clang_Type_getModifiedType(bare);
  std::string s = text(clang_getTypeSpelling(bare));
  if (bare.kind == CXType_Unexposed) s = without_macro_word(s);
  // the canonical type keeps every qualifier the variable has at its top level; the printed sugar can drop one
  if (clang_isConstQualifiedType(clang_getCanonicalType(t))) {
    bool leading = s.compare(0, 6, "const ") == 0;
    bool trailing = s.size() >= 5 && s.compare(s.size() - 5, 5, "const") == 0;
    if (!leading && !trailing && !s.empty()) s = s.back() == '*' ? s + "const" : "const " + s;
  }
  return without_location(s);
}

// The offset in its file of a source location (the expansion, for a token a macro produced).
unsigned offset_of(CXSourceLocation loc) {
  CXFile file;
  unsigned line = 0, column = 0, offset = 0;
  clang_getExpansionLocation(loc, &file, &line, &column, &offset);
  return offset;
}

// A token of a declaration as written: its spelling, its offsets in the file, and whether it is a string literal.
struct Token {
  std::string spelling;
  unsigned start, end;
  bool literal;
};

// The tokens of a declaration's extent, comments left out. clang splits an Objective-C directive into "@" and its word ("@" "end"):
// the two are one token when they touch.
std::vector<Token> tokens_of(CXTranslationUnit tu, CXCursor c) {
  CXToken* tokens = nullptr;
  unsigned count = 0;
  clang_tokenize(tu, clang_getCursorExtent(c), &tokens, &count);
  std::vector<Token> toks;
  for (unsigned i = 0; i < count; ++i) {
    if (clang_getTokenKind(tokens[i]) == CXToken_Comment) continue;
    CXSourceRange extent = clang_getTokenExtent(tu, tokens[i]);
    Token t{text(clang_getTokenSpelling(tu, tokens[i])), offset_of(clang_getRangeStart(extent)),
            offset_of(clang_getRangeEnd(extent)), clang_getTokenKind(tokens[i]) == CXToken_Literal};
    if (!toks.empty() && toks.back().spelling == "@" && toks.back().end == t.start) {
      toks.back().spelling += t.spelling;
      toks.back().end = t.end;
      toks.back().literal = false;
      continue;
    }
    toks.push_back(t);
  }
  clang_disposeTokens(tu, tokens, count);
  return toks;
}

// The declaration as written: its tokens, with each run of whitespace or comment as one space and macros as spelled. The head of
// a class, protocol or category stops before its members; a body in braces is written as "{ ... }"; a trailing ";" is dropped.
// The deprecation text a declaration writes in its macros: the first string of API_DEPRECATED("TEXT", ...), the replacement of
// API_DEPRECATED_WITH_REPLACEMENT("NAME", ...) (read as "Use NAME instead"), or the message="TEXT" of an availability attribute.
// Consecutive string literals are one text. libclang does not report these texts for an availability attribute.
std::string written_deprecation(const std::vector<Token>& toks) {
  for (size_t i = 0; i + 2 < toks.size(); ++i) {
    const std::string& word = toks[i].spelling;
    bool macro = (word == "API_DEPRECATED" || word == "API_DEPRECATED_WITH_REPLACEMENT") && toks[i + 1].spelling == "(";
    bool attribute = word == "message" && toks[i + 1].spelling == "=";
    if (!macro && !attribute) continue;
    std::string body;
    size_t j = i + 2;
    for (; j < toks.size() && toks[j].literal; ++j) body += toks[j].spelling.substr(1, toks[j].spelling.size() - 2);
    if (j == i + 2) continue;
    return word == "API_DEPRECATED_WITH_REPLACEMENT" ? "Use " + body + " instead" : body;
  }
  return "";
}

// The texts of the availability attributes, for the message column: "deprecated: TEXT" and "unavailable: TEXT", joined by " | ".
std::string message_of(CXTranslationUnit tu, CXCursor c) {
  int always_deprecated = 0, always_unavailable = 0;
  CXString deprecated_message, unavailable_message;
  CXPlatformAvailability records[16];
  int n = clang_getCursorPlatformAvailability(c, &always_deprecated, &deprecated_message, &always_unavailable,
                                              &unavailable_message, records, 16);
  int count = n < 16 ? n : 16;
  for (int i = 0; i < count; ++i) clang_disposeCXPlatformAvailability(&records[i]);
  std::string out;
  std::string deprecated = text(deprecated_message);
  std::string written = written_deprecation(tokens_of(tu, c));
  if (!written.empty()) deprecated = written;
  std::string unavailable = text(unavailable_message);
  if (!deprecated.empty()) out += "deprecated: " + deprecated;
  if (!unavailable.empty()) out += std::string(out.empty() ? "" : " | ") + "unavailable: " + unavailable;
  return cell(out);
}

// The key of a source position: its file and offset.
std::string position_key(CXSourceLocation location) {
  CXFile file = nullptr;
  unsigned line = 0, column = 0, offset = 0;
  clang_getExpansionLocation(location, &file, &line, &column, &offset);
  if (!file) return "";
  return text(clang_getFileName(file)) + ":" + std::to_string(offset);
}

std::string decl_text(CXTranslationUnit tu, const std::map<std::string, std::string>& macro_at, CXCursor c) {
  // A declaration a macro produced is written as the macro's name, as spelled at the use site (the macro uses come from the
  // preprocessing record: see collect_macro_uses).
  auto macro = macro_at.find(position_key(clang_getCursorLocation(c)));
  if (macro != macro_at.end()) return cell(macro->second);
  CXCursorKind kind = clang_getCursorKind(c);
  bool objc_head = kind == CXCursor_ObjCInterfaceDecl || kind == CXCursor_ObjCCategoryDecl || kind == CXCursor_ObjCProtocolDecl;
  std::vector<Token> toks = tokens_of(tu, c);
  std::string out;
  unsigned previous_end = 0;
  bool any = false;
  for (size_t i = 0; i < toks.size(); ++i) {
    const std::string& spelling = toks[i].spelling;
    if (objc_head && (spelling == "{" || spelling == "@end" || spelling == "-" || spelling == "+" || spelling == "@property" ||
                      spelling == "@optional" || spelling == "@required")) {
      break;
    }
    if (any && toks[i].start > previous_end) out += ' ';
    if (spelling == "{") {  // a body of a tag, typedef, function or variable: written, not spelled out
      out += "{ ... }";
      int depth = 0;
      for (; i < toks.size(); ++i) {
        if (toks[i].spelling == "{") ++depth;
        if (toks[i].spelling == "}" && --depth == 0) break;
      }
      previous_end = i < toks.size() ? toks[i].end : previous_end;
      any = true;
      continue;
    }
    out += spelling;
    previous_end = toks[i].end;
    any = true;
  }
  if (!out.empty() && out.back() == ';') out.pop_back();
  // a getter or setter clang synthesises from a property has no declaration of its own: its extent is the property's name, and the
  // property's row carries the declaration
  bool method = kind == CXCursor_ObjCInstanceMethodDecl || kind == CXCursor_ObjCClassMethodDecl;
  if (method && (out.empty() || (out[0] != '-' && out[0] != '+'))) out = "-";
  return cell(out.empty() ? "-" : out);
}

// One declaration's row (the 13 fields the extractor writes per declaration, and the decl text).
struct Row {
  std::string kind, usr, container, name, side, header, line, avail, nullab, type, params, attrs, value, decl, message;
  std::string brief, comment, params_names;  // the doc mode only (--doc): the doc comment and the parameter names
};

// A declaration with the facts resolution needs. defining: it is the defining declaration of its entity (a definition, or a
// member of the class's or protocol's own @interface or @protocol). extension: it is written in a category or class extension.
// intro: the iOS introduction of its availability (0 when none).
struct Record {
  Row row;
  bool defining;
  bool extension;
  int intro;
};

struct Context {
  std::string framework;
  std::vector<std::string> own;  // the directories whose headers are the framework's own, each with its trailing slash
  CXTranslationUnit tu;
  std::vector<Record> records;  // every declaration in source order; resolve() writes them
  std::set<std::string> tags;   // the tags emitted, by USR: each is one declaration
  std::map<std::string, std::string> macro_at;  // file:offset of a macro use -> the macro's name
  std::string out;              // the rows, written only when the parse has no error
  bool doc = false;             // the doc mode (--doc): the doc rows of the declarations only
};

// The file and line where a declaration is written. A declaration a macro produces (AV_INIT_UNAVAILABLE expands to init and new)
// is placed at the expansion, where the header uses the macro: the spelling of its tokens is in the macro's header, and the
// spelling location differs between libclang versions.
bool in_framework(CXCursor c, const Context& ctx, std::string* file_out, unsigned* line_out) {
  CXSourceLocation loc = clang_getCursorLocation(c);
  CXFile file;
  unsigned line = 0, column = 0, offset = 0;
  clang_getExpansionLocation(loc, &file, &line, &column, &offset);
  if (!file) return false;
  std::string path = text(clang_getFileName(file));
  for (const std::string& dir : ctx.own) {
    if (path.compare(0, dir.size(), dir) == 0) {
      *file_out = path.substr(dir.size());
      *line_out = line;
      return true;
    }
  }
  return false;
}

// The first 8 bytes of SHA-256, as 16 hex digits: the declaration hash and the availability hash.
std::string digest16(const std::string& s) {
  unsigned char d[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(s.data(), (CC_LONG)s.size(), d);
  std::string out;
  char hex[3];
  for (int i = 0; i < 8; ++i) {
    std::snprintf(hex, sizeof hex, "%02x", d[i]);
    out += hex;
  }
  return out;
}

// The declaration hash covers what the declaration says and not where it is written: no header, line, availability or decl text.
// Fields are joined with the unit separator (0x1f), which no field contains.
std::string declaration_hash(const Row& r) {
  const char* fields[] = {r.kind.c_str(), r.usr.c_str(), r.container.c_str(), r.name.c_str(), r.side.c_str(), r.type.c_str(),
                          r.params.c_str(), r.nullab.c_str(), r.attrs.c_str(), r.value.c_str()};
  std::string canonical;
  for (const char* f : fields) {
    canonical += f;
    canonical += '\x1f';
  }
  return digest16(canonical);
}

// The doc-time text of a declaration (--doc): its brief and raw doc comment as clang parses them, and the names of its parameters.
// It is attached when the record is made, while the cursor is at hand.
void attach_doc(CXCursor c, Row* r) {
  // only the /// and /** */ forms are doc comments here (ruling of 2026-10-10): clang also attaches //! and /*! comments, which are not
  // kept, with their brief; a declaration with only those has no doc text
  int n = clang_Cursor_getNumArguments(c);
  for (int i = 0; i < n; ++i) {
    if (i) r->params_names += " | ";
    r->params_names += text(clang_getCursorSpelling(clang_Cursor_getArgument(c, (unsigned)i)));
  }
  std::string raw = text(clang_Cursor_getRawCommentText(c));
  if (raw.compare(0, 3, "///") != 0 && raw.compare(0, 3, "/**") != 0) return;
  r->comment = raw;
  r->brief = text(clang_Cursor_getBriefCommentText(c));
}

// A cell of the doc mode with its backslashes, tabs and line breaks escaped, so that a declaration is one line.
std::string escaped(const std::string& s) {
  std::string out;
  for (char ch : s) {
    switch (ch) {
      case '\\': out += "\\\\"; break;
      case '\t': out += "\\t"; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      default: out += ch;
    }
  }
  return out;
}

// The doc-time row of a declaration (--doc): ten escaped cells, tab separated and newline terminated.
void write_doc(Context& ctx, const Row& r) {
  const std::string cells[] = {ctx.framework, r.kind, r.usr, r.container, r.name, r.side, r.params_names, r.brief, r.comment, r.decl};
  for (size_t i = 0; i < sizeof cells / sizeof cells[0]; ++i) {
    if (i) ctx.out += '\t';
    ctx.out += escaped(cells[i]);
  }
  ctx.out += '\n';
}

// The 17 cells of a declaration row, tab separated and newline terminated.
void write_row(Context& ctx, const Row& r) {
  if (ctx.doc) {
    write_doc(ctx, r);
    return;
  }
  const std::string cells[] = {cell(ctx.framework), r.kind,                 filled(cell(r.usr)),
                               filled(cell(r.container)), filled(cell(r.name)), r.side,
                               filled(cell(r.header)), r.line,              filled(cell(r.avail)),
                               r.nullab,            filled(cell(r.type)),   filled(cell(r.params)),
                               filled(cell(r.attrs)), filled(cell(r.value)), declaration_hash(r),
                               digest16(r.avail),   filled(cell(r.decl)),   filled(cell(r.message))};
  for (size_t i = 0; i < sizeof cells / sizeof cells[0]; ++i) {
    if (i) ctx.out += '\t';
    ctx.out += cells[i];
  }
  ctx.out += '\n';
}

// A conflict row: the key of a declaration that is declared more than once with different availability, how it was resolved
// ("defining", "stricter-extension" or "merged"), and the availability variants. ir.lua lists these for review.
void write_conflict(Context& ctx, const Row& key, const std::string& resolution, const std::string& variants) {
  if (ctx.doc) return;  // the doc mode writes declarations only
  const std::string cells[] = {cell(ctx.framework), "conflict",   filled(cell(key.usr)), filled(cell(key.container)),
                               filled(cell(key.name)), key.side,  key.kind,              "-",
                               resolution,            "-",        variants,              "-",
                               "-",                   "-",        "-",                   "-",
                               "-",                   "-"};
  for (size_t i = 0; i < sizeof cells / sizeof cells[0]; ++i) {
    if (i) ctx.out += '\t';
    ctx.out += cells[i];
  }
  ctx.out += '\n';
}

void record(Context& ctx, CXCursor c, const Row& r, bool defining, bool extension, int intro) {
  Row kept = r;
  if (ctx.doc) attach_doc(c, &kept);
  ctx.records.push_back(Record{kept, defining, extension, intro});
}

// The rule of section 5.2 and the ruling D3. Records of one key are grouped in source order.
//  - all the same availability: the first is written (redeclarations that differ only in parameter names are one declaration);
//  - a defining record exists: its availability counts. A category or extension record with another availability overrides it
//    only when its iOS introduction is later (the stricter, listed as stricter-extension); an earlier one is ignored (defining).
//    Any other record with another availability is merged (ir.lua applies the rule of avail.lua to all the variants);
//  - no defining record: merged, with every availability written.
void resolve(Context& ctx) {
  std::map<std::string, std::vector<size_t>> groups;
  std::vector<std::string> order;
  for (size_t i = 0; i < ctx.records.size(); ++i) {
    const Row& r = ctx.records[i].row;
    std::string key = r.kind + "\t" + r.usr + "\t" + r.container + "\t" + r.name + "\t" + r.side;
    if (groups.find(key) == groups.end()) order.push_back(key);
    groups[key].push_back(i);
  }
  for (const std::string& key : order) {
    const std::vector<size_t>& group = groups[key];
    const Record& first = ctx.records[group[0]];
    std::vector<std::string> variants;
    std::vector<size_t> first_of_variant;
    for (size_t i : group) {
      const std::string& avail = ctx.records[i].row.avail;
      if (std::find(variants.begin(), variants.end(), avail) == variants.end()) {
        variants.push_back(avail);
        first_of_variant.push_back(i);
      }
    }
    if (variants.size() == 1) {
      write_row(ctx, first.row);
      continue;
    }
    size_t base = group.size();
    for (size_t i : group) {
      if (ctx.records[i].defining) {
        base = i;
        break;
      }
    }
    std::string resolution = "merged";
    std::vector<size_t> written = first_of_variant;
    if (base != group.size()) {
      size_t chosen = base;
      bool stricter = false, unresolved = false;
      for (size_t i : group) {
        const Record& r = ctx.records[i];
        if (r.row.avail == ctx.records[chosen].row.avail) continue;
        if (r.extension) {
          if (r.intro > ctx.records[chosen].intro) {
            chosen = i;
            stricter = true;
          }
        } else {
          unresolved = true;
        }
      }
      if (!unresolved) {
        resolution = stricter ? "stricter-extension" : "defining";
        written = {chosen};
      }
    }
    std::string joined;
    for (const std::string& v : variants) joined += (joined.empty() ? "" : " | ") + v;
    for (size_t i : written) write_row(ctx, ctx.records[i].row);
    if (variants.size() > 1) write_conflict(ctx, first.row, resolution, joined);
  }
}

// A tag is one declaration: the first declaration of its USR in the framework is the one emitted (tag_is_emitted prefers the definition).
bool first_tag(Context& ctx, CXCursor c) {
  return ctx.tags.insert(text(clang_getCursorUSR(c))).second;
}

// A tag (enum, struct, union) is one declaration: its definition where this framework writes one, otherwise its first declaration
// in the framework (an opaque type, or a definition written elsewhere). A forward declaration that the framework's own definition
// supersedes is not emitted, and neither are its children, which belong to the definition.
bool tag_is_emitted(CXCursor c, Context& ctx) {
  std::string file;
  unsigned line = 0;
  CXCursor definition = clang_getCursorDefinition(c);
  if (!clang_Cursor_isNull(definition) && in_framework(definition, ctx, &file, &line)) return clang_isCursorDefinition(c);
  return first_tag(ctx, c);
}

std::string parameters(CXCursor c, std::string* nullab) {
  int n = clang_Cursor_getNumArguments(c);
  std::string out;
  for (int i = 0; i < n; ++i) {
    CXCursor arg = clang_Cursor_getArgument(c, (unsigned)i);
    if (i) out += " | ";
    out += spelled(clang_getCursorType(arg)) + " " + text(clang_getCursorSpelling(arg));
    if (i) *nullab += ",";
    *nullab += nullability(clang_getCursorType(arg));
  }
  return out.empty() ? "-" : out;
}

CXChildVisitResult visit(CXCursor c, CXCursor parent, CXClientData data);

// Every macro use of the translation unit, by position (the preprocessing record is parsed for this).
CXChildVisitResult collect_macro_uses(CXCursor c, CXCursor parent, CXClientData data) {
  (void)parent;
  if (clang_getCursorKind(c) == CXCursor_MacroExpansion) {
    Context& ctx = *static_cast<Context*>(data);
    ctx.macro_at[position_key(clang_getCursorLocation(c))] = text(clang_getCursorSpelling(c));
  }
  return CXChildVisit_Continue;
}

// What a member's context says about it: an extension or category statement, or the defining @interface or @protocol of its class.
struct Nest {
  Context* ctx;
  std::string name;       // the class, protocol or tag the declarations belong to ("-" at the top level)
  std::string category;   // the name of the category they are written in ("" for a class extension, an @interface or a @protocol)
  bool extension;         // written in a category or class extension
  bool defining_context;  // written in the defining @interface or @protocol (not a forward declaration)
};

void method_row(Context& ctx, CXCursor c, bool klass, const Nest& nest) {
  std::string file;
  unsigned line = 0;
  if (!in_framework(c, ctx, &file, &line)) return;
  Row r;
  r.kind = "method";
  r.usr = text(clang_getCursorUSR(c));
  r.container = nest.category.empty() ? "-" : nest.category;
  r.name = text(clang_getCursorSpelling(c));
  r.side = klass ? "+" : "-";
  r.header = file;
  r.line = std::to_string(line);
  r.avail = availability(c);
  std::string params_nullab;
  r.params = parameters(c, &params_nullab);
  r.nullab = nullability(clang_getCursorResultType(c)) + "|" + params_nullab;
  r.type = spelled(clang_getCursorResultType(c));
  r.attrs = clang_Cursor_isObjCOptional(c) ? "optional" : "-";
  r.value = "-";
  r.message = message_of(ctx.tu, c);
  r.decl = decl_text(ctx.tu, ctx.macro_at, c);
  // a getter or setter clang synthesises from a property is no declaration of its own: it is an accessor row (the spec's members are
  // the properties, and ir.lua keeps accessors out of the shards)
  if (r.decl == "-") r.kind = "accessor";
  record(ctx, c, r, !nest.extension && nest.defining_context, nest.extension, introduced_ios(c));
}

void property_row(Context& ctx, CXCursor c, const Nest& nest) {
  std::string file;
  unsigned line = 0;
  if (!in_framework(c, ctx, &file, &line)) return;
  Row r;
  r.kind = "property";
  r.usr = text(clang_getCursorUSR(c));
  r.container = nest.category.empty() ? "-" : nest.category;
  r.name = text(clang_getCursorSpelling(c));
  r.side = "-";
  r.header = file;
  r.line = std::to_string(line);
  r.avail = availability(c);
  CXType t = clang_getCursorType(c);
  r.type = spelled(t);
  r.nullab = nullability(t);
  r.params = "-";
  unsigned bits = clang_Cursor_getObjCPropertyAttributes(c, 0);
  std::string attrs;
  auto add = [&attrs](const std::string& s) {
    if (!attrs.empty()) attrs += ",";
    attrs += s;
  };
  if (bits & CXObjCPropertyAttr_readonly) add("readonly");
  if (bits & CXObjCPropertyAttr_copy) add("copy");
  if (bits & CXObjCPropertyAttr_retain) add("retain");
  if (bits & CXObjCPropertyAttr_assign) add("assign");
  if (bits & CXObjCPropertyAttr_weak) add("weak");
  if (bits & CXObjCPropertyAttr_strong) add("strong");
  if (bits & CXObjCPropertyAttr_nonatomic) add("nonatomic");
  if (bits & CXObjCPropertyAttr_atomic) add("atomic");
  if (bits & CXObjCPropertyAttr_class) add("class");
  if (bits & CXObjCPropertyAttr_getter) add("getter=" + text(clang_Cursor_getObjCPropertyGetterName(c)));
  if (bits & CXObjCPropertyAttr_setter) add("setter=" + text(clang_Cursor_getObjCPropertySetterName(c)));
  r.attrs = attrs.empty() ? "-" : attrs;
  r.value = "-";
  r.message = message_of(ctx.tu, c);
  r.decl = decl_text(ctx.tu, ctx.macro_at, c);
  record(ctx, c, r, !nest.extension && nest.defining_context, nest.extension, introduced_ios(c));
}

void function_row(Context& ctx, CXCursor c) {
  std::string file;
  unsigned line = 0;
  if (!in_framework(c, ctx, &file, &line)) return;
  Row r;
  r.kind = "function";
  r.usr = text(clang_getCursorUSR(c));
  r.container = "-";
  r.name = text(clang_getCursorSpelling(c));
  r.side = "-";
  r.header = file;
  r.line = std::to_string(line);
  r.avail = availability(c);
  std::string params_nullab;
  r.params = parameters(c, &params_nullab);
  r.nullab = nullability(clang_getCursorResultType(c)) + "|" + params_nullab;
  r.type = spelled(clang_getCursorType(c));
  r.attrs = clang_Cursor_isVariadic(c) ? "variadic" : "-";
  r.value = "-";
  r.message = message_of(ctx.tu, c);
  r.decl = decl_text(ctx.tu, ctx.macro_at, c);
  record(ctx, c, r, clang_isCursorDefinition(c), false, introduced_ios(c));
}

// A declaration with one type (a variable, typedef, field, enum or struct) or one value (an enum constant).
void simple_row(Context& ctx, CXCursor c, const char* kind, const std::string& type, const std::string& nullab,
                const std::string& value, const std::string& container, bool defining) {
  std::string file;
  unsigned line = 0;
  if (!in_framework(c, ctx, &file, &line)) return;
  Row r;
  r.kind = kind;
  r.usr = text(clang_getCursorUSR(c));
  r.container = container;
  r.name = declared_name(c);
  r.side = "-";
  r.header = file;
  r.line = std::to_string(line);
  r.avail = availability(c);
  r.nullab = nullab;
  r.params = "-";
  r.type = type;
  r.attrs = "-";
  r.value = value;
  r.message = message_of(ctx.tu, c);
  r.decl = decl_text(ctx.tu, ctx.macro_at, c);
  record(ctx, c, r, defining, false, introduced_ios(c));
}

// The class a category or class extension extends: the ObjCClassRef among its children.
CXChildVisitResult class_ref(CXCursor c, CXCursor parent, CXClientData data) {
  (void)parent;
  if (clang_getCursorKind(c) != CXCursor_ObjCClassRef) return CXChildVisit_Continue;
  *static_cast<std::string*>(data) = text(clang_getCursorSpelling(c));
  return CXChildVisit_Break;
}

std::string category_class(CXCursor c) {
  std::string name = "-";
  clang_visitChildren(c, class_ref, &name);
  return name;
}

CXChildVisitResult visit(CXCursor c, CXCursor parent, CXClientData data) {
  (void)parent;
  Nest* nest = static_cast<Nest*>(data);
  Context& ctx = *nest->ctx;
  CXCursorKind kind = clang_getCursorKind(c);
  std::string file;
  unsigned line = 0;
  // a declaration outside the framework's headers is not emitted, and its children are not visited (they sit in that file)
  bool own = in_framework(c, ctx, &file, &line);
  switch (kind) {
    case CXCursor_ObjCInterfaceDecl:
    case CXCursor_ObjCCategoryDecl:
    case CXCursor_ObjCProtocolDecl: {
      if (!own) return CXChildVisit_Continue;
      // a class's @interface is its definition; a protocol is defined by its @protocol ... @end, and a forward declaration
      // (@protocol P;) is not a declaration of the framework (its definition is written elsewhere)
      bool definition = kind != CXCursor_ObjCProtocolDecl || clang_isCursorDefinition(c);
      if (!definition) return CXChildVisit_Continue;
      Row r;
      r.kind = kind == CXCursor_ObjCInterfaceDecl ? "interface" : kind == CXCursor_ObjCCategoryDecl ? "category" : "protocol";
      r.usr = text(clang_getCursorUSR(c));
      // a class extension's USR carries the file and offset of its declaration, which move with any edit above it: the class
      // name alone identifies it (c:objc(ext)Class)
      size_t at = r.usr.find('@', r.usr.find(')'));
      if (r.usr.compare(0, 10, "c:objc(ext") == 0 && at != std::string::npos) r.usr.resize(at);
      r.container = "-";
      r.name = text(clang_getCursorSpelling(c));
      r.side = "-";
      r.header = file;
      r.line = std::to_string(line);
      r.avail = availability(c);
      r.nullab = "-";
      r.type = "-";
      r.params = "-";
      r.attrs = "-";
      r.value = "-";
      r.message = message_of(ctx.tu, c);
      r.decl = decl_text(ctx.tu, ctx.macro_at, c);
      record(ctx, c, r, kind != CXCursor_ObjCCategoryDecl && definition, kind == CXCursor_ObjCCategoryDecl, introduced_ios(c));
      // the protocols a category lists belong to the class it extends, not to the category
      std::string owner = kind == CXCursor_ObjCCategoryDecl ? category_class(c) : r.name;
      bool category = kind == CXCursor_ObjCCategoryDecl;
      Nest child{nest->ctx, owner, category ? r.name : "", category, !category};
      clang_visitChildren(c, visit, &child);
      return CXChildVisit_Continue;
    }
    case CXCursor_ObjCSuperClassRef:
    case CXCursor_ObjCProtocolRef: {
      // a reference outside any class, category or protocol (a forward declaration @protocol P;) is not a conformance
      if (!own || nest->name == "-") return CXChildVisit_Continue;
      Row r;
      r.kind = kind == CXCursor_ObjCSuperClassRef ? "super" : "conforms";
      r.usr = "-";
      r.container = nest->name;
      r.name = text(clang_getCursorSpelling(c));
      r.side = "-";
      r.header = file;
      r.line = std::to_string(line);
      r.avail = "-";
      r.nullab = "-";
      r.type = "-";
      r.params = "-";
      r.attrs = "-";
      r.value = "-";
      r.decl = "-";
      record(ctx, c, r, true, false, 0);
      return CXChildVisit_Continue;
    }
    case CXCursor_ObjCInstanceMethodDecl:
      method_row(ctx, c, false, *nest);
      return CXChildVisit_Continue;
    case CXCursor_ObjCClassMethodDecl:
      method_row(ctx, c, true, *nest);
      return CXChildVisit_Continue;
    case CXCursor_ObjCPropertyDecl:
      property_row(ctx, c, *nest);
      return CXChildVisit_Continue;
    case CXCursor_VarDecl:
      if (own && clang_getCursorLinkage(c) == CXLinkage_External) {
        CXType t = clang_getCursorType(c);
        simple_row(ctx, c, "var", declared_type(t), nullability(t), "-", "-", clang_isCursorDefinition(c));
      }
      return CXChildVisit_Continue;
    case CXCursor_FunctionDecl:
      if (own) function_row(ctx, c);
      return CXChildVisit_Continue;
    case CXCursor_TypedefDecl:
      if (own) simple_row(ctx, c, "typedef", spelled(clang_getTypedefDeclUnderlyingType(c)),
                          nullability(clang_getTypedefDeclUnderlyingType(c)), "-", "-", false);
      return CXChildVisit_Continue;
    case CXCursor_EnumDecl:
      if (own && tag_is_emitted(c, ctx)) {
        std::string name = declared_name(c);
        simple_row(ctx, c, "enum", spelled(clang_getEnumDeclIntegerType(c)), "-", "-", "-", clang_isCursorDefinition(c));
        Nest child{nest->ctx, name, "", false, false};
        clang_visitChildren(c, visit, &child);
      }
      return CXChildVisit_Continue;
    case CXCursor_EnumConstantDecl:
      if (own) {
        long long value = clang_getEnumConstantDeclValue(c);
        simple_row(ctx, c, "enumconst", "-", "-", std::to_string(value), nest->name, true);
      }
      return CXChildVisit_Continue;
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl: {
      if (!own || !tag_is_emitted(c, ctx)) return CXChildVisit_Continue;
      std::string name = declared_name(c);
      simple_row(ctx, c, kind == CXCursor_StructDecl ? "struct" : "union", "-", "-", "-", "-", clang_isCursorDefinition(c));
      Nest child{nest->ctx, name, "", false, false};
      clang_visitChildren(c, visit, &child);
      return CXChildVisit_Continue;
    }
    case CXCursor_FieldDecl:
      if (own) {
        CXType t = clang_getCursorType(c);
        simple_row(ctx, c, "field", declared_type(t), nullability(t), "-", nest->name, true);
      }
      return CXChildVisit_Continue;
    default:
      return CXChildVisit_Continue;
  }
}

// The census of the translation unit: the declarations of the kinds the extractor reads, counted by where they are written: the
// framework's own, and those of other SDK headers the translation unit reaches. One census row per parsed framework; the gaps mode of
// ir.lua classifies the frameworks that have no declaration of their own with it.
struct Census {
  Context* ctx;
  std::string sdk;
  long own;
  long foreign;
};

CXChildVisitResult census_visit(CXCursor c, CXCursor parent, CXClientData data) {
  (void)parent;
  Census* census = static_cast<Census*>(data);
  switch (clang_getCursorKind(c)) {
    case CXCursor_ObjCInterfaceDecl:
    case CXCursor_ObjCCategoryDecl:
    case CXCursor_ObjCProtocolDecl:
    case CXCursor_FunctionDecl:
    case CXCursor_VarDecl:
    case CXCursor_TypedefDecl:
    case CXCursor_EnumDecl:
    case CXCursor_StructDecl:
    case CXCursor_UnionDecl:
      break;
    default:
      return CXChildVisit_Continue;
  }
  std::string file;
  unsigned line = 0;
  if (in_framework(c, *census->ctx, &file, &line)) {
    census->own++;
    return CXChildVisit_Continue;
  }
  CXFile written = nullptr;
  unsigned column = 0, offset = 0;
  clang_getExpansionLocation(clang_getCursorLocation(c), &written, &line, &column, &offset);
  if (written && text(clang_getFileName(written)).compare(0, census->sdk.size(), census->sdk) == 0) census->foreign++;
  return CXChildVisit_Continue;
}

void usage() {
  std::fprintf(stderr,
               "usage: decls --version | --target | --digest TEXT | --list\n"
               "       decls [--doc] [--timeout SECONDS] <framework>\n"
               "The SDK is IR_SDK. IR_USR_MODULES (a comma list) overrides the usr/include modules of the sweep. IR_RESOURCE, if set,\n"
               "is the compiler's resource directory; by default libclang finds its own.\n");
}

}  // namespace

// The frameworks the sweep covers, and the rule that gives each one's headers. The sweep (ir.lua) and the doc mode (--doc) both
// resolve a framework here, so the rule is written once.
namespace fs = std::filesystem;

// The target the rows are compiled for: the iOS arm64 target the spec is written against (ir.lua writes it in the meta row).
const char* const kTarget = "arm64-apple-ios26.2";

// The usr/include modules of the sweep (ruling of 2026-10-10). IR_USR_MODULES, a comma list, overrides it.
const char* const kUsrModules = "AppleArchive,Dispatch,Spatial,XPC,hvf,os,simd";

struct Framework {
  std::string name;  // as the rows carry it: a nested framework is Outer/Inner
  std::string base;  // the folder's name without .framework (a usr/include module's name)
  fs::path root;     // the .framework directory (a usr/include module: the usr/include directory)
  fs::path map;      // a usr/include module's module map
  bool usr = false;  // a module of usr/include
};

// A path as the rows and the imports carry it: lexically normal (no "." or "x/..").
std::string normal(const fs::path& p) { return p.lexically_normal().string(); }

std::string trim_space(const std::string& s) {
  size_t begin = s.find_first_not_of(" \t\r\n");
  if (begin == std::string::npos) return "";
  size_t end = s.find_last_not_of(" \t\r\n");
  return s.substr(begin, end - begin + 1);
}

bool is_file(const fs::path& p) {
  std::error_code ec;
  return fs::is_regular_file(p, ec);
}

bool is_dir(const fs::path& p) {
  std::error_code ec;
  return fs::is_directory(p, ec);
}

// The entries of a folder, sorted by path (none when the folder does not exist).
std::vector<fs::path> entries_of(const fs::path& dir) {
  std::vector<fs::path> out;
  std::error_code ec;
  for (fs::directory_iterator it(dir, ec), end; !ec && it != end; it.increment(ec)) out.push_back(it->path());
  std::sort(out.begin(), out.end());
  return out;
}

// The frameworks directly in a folder, then those nested in each one's Frameworks/ folder (named Outer/Inner). A symbolic link to a
// directory is listed as the framework it names, as it always has been (WebKit.framework links into the Cryptexes; AVFoundation's
// Frameworks/AVFAudio.framework links to the top-level AVFAudio.framework, and parses to no declaration of its own: it has no shard).
void frameworks_in(const fs::path& dir, const std::string& outer, std::vector<Framework>* out) {
  const std::string suffix = ".framework";
  for (const fs::path& p : entries_of(dir)) {
    std::string file = p.filename().string();
    if (file.size() <= suffix.size() || file.compare(file.size() - suffix.size(), suffix.size(), suffix) != 0) continue;
    if (!is_dir(p)) continue;
    Framework f;
    f.base = file.substr(0, file.size() - suffix.size());
    f.name = outer.empty() ? f.base : outer + "/" + f.base;
    f.root = p;
    out->push_back(f);
    frameworks_in(p / "Frameworks", f.name, out);
  }
}

// The name a module map line declares as a top-level module (the line starts at its first column with module or explicit module), or "".
std::string declared_module(const std::string& line) {
  static const std::regex declaration(R"re(^(?:explicit\s+)?module\s+([A-Za-z0-9_]+))re");
  std::smatch m;
  return std::regex_search(line, m, declaration) ? m[1].str() : std::string();
}

// The module map of a usr/include module: the one map (usr/include/*.modulemap, or usr/include/<dir>/module.modulemap) that declares
// the module as a top-level module. Two maps that declare it are an error.
fs::path usr_module_map(const fs::path& include, const std::string& name, std::string* error) {
  std::vector<fs::path> candidates;
  for (const fs::path& p : entries_of(include)) {
    if (p.extension() == ".modulemap" && is_file(p)) candidates.push_back(p);
    if (is_dir(p) && is_file(p / "module.modulemap")) candidates.push_back(p / "module.modulemap");
  }
  std::vector<fs::path> found;
  for (const fs::path& file : candidates) {
    std::ifstream in(file);
    for (std::string line; std::getline(in, line);) {
      if (declared_module(line) == name) {
        found.push_back(file);
        break;
      }
    }
  }
  if (found.size() > 1) {
    *error = "more than one module map declares the module " + name;
    return {};
  }
  return found.empty() ? fs::path() : found[0];
}

// The public headers a module map exposes, as paths: the header lines and the umbrella header resolve in header_base, the umbrella
// directories in dir_base. A framework module nested in this one is its own framework and is skipped, and so is a module that requires
// x86 (the target is arm64). Textual, private and excluded headers are not public: an exclude removes a header an umbrella directory
// takes, unless the module names it. wanted, when set, is the one top-level module to take (a usr/include map can declare several); a
// framework's headers are in path order, a usr/include module's in the order its map names them.
std::vector<std::string> module_headers(const fs::path& map, const fs::path& header_base, const fs::path& dir_base,
                                        const std::string& wanted) {
  if (!is_file(map)) return {};
  static const std::regex framework_module(R"re(^framework\s+module\s)re");
  static const std::regex x86(R"re(^requires\s+x86)re");
  static const std::regex umbrella_header(R"re(^umbrella\s+header\s+"([^"]+)")re");
  static const std::regex header_line(R"re(^header\s+"([^"]+)")re");
  static const std::regex exclude_header(R"re(^exclude\s+header\s)re");
  static const std::regex umbrella_dir(R"re(^umbrella\s+"([^"]+)")re");
  static const std::regex quoted(R"re("([^"]+)")re");
  std::vector<std::string> headers;
  std::set<std::string> seen, named, excluded;
  auto add = [&](const std::string& file, bool is_named) {
    if (is_named) named.insert(file);
    if (seen.insert(file).second) headers.push_back(file);
  };
  std::ifstream in(map);
  int depth = 0;
  bool skipping_set = false;
  int skip_at = 0;
  for (std::string line; std::getline(in, line);) {
    std::string code = trim_space(line.substr(0, line.find("//")));
    int opens = (int)std::count(code.begin(), code.end(), '{');
    int closes = (int)std::count(code.begin(), code.end(), '}');
    bool skipping = skipping_set && depth >= skip_at;
    if (!skipping) {
      std::smatch m;
      std::string declared = declared_module(code);
      if (std::regex_search(code, framework_module) && depth >= 1) {
        skipping_set = true;
        skip_at = depth + 1;
      } else if (std::regex_search(code, x86)) {
        skipping_set = true;
        skip_at = depth;
      } else if (!wanted.empty() && depth == 0 && !declared.empty() && declared != wanted) {
        skipping_set = true;
        skip_at = depth + 1;
      } else if (std::regex_search(code, m, umbrella_header) || std::regex_search(code, m, header_line)) {
        add(normal(header_base / m[1].str()), true);
      } else if (std::regex_search(code, exclude_header)) {
        std::smatch q;
        if (std::regex_search(code, q, quoted)) excluded.insert(normal(header_base / q[1].str()));
      } else if (std::regex_search(code, m, umbrella_dir)) {
        std::vector<std::string> files;
        std::error_code ec;
        for (fs::recursive_directory_iterator it(dir_base / m[1].str(), ec), end; !ec && it != end; it.increment(ec)) {
          if (it->path().extension() == ".h" && is_file(it->path())) files.push_back(normal(it->path()));
        }
        std::sort(files.begin(), files.end());
        for (const std::string& file : files) add(file, false);
      }
    }
    depth += opens - closes;
    if (skipping_set && depth < skip_at) skipping_set = false;
  }
  std::vector<std::string> out;
  for (const std::string& file : headers) {
    if (!excluded.count(file) || named.count(file)) out.push_back(file);
  }
  if (wanted.empty()) std::sort(out.begin(), out.end());
  return out;
}

// The headers a framework is parsed from: its module map's list, else its umbrella header, else its Headers/ files; and the reason it has
// none. A usr/include module has its map's list and nothing else.
std::vector<std::string> headers_of(const Framework& f, std::string* reason) {
  if (f.usr) {
    std::vector<std::string> listed = module_headers(f.map, f.map.parent_path(), f.map.parent_path(), f.name);
    if (!listed.empty()) return listed;
    *reason = "no module map header";
    return {};
  }
  std::vector<std::string> listed = module_headers(f.root / "Modules" / "module.modulemap", f.root / "Headers", f.root, "");
  if (!listed.empty()) return listed;
  fs::path umbrella = f.root / "Headers" / (f.base + ".h");
  if (is_file(umbrella)) return {normal(umbrella)};
  std::vector<std::string> all;
  for (const fs::path& p : entries_of(f.root / "Headers")) {
    if (p.extension() == ".h" && is_file(p)) all.push_back(normal(p));
  }
  if (!all.empty()) return all;
  for (const fs::path& p : entries_of(f.root / "Modules")) {
    if (p.extension() == ".swiftmodule" && is_dir(p)) {
      *reason = "no Objective-C or C header; Swift interface only";
      return {};
    }
  }
  *reason = "no public header in Headers/ and no module map header";
  return {};
}

// The frameworks the sweep covers, sorted by name: System/Library/Frameworks with those nested in each, and the usr/include modules of
// IR_USR_MODULES (a comma list; the default is kUsrModules). Two frameworks of one name, or a module with no module map, are errors.
bool discover(const std::string& sdk, std::vector<Framework>* out, std::string* error) {
  frameworks_in(fs::path(sdk) / "System" / "Library" / "Frameworks", "", out);
  const char* env = std::getenv("IR_USR_MODULES");
  std::stringstream names(env != nullptr ? env : kUsrModules);
  for (std::string name; std::getline(names, name, ',');) {
    if (name.empty()) continue;
    Framework f;
    f.name = name;
    f.base = name;
    f.root = fs::path(sdk) / "usr" / "include";
    f.usr = true;
    out->push_back(f);  // its module map is found when it is the framework asked for (main), not for every listing
  }
  std::sort(out->begin(), out->end(), [](const Framework& a, const Framework& b) { return a.name < b.name; });
  for (size_t i = 1; i < out->size(); ++i) {
    if ((*out)[i].name == (*out)[i - 1].name) {
      *error = "two frameworks are named " + (*out)[i].name;
      return false;
    }
  }
  return true;
}

// The census row: a row of kind census, the framework's own and foreign declaration counts in the name and type cells (ir.lua reads
// them to classify the frameworks that have no shard).
void census_row(Context& ctx, const char* sdk, CXTranslationUnit tu) {
  Census census{&ctx, sdk, 0, 0};
  clang_visitChildren(clang_getTranslationUnitCursor(tu), census_visit, &census);
  std::string row = cell(ctx.framework) + "\tcensus\t-\t-\town=" + std::to_string(census.own) + "\t-\t-\t-\t-\t-\tforeign=" +
                    std::to_string(census.foreign);
  for (int i = 11; i < 18; ++i) row += "\t-";
  ctx.out += row + "\n";
}

int main(int argc, char** argv) {
  if (argc == 2 && std::strcmp(argv[1], "--version") == 0) {
    std::printf("%s\n", text(clang_getClangVersion()).c_str());
    return 0;
  }
  // the hash of one text, as the availability hash is computed: ir.lua hashes the availability it merges with this
  if (argc == 3 && std::strcmp(argv[1], "--digest") == 0) {
    std::printf("%s\n", digest16(argv[2]).c_str());
    return 0;
  }
  if (argc == 2 && std::strcmp(argv[1], "--target") == 0) {
    std::printf("%s\n", kTarget);
    return 0;
  }
  // the flags, in any order: --doc (the doc rows), --list (the frameworks), --timeout SECONDS
  int first = 1;
  bool doc = false, list = false;
  for (;;) {
    if (first < argc && std::strcmp(argv[first], "--doc") == 0) {
      doc = true;
      first += 1;
    } else if (first < argc && std::strcmp(argv[first], "--list") == 0) {
      list = true;
      first += 1;
    } else if (first + 1 < argc && std::strcmp(argv[first], "--timeout") == 0) {
      alarm((unsigned)std::atoi(argv[first + 1]));
      first += 2;
    } else {
      break;
    }
  }
  const char* sdk_env = std::getenv("IR_SDK");
  if (sdk_env == nullptr) {
    std::fprintf(stderr, "decls: IR_SDK must name the iPhoneOS SDK\n");
    return 2;
  }
  const std::string sdk = fs::absolute(sdk_env).string();
  std::vector<Framework> frameworks;
  std::string error;
  if (!discover(sdk, &frameworks, &error)) {
    std::fprintf(stderr, "decls: %s\n", error.c_str());
    return 2;
  }
  if (list) {
    for (const Framework& f : frameworks) std::printf("%s\t%s\n", f.name.c_str(), f.root.string().c_str());
    return 0;
  }
  if (argc - first != 1) {
    usage();
    return 2;
  }
  const std::string name = argv[first];
  const Framework* framework = nullptr;
  for (const Framework& f : frameworks) {
    if (f.name == name) framework = &f;
  }
  if (framework == nullptr) {
    std::fprintf(stderr, "decls: no framework named %s in the SDK\n", name.c_str());
    return 2;
  }
  std::string reason;
  Framework chosen = *framework;
  if (chosen.usr) {
    chosen.map = usr_module_map(chosen.root, chosen.name, &error);
    if (!error.empty() || chosen.map.empty()) {
      std::fprintf(stderr, "decls: %s\n", error.empty() ? ("no module map in usr/include declares the module " + name).c_str() : error.c_str());
      return 2;
    }
  }
  std::vector<std::string> headers = headers_of(chosen, &reason);
  Context ctx;
  ctx.doc = doc;
  ctx.framework = name;
  if (framework->usr) {
    std::set<std::string> dirs;
    for (const std::string& h : headers) dirs.insert(fs::path(h).parent_path().string() + "/");
    ctx.own.assign(dirs.begin(), dirs.end());
  } else {
    ctx.own.push_back(framework->root.string() + "/Headers/");
  }
  if (headers.empty()) {
    if (doc) {
      std::fprintf(stderr, "decls: %s: %s\n", name.c_str(), reason.c_str());
      return 1;
    }
    // a framework with no header is one row of kind unparsed, its reason in the name column, as a framework that does not parse is
    std::string row = name + "\tunparsed\t-\t-\t" + reason;
    for (int i = 5; i < 18; ++i) row += "\t-";
    std::printf("%s\n", row.c_str());
    return 0;
  }
  std::string imports;
  for (const std::string& h : headers) imports += "#import \"" + h + "\"\n";
  CXUnsavedFile unsaved = {"charon-module.m", imports.c_str(), (unsigned long)imports.size()};
  std::vector<const char*> args = {"-x", "objective-c", "-target", kTarget, "-isysroot", sdk.c_str()};
  if (const char* resource = std::getenv("IR_RESOURCE")) {
    args.push_back("-resource-dir");
    args.push_back(resource);
  }
  args.push_back("-Wno-everything");
  CXIndex index = clang_createIndex(0, 0);
  CXTranslationUnit tu = nullptr;
  CXErrorCode code = clang_parseTranslationUnit2(
      index, "charon-module.m", args.data(), (int)args.size(), &unsaved, 1,
      CXTranslationUnit_SkipFunctionBodies | CXTranslationUnit_DetailedPreprocessingRecord | CXTranslationUnit_IncludeAttributedTypes,
      &tu);
  if (code != CXError_Success || !tu) {
    std::fprintf(stderr, "decls: parse failed for %s (code %d)\n", name.c_str(), (int)code);
    return 1;
  }
  ctx.tu = tu;
  long errors = 0;
  std::string first_error;
  unsigned n = clang_getNumDiagnostics(tu);
  for (unsigned i = 0; i < n; ++i) {
    CXDiagnostic d = clang_getDiagnostic(tu, i);
    if (clang_getDiagnosticSeverity(d) >= CXDiagnostic_Error) {
      if (errors == 0) {
        // the first error, with the file and line it is in (the header that refused the parse)
        CXFile file = nullptr;
        unsigned line = 0, column = 0, offset = 0;
        clang_getSpellingLocation(clang_getDiagnosticLocation(d), &file, &line, &column, &offset);
        std::string where = file ? text(clang_getFileName(file)) + ":" + std::to_string(line) + ": " : "";
        first_error = cell(where + text(clang_getDiagnosticSpelling(d)));
      }
      ++errors;
    }
    clang_disposeDiagnostic(d);
  }
  if (errors == 0) {
    clang_visitChildren(clang_getTranslationUnitCursor(tu), collect_macro_uses, &ctx);
    Nest root{&ctx, "-", "", false, true};
    clang_visitChildren(clang_getTranslationUnitCursor(tu), visit, &root);
    resolve(ctx);
    if (!doc) census_row(ctx, sdk.c_str(), tu);
    std::fwrite(ctx.out.data(), 1, ctx.out.size(), stdout);
  } else if (doc) {
    std::fprintf(stderr, "decls: %s: %ld error diagnostics\n", name.c_str(), errors);
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);
    return 1;
  } else {
    // A module that does not parse is one row of kind unparsed, its reason in the name column; no declaration of it is written.
    // The SDK's absolute path is redacted: the snapshot must not depend on where the SDK is installed.
    for (size_t at = first_error.find(sdk); at != std::string::npos; at = first_error.find(sdk, at)) {
      first_error.replace(at, sdk.size(), "<sdk>");
    }
    std::fprintf(stderr, "decls: %s: %ld error diagnostics, first: %s\n", name.c_str(), errors, first_error.c_str());
    // the row has the 17 cells of every row: the reason is the name, the rest are "-"
    std::string row = name + "\tunparsed\t-\t-\t" + first_error;
    for (int i = 5; i < 18; ++i) row += "\t-";
    std::printf("%s\n", row.c_str());
  }
  clang_disposeTranslationUnit(tu);
  clang_disposeIndex(index);
  return 0;
}

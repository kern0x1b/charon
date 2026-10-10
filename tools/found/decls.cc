// The declarations of one framework, from clang's own AST through libclang: the source of the spec's Objective-C and C facts.
//
// usage: decls --version
//        decls [--doc] [--timeout SECONDS] <sdk-root> <framework> <framework-root> <target-triple> <clang-resource-dir> <header>...
// <framework> is the name the rows carry (a nested framework has its own name). <framework-root> is its .framework directory;
// its declarations are the ones written under <framework-root>/Headers. Each <header> is an absolute path of a public header
// of the module (the driver reads the module map and passes the header set); the headers become one unsaved buffer of #import
// lines, so nothing is written to disk. <clang-resource-dir> holds the compiler's own headers (stdarg.h, stddef.h).
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
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
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
std::string spelled(CXType t) {
  std::string s = text(clang_getTypeSpelling(unqualified(t)));
  for (const char* open : {"(unnamed", "(anonymous"}) {
    for (size_t at = s.find(open); at != std::string::npos; at = s.find(open, at + 1)) {
      size_t close = s.find(')', at);
      if (close == std::string::npos) break;
      s.replace(at, close - at + 1, std::string(open) + ")");
    }
  }
  return s;
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
  std::string headers;  // <framework-root>/Headers/, with the trailing slash
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
  if (path.compare(0, ctx.headers.size(), ctx.headers) != 0) return false;
  *file_out = path.substr(ctx.headers.size());
  *line_out = line;
  return true;
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
  r->brief = text(clang_Cursor_getBriefCommentText(c));
  r->comment = text(clang_Cursor_getRawCommentText(c));
  int n = clang_Cursor_getNumArguments(c);
  for (int i = 0; i < n; ++i) {
    if (i) r->params_names += " | ";
    r->params_names += text(clang_getCursorSpelling(clang_Cursor_getArgument(c, (unsigned)i)));
  }
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
        simple_row(ctx, c, "var", spelled(t), nullability(t), "-", "-", clang_isCursorDefinition(c));
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
        simple_row(ctx, c, "field", spelled(t), nullability(t), "-", nest->name, true);
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
               "usage: decls --version\n"
               "       decls [--doc] [--timeout SECONDS] <sdk-root> <framework> <framework-root> <target-triple> "
               "<clang-resource-dir> <header>...\n");
}

}  // namespace

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
  int first = 1;
  bool doc = false;
  if (argc > first && std::strcmp(argv[first], "--doc") == 0) {
    doc = true;
    ++first;
  }
  if (argc > first + 1 && std::strcmp(argv[first], "--timeout") == 0) {
    alarm((unsigned)std::atoi(argv[first + 1]));
    first += 2;
  }
  if (argc - first < 6) {
    usage();
    return 1;
  }
  const char* sdk = argv[first];
  Context ctx;
  ctx.doc = doc;
  ctx.framework = argv[first + 1];
  ctx.headers = std::string(argv[first + 2]) + "/Headers/";
  const char* triple = argv[first + 3];
  const char* resource = argv[first + 4];
  std::string imports;
  for (int i = first + 5; i < argc; ++i) imports += std::string("#import \"") + argv[i] + "\"\n";
  CXUnsavedFile unsaved = {"charon-module.m", imports.c_str(), (unsigned long)imports.size()};
  const char* args[] = {"-x", "objective-c", "-target", triple, "-isysroot", sdk, "-resource-dir", resource, "-Wno-everything"};
  CXIndex index = clang_createIndex(0, 0);
  CXTranslationUnit tu = nullptr;
  CXErrorCode code = clang_parseTranslationUnit2(
      index, "charon-module.m", args, sizeof args / sizeof args[0], &unsaved, 1,
      CXTranslationUnit_SkipFunctionBodies | CXTranslationUnit_DetailedPreprocessingRecord | CXTranslationUnit_IncludeAttributedTypes,
      &tu);
  if (code != CXError_Success || !tu) {
    std::fprintf(stderr, "decls: parse failed for %s (code %d)\n", ctx.framework.c_str(), (int)code);
    return 1;
  }
  ctx.tu = tu;
  long errors = 0;
  std::string first_error;
  unsigned n = clang_getNumDiagnostics(tu);
  for (unsigned i = 0; i < n; ++i) {
    CXDiagnostic d = clang_getDiagnostic(tu, i);
    if (clang_getDiagnosticSeverity(d) >= CXDiagnostic_Error) {
      if (errors == 0) first_error = cell(text(clang_getDiagnosticSpelling(d)));
      ++errors;
    }
    clang_disposeDiagnostic(d);
  }
  if (errors == 0) {
    clang_visitChildren(clang_getTranslationUnitCursor(tu), collect_macro_uses, &ctx);
    Nest root{&ctx, "-", "", false, true};
    clang_visitChildren(clang_getTranslationUnitCursor(tu), visit, &root);
    resolve(ctx);
    if (!doc) census_row(ctx, sdk, tu);
    std::fwrite(ctx.out.data(), 1, ctx.out.size(), stdout);
  } else if (doc) {
    std::fprintf(stderr, "decls: %s: %ld error diagnostics\n", ctx.framework.c_str(), errors);
    clang_disposeTranslationUnit(tu);
    clang_disposeIndex(index);
    return 1;
  } else {
    // A module that does not parse is one row of kind unparsed, its reason in the name column; no declaration of it is written.
    // The SDK's absolute path is redacted: the snapshot must not depend on where the SDK is installed.
    for (size_t at = first_error.find(sdk); at != std::string::npos; at = first_error.find(sdk, at)) {
      first_error.replace(at, std::strlen(sdk), "<sdk>");
    }
    std::fprintf(stderr, "decls: %s: %ld error diagnostics, first: %s\n", ctx.framework.c_str(), errors, first_error.c_str());
    // the row has the 17 cells of every row: the reason is the name, the rest are "-"
    std::string row = cell(ctx.framework) + "\tunparsed\t-\t-\t" + first_error;
    for (int i = 5; i < 18; ++i) row += "\t-";
    std::printf("%s\n", row.c_str());
  }
  clang_disposeTranslationUnit(tu);
  clang_disposeIndex(index);
  return 0;
}

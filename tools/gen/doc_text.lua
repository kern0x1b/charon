-- The doc-time text of a framework's declarations: the header comments and the declaration text, which the doc pages show and the
-- snapshot does not hold (ruling 2: the comments are re-derived from clang at doc time; ruling D8: so is the declaration text).
-- The source is the extractor's doc mode, `decls --doc <F>` (tools/found/decls.cc): one row per declaration with its USR, its doc
-- comment, its declaration text and the names of its parameters, written to a pipe and never to a file. The extractor's header list
-- for the framework is its own (the module-map resolution), so the call takes the framework alone.
--
-- Until that mode is on the branch, available() is false and the pages keep the marked text ("not derived"), so no comment is
-- faked. The contract for when it is: available(tree, fw) is true when the mode can run for the framework, and rows(tree, fw) then
-- returns a map from USR to {comment, decl, params}; a declaration with no comment has comment "". Nothing else changes.

-- Whether the extractor's doc mode can run for a framework. False until decls --doc <F> is on the branch.
function available(tree, fw)
    return false
end

-- The doc-time rows of a framework, keyed by USR, when available(tree, fw) is true (not called otherwise).
function rows(tree, fw)
    error("decls --doc is not on the branch yet: doc_text.available is false for " .. fw)
end

-- The lines of a page's header-comment section for the framework: the comments when available, else the marked text the caller gives.
function comment_lines(tree, fw, marked)
    if available(tree, fw) then
        return {"(comments: see the doc-time rows)"}
    end
    return {marked}
end

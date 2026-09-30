#!/usr/bin/env python3
"""
merge-readiness.py -- what is ready to merge, and what is standing in the way of each band.

The fleet's bottleneck is the merge rate: rows are built and sitting in band worktrees. This says,
for every band, whether its series would apply to current origin/main and whether anything is known
to be wrong with it, so the order is decided by evidence rather than by which band asked last.

For each band it reports:

  - the exported patch directories, how many patches each holds, and the base the series starts
    from (the merge-base with origin/main);
  - whether each directory applies to current origin/main with `git am -3`, tried for real in a
    scratch worktree under `charon/.agent-work/worktrees/merge-probe/` -- never /tmp, and a fresh
    one per trial so that nothing has to be reset destructively to try the next band;
  - the files more than one band's unmerged series touch, which is where two bands collide before
    either is merged;
  - the latest gate log for the band, read the way the backports-gate skill says to read it: the
    `imports:` line, the `error:` lines, and `EXIT=` when the log carries one (`EXIT=0` alone is
    not green, and the skill's `echo EXIT=$?` goes to the terminal, so a log without it is reported
    as not recording one rather than as green);
  - a review verdict from coordination/reviews/ naming that band or one of its series, with the
    file it came from;
  - the ledger rows the band holds that main does not -- the same count fleet-progress.py attributes
    to it, read from that tool's FLEET.json when it is there.

Sorted by rows ready first -- a band whose gate is green and whose review says APPROVE -- and by
rows descending within each group.

Usage:
  python3 merge-readiness.py --out <MERGE.md> [--worktrees <workspace root>] [--charon <checkout>]
                             [--skip-apply] [--jobs 1]
"""
import argparse
import collections
import importlib.util
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.realpath(__file__))


def _neighbour(name):
    """fleet-progress.py, loaded from beside this file: the band discovery and the row attribution
    are its, and a second copy of them here would be one more thing to keep in step."""
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"),
                                              os.path.join(HERE, name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


fleet = _neighbour("fleet-progress")

VERDICTS = ("APPROVE", "APPROVED", "CHANGES", "BLOCK", "BLOCKED", "REJECT", "REJECTED")
IMPORTS_RE = re.compile(r"^imports:.*resolves against (\d+) exports", re.M)
RED_RE = re.compile(r"^\x1b?\[?0?m?\s*(error|fatal error):", re.M)


def note(message):
    print(message, file=sys.stderr, flush=True)


def git(worktree, *args, **kwargs):
    return subprocess.run(["git", "-C", worktree] + list(args), capture_output=True, text=True,
                          timeout=kwargs.get("timeout", 300))


# ---------------------------------------------------------------------------
# A band's own state
# ---------------------------------------------------------------------------

def patch_dirs(worktree):
    """The exported patch directories, each with its patch files in series order."""
    root = os.path.join(worktree, ".agent-work", "patches")
    found = []
    if not os.path.isdir(root):
        return found
    for name in sorted(os.listdir(root)):
        directory = os.path.join(root, name)
        if not os.path.isdir(directory):
            continue
        patches = sorted(os.path.join(directory, f) for f in os.listdir(directory)
                         if f.endswith(".patch"))
        if patches:
            found.append({"name": name, "directory": directory, "patches": patches})
    return found


def series_state(worktree, origin):
    """The unmerged series: its commits, its base, and the files it touches."""
    base = git(worktree, "merge-base", "HEAD", origin).stdout.strip()
    if not base:
        base = origin
    commits = git(worktree, "log", "--oneline", "%s..HEAD" % origin).stdout.splitlines()
    files = git(worktree, "diff", "--name-only", "%s..HEAD" % base).stdout.splitlines()
    subject = git(worktree, "log", "-1", "--format=%s").stdout.strip()
    return {"base": base, "commits": commits, "files": files, "subject": subject}


def gate_verdict(worktree):
    """The latest gate log for the band, read the way the backports-gate skill reads one."""
    runs = os.path.join(worktree, ".agent-work", "runs")
    logs = []
    for base, _, files in os.walk(runs) if os.path.isdir(runs) else []:
        for name in files:
            if name.endswith(".log"):
                path = os.path.join(base, name)
                logs.append((os.path.getmtime(path), path))
    if not logs:
        return {"log": None, "newest-log": None, "imports": None, "exports": None, "weak": None,
                "exit": None, "red": [], "red-count": 0, "green": False,
                "verdict": "no log at all in this tree"}
    # The newest *gate* log, not the newest log: a band keeps light-test and build logs beside its
    # gate ones, and a log with neither an imports line nor an error line is not a gate verdict.
    newest_log = max(logs)[1]
    gate = None
    for stamp, path in sorted(logs, reverse=True):
        with open(path, encoding="utf-8", errors="replace") as f:
            body = re.sub(r"\x1b\[[0-9;]*m", "", f.read())
        if "imports:" in body or re.search(r"^\s*(error|fatal error):", body, re.M):
            gate = (stamp, path, body)
            break
    if gate is None:
        return {"log": newest_log, "newest-log": newest_log, "imports": None, "exports": None,
                "weak": None, "exit": None, "red": [], "red-count": 0, "green": False,
                "verdict": "no gate verdict in this tree: no log carries an imports line or an error "
                           "line (newest log: %s)" % fleet.short(newest_log)}
    stamp, path, plain = gate
    imports = IMPORTS_RE.search(plain)
    red = [line.strip() for line in plain.splitlines()
           if re.match(r"^\s*(error|fatal error):", line)]
    weak = re.search(r"imports:.*?;\s*(\d+) weak imports it does not export", plain)
    exit_line = re.search(r"^EXIT=(\d+)", plain, re.M)
    green = bool(imports) and not red
    if not imports and not red:
        verdict = "no imports line and no error line: the log is not a gate verdict"
    elif green:
        verdict = "green: no error line, and the imports line resolves"
    else:
        verdict = "red: %d error line(s)" % len(red)
    return {"log": path, "mtime": stamp, "newest-log": newest_log,
            "imports": imports.group(0).strip() if imports else None,
            "exports": int(imports.group(1)) if imports else None,
            "weak": int(weak.group(1)) if weak else None,
            "exit": int(exit_line.group(1)) if exit_line else None,
            "red": red[:5], "red-count": len(red), "green": green, "verdict": verdict}


def review_verdicts(reviews, band, series_names):
    """Every review file naming this band or one of its series, with the verdict it carries."""
    found = []
    for name in sorted(os.listdir(reviews)) if os.path.isdir(reviews) else []:
        if not name.endswith(".md"):
            continue
        path = os.path.join(reviews, name)
        with open(path, encoding="utf-8", errors="replace") as f:
            text = f.read()
        stem = os.path.splitext(name)[0]
        mentions = band in stem or band in text
        if not mentions:
            mentions = any(series in text for series in series_names)
        if not mentions:
            continue
        verdict = None
        for token in VERDICTS:
            if re.search(r"\*\*%s" % token, text) or re.search(r"^Verdict: *%s" % token, text, re.M):
                verdict = token
                break
        # The file is named after the series it reviews (2026-09-27-<band>-<series>[-hash].md), so
        # the verdict belongs to that directory and not to the whole band.
        series = None
        tail = re.sub(r"^\d{4}-\d{2}-\d{2}-", "", stem)
        tail = re.sub(r"^%s-" % re.escape(band.split("/")[-1]), "", tail)
        tail = re.sub(r"-[0-9a-f]{6,8}$", "", tail)
        # The review's tail is the series with the band's own prefix already removed, so it is a
        # suffix of the directory name (`movement-2` of `uikit-movement-2`), not a prefix of it.
        # Either may carry the other's prefix -- the review of api-uikit-a's `uikit-movement-2`
        # is filed as `2026-09-27-api-uikit-movement-2.md` -- so a suffix match either way, longest
        # name first.
        for candidate in sorted(series_names, key=len, reverse=True):
            if candidate and tail.endswith(candidate):
                series = candidate
                break
        if series is None:
            for candidate in sorted(series_names, key=len, reverse=True):
                if candidate and candidate.endswith(tail):
                    series = candidate
                    break
        found.append({"file": name, "verdict": verdict, "series": series})
    return found


# ---------------------------------------------------------------------------
# The apply trial
# ---------------------------------------------------------------------------

def try_apply(charon, probe_root, tag, series, origin):
    """`git am -3` a series onto current origin/main, in a scratch worktree of the charon checkout
    under .agent-work/worktrees/merge-probe/. One worktree per trial, so nothing is ever reset to
    try the next band and no other session's work is touched; the worktree is removed afterwards."""
    path = os.path.join(probe_root, tag)
    added = git(charon, "worktree", "add", "--detach", path, origin, timeout=600)
    if added.returncode != 0:
        return {"applies": None, "why": "the scratch worktree could not be created: %s"
                % added.stderr.strip()[-200:]}
    try:
        out = git(path, "am", "-3", *series["patches"], timeout=900)
        if out.returncode == 0:
            return {"applies": True, "why": "", "commits": git(path, "rev-list", "--count",
                                                                "%s..HEAD" % origin).stdout.strip()}
        conflicted = git(path, "diff", "--name-only", "--diff-filter=U").stdout.split()
        git(path, "am", "--abort")
        return {"applies": False, "why": "git am -3 reported a conflict",
                "files": conflicted[:8],
                "detail": out.stdout.strip().splitlines()[-1][:200] if out.stdout.strip() else
                          out.stderr.strip()[-200:]}
    finally:
        git(charon, "worktree", "remove", "--force", path, timeout=600)


# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    ap.add_argument("--out", required=True)
    ap.add_argument("--worktrees", default=os.path.expanduser("~/Git/projects/ios"))
    ap.add_argument("--charon", default=None)
    ap.add_argument("--origin", default="origin/main")
    ap.add_argument("--skip-apply", action="store_true")
    ap.add_argument("--jobs", type=int, default=1)
    ap.add_argument("--fleet-json", default=None,
                    help="FLEET.json from fleet-progress.py, for the per-band row counts; defaults "
                         "to one beside --out. Without it the row column is reported as unknown, "
                         "not as zero")
    args = ap.parse_args()
    started = time.time()

    charon = args.charon or os.path.join(args.worktrees, "charon")
    probe_root = os.path.join(charon, ".agent-work", "worktrees", "merge-probe")
    reviews = os.path.join(args.worktrees, "coordination", "reviews")
    fleet_json = args.fleet_json or os.path.join(os.path.dirname(args.out), "FLEET.json")
    rows_by_band = {}
    if os.path.exists(fleet_json):
        with open(fleet_json, encoding="utf-8") as f:
            payload = json.load(f)
        rows_by_band = {k: v.get("rows", 0) for k, v in payload.get("by-band", {}).items()}
        note("rows from %s" % fleet.short(fleet_json))
    else:
        note("no %s, so the row column is unknown rather than zero; run fleet-progress.py first"
             % fleet.short(fleet_json))

    bands = fleet.discover_bands(args.worktrees)
    note("%d bands" % len(bands))
    os.makedirs(probe_root, exist_ok=True)
    reports, file_owners = [], collections.defaultdict(set)
    for band in bands:
        name, worktree = band["name"], band["worktree"]
        series = series_state(worktree, args.origin)
        directories = patch_dirs(worktree)
        entry = {"band": name, "worktree": worktree, "kind": band["kind"],
                 "base": series["base"], "commits": series["commits"],
                 "files": series["files"],
                 "rows": rows_by_band.get(name) if name in rows_by_band else None,
                 "patches": sum(len(d["patches"]) for d in directories),
                 "dirs": [], "gate": gate_verdict(worktree),
                 "reviews": review_verdicts(reviews, name, [d["name"] for d in directories])}
        for directory in directories:
            record = {"name": directory["name"], "count": len(directory["patches"])}
            if args.skip_apply:
                record["applies"] = None
                record["why"] = "not tried (--skip-apply)"
            else:
                record.update(try_apply(charon, probe_root,
                                        "%s-%s" % (name.replace("/", "_"), directory["name"]),
                                        directory, args.origin))
            entry["dirs"].append(record)
        for touched in series["files"]:
            file_owners[touched].add(name)
        reports.append(entry)
        note("  %-26s %2d dir(s) %3d patch(es) %2d commit(s) %6s rows  gate: %s"
             % (name, len(directories), entry["patches"], len(series["commits"]),
                entry["rows"] if entry["rows"] is not None else "?", entry["gate"]["verdict"][:40]))

    shared = {path: sorted(owners) for path, owners in file_owners.items() if len(owners) > 1}
    for entry in reports:
        verdicts = {r["verdict"] for r in entry["reviews"] if r["verdict"]}
        # A verdict is attributed to a directory when the review names it, and to the band otherwise;
        # a directory with an APPROVE and another with CHANGES is a band that is partly ready, and
        # saying so is the difference between "not ready" and "merge these two now".
        for review in entry["reviews"]:
            review["applies-to"] = review["series"] or "the whole band"
        entry["series-verdicts"] = sorted({(r["applies-to"], r["verdict"] or "no verdict")
                                            for r in entry["reviews"]})
        entry["approved-dirs"] = sorted({r["applies-to"] for r in entry["reviews"]
                                         if r["verdict"] in ("APPROVE", "APPROVED")})
        entry["approved"] = bool(verdicts) and verdicts <= {"APPROVE", "APPROVED"}
        entry["changes"] = bool(verdicts & {"CHANGES", "REJECT", "REJECTED"})
        entry["blocked"] = bool(verdicts & {"BLOCK", "BLOCKED"})
        applicable = [d["applies"] for d in entry["dirs"]]
        entry["applies-clean"] = all(a is True for a in applicable) and bool(applicable)
        entry["applies-unknown"] = any(a is None for a in applicable)
        entry["collides"] = sorted({p for p in entry["files"] if p in shared})
        entry["ready"] = (entry["gate"]["green"] and entry["approved"] and entry["applies-clean"]
                          and not entry["blocked"])
        entry["reasons"] = []
        if not entry["gate"]["green"]:
            entry["reasons"].append("gate: " + entry["gate"]["verdict"])
        if entry["changes"]:
            entry["reasons"].append("review asks for changes")
        if entry["blocked"]:
            entry["reasons"].append("review blocks it")
        if not entry["approved"] and not entry["changes"] and not entry["blocked"]:
            entry["reasons"].append("no review verdict naming it")
        if not entry["dirs"]:
            entry["reasons"].append("no exported patches")
        elif not entry["applies-clean"]:
            bad = [d["name"] for d in entry["dirs"] if d["applies"] is not True]
            entry["reasons"].append("does not apply cleanly: " + ", ".join(bad[:3]))
        if entry["collides"]:
            entry["reasons"].append("touches %d file(s) another band also touches" % len(entry["collides"]))

    # A band whose row count is unknown sorts by its name among the unknown, not as zero rows.
    reports.sort(key=lambda e: (not e["ready"], -(e["rows"] or 0), e["band"]))
    ready = [e for e in reports if e["ready"]]
    applicable = sum(1 for e in reports for d in e["dirs"] if d["applies"] is True)
    conflicted = sum(1 for e in reports for d in e["dirs"] if d["applies"] is False)

    with open(args.out, "w", encoding="utf-8") as f:
        f.write("# Merge readiness -- the fleet's bands, ready first\n\n")
        f.write("Generated %s by `charon/tools/corpus/merge-readiness.py` in %.1f seconds. A band is "
                "**ready** when its latest gate log is green (no `error:` line and an `imports:` line "
                "that resolves, read as the `backports-gate` skill reads one), a review in "
                "`coordination/reviews/` names it and says **APPROVE**, and its exported patches "
                "apply to current `%s` with `git am -3`, tried for real in a scratch worktree under "
                "`charon/.agent-work/worktrees/merge-probe/`.\n\n"
                % (time.strftime("%Y-%m-%d %H:%M:%S %Z"), time.time() - started, args.origin))
        f.write("| | bands | patch dirs | applies | conflicts |\n| --- | --- | --- | --- | --- |\n")
        f.write("| ready (gate green + APPROVE + applies) | %d | %d | %d | – |\n"
                % (len(ready), sum(len(e["dirs"]) for e in ready),
                   sum(1 for e in ready for d in e["dirs"] if d["applies"] is True)))
        f.write("| all bands | %d | %d | %d | %d |\n\n"
                % (len(reports), sum(len(e["dirs"]) for e in reports), applicable, conflicted))
        f.write("Ready first, then by the ledger rows the band holds that main does not.\n\n")
        f.write("| band | ready | rows | gate | review | patches | applies | collides | why not |\n")
        f.write("| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n")
        for entry in reports:
            gate = entry["gate"]
            gate_text = "green" if gate["green"] else gate["verdict"].split(":")[0]
            review = ", ".join("%s: %s" % (r["applies-to"], r["verdict"] or "no verdict")
                               for r in entry["reviews"]) or "none"
            applies = ("all %d" % len(entry["dirs"])) if entry["applies-clean"] else ", ".join(
                "%s: %s" % (d["name"], "clean" if d["applies"] else
                            ("untried" if d["applies"] is None else "CONFLICT")) for d in entry["dirs"])
            f.write("| %s | %s | %s | %s | %s | %d | %s | %d | %s |\n"
                    % (entry["band"], "**yes**" if entry["ready"] else "no",
                       entry["rows"] if entry["rows"] is not None else "?", gate_text,
                       review, entry["patches"], applies or "-", len(entry["collides"]),
                       "; ".join(entry["reasons"])[:110] or "-"))
        f.write("\n## Per band\n")
        for entry in reports:
            f.write("\n### %s\n\n" % entry["band"])
            f.write("- rows main does not have: **%s**\n"
                    % (entry["rows"] if entry["rows"] is not None else "unknown (no FLEET.json)"))
            f.write("- base: `%s`; unmerged commits: %d; HEAD: %s\n"
                    % (fleet.short(entry["base"]), len(entry["commits"]),
                       entry["commits"][0] if entry["commits"] else "on origin/main"))
            f.write("- gate: %s\n" % entry["gate"]["verdict"])
            if entry["gate"]["log"]:
                f.write("  - log: `%s`\n" % fleet.short(entry["gate"]["log"]))
                if entry["gate"]["imports"]:
                    f.write("  - %s%s\n" % (entry["gate"]["imports"],
                                            ("; %d weak imports it does not export" % entry["gate"]["weak"])
                                            if entry["gate"]["weak"] else ""))
                f.write("  - EXIT: %s\n" % ("recorded as %d" % entry["gate"]["exit"]
                                            if entry["gate"]["exit"] is not None
                                            else "not in the log (the skill's `echo EXIT=$?` goes to "
                                                 "the terminal, and EXIT=0 alone is not green)"))
                for line in entry["gate"]["red"]:
                    f.write("  - red: %s\n" % line[:160])
            if entry["dirs"]:
                f.write("- exported patch directories (%d patches):\n" % entry["patches"])
                for directory in entry["dirs"]:
                    f.write("  - `%s`: %d patch(es) -- %s%s\n"
                            % (directory["name"], directory["count"],
                               "applies cleanly" if directory["applies"] is True else
                               ("not tried" if directory["applies"] is None else "**CONFLICT**"),
                               (" (%s)" % directory["why"]) if directory.get("why") else ""))
                    for name in directory.get("files", [])[:6]:
                        f.write("    - conflicting: `%s`\n" % name)
            else:
                f.write("- no exported patch directory: nothing handed over yet\n")
            if entry["reviews"]:
                for review in entry["reviews"]:
                    f.write("- review: `%s` -- **%s** (about: %s)\n"
                            % (review["file"], review["verdict"] or "no verdict token in the file",
                               review["applies-to"]))
            else:
                f.write("- review: none in coordination/reviews/ names this band or its series\n")
            if entry["collides"]:
                f.write("- files another band's unmerged series also touches (%d): %s\n"
                        % (len(entry["collides"]), ", ".join("`%s`" % p
                                                             for p in entry["collides"][:6])))
        if ready:
            f.write("\n## Ready now\n\n")
            for entry in ready:
                f.write("- **%s** -- %d rows, gate `%s`, %d patch dir(s) apply, approved: %s\n"
                        % (entry["band"], entry["rows"],
                           fleet.short(entry["gate"]["log"]), len(entry["dirs"]),
                           ", ".join(entry["approved-dirs"]) or "the whole band"))
        f.write("\n## Where two bands collide\n\n")
        if shared:
            f.write("%d files are touched by more than one band's unmerged series. Merging one band "
                    "moves the other, so they are ordered together:\n\n" % len(shared))
            for path in sorted(shared, key=lambda p: (-len(shared[p]), p)):
                f.write("- `%s` -- %s\n" % (path, ", ".join(shared[path])))
        else:
            f.write("No file is touched by more than one band's unmerged series.\n")
        f.write("\n## What this does not measure\n\n")
        f.write("- A series is tried with `git am -3` against current `%s` and nothing else: it does "
                "not build, so \"applies\" is about the patch applying, never about the result being "
                "correct. The gate log is the build verdict and it is the band's own latest run, "
                "not a run of this series on a fresh tree.\n" % args.origin)
        f.write("- `rows` is what fleet-progress.py attributes to the band: the ledger rows it holds "
                "that main does not, from its registry and its built artifacts. It is a count of rows, "
                "not a quality claim about the work.\n")
        f.write("- A band with no gate log is reported as such, not as unblocked; a band whose "
                "reviews are absent is reported as having no verdict, not as approved.\n")
    note("wrote %s: %d bands, %d ready, %d patch dirs apply, %d conflict, in %.1f seconds"
         % (args.out, len(reports), len(ready), applicable, conflicted, time.time() - started))


if __name__ == "__main__":
    main()

"""Tools for update-split-long-requirements (design D3, D4).

Each *_DIR holds <capability>/spec.md. BEFORE_DIR is the main specs before the
split: export them with `git show 2d64cb0:openspec/specs/<cap>/spec.md`.
TARGET_DIR is work/target in this change.

usage:
  python3 -I specsplit.py delta  BEFORE_DIR TARGET_DIR OUT_DIR   # write delta specs
  python3 -I specsplit.py check  BEFORE_DIR TARGET_DIR            # preservation check
  python3 -I specsplit.py verify-archive BEFORE_DIR TARGET_DIR ARCHIVED_DIR
                                         # archive result == target + kept scenarios
  python3 -I specsplit.py same   A_DIR B_DIR                      # same requirement set (order ignored)
"""
import os
import re
import sys

CAPS = "accounts diagnostics distribution gh-cli github-api notifications polling settings ui".split()
NORM = re.compile(r"\b(MUST|SHALL|SHOULD)\b")


def parse(path):
    """Return (head, [(name, raw)], tail). raw = block text without trailing blank lines."""
    lines = open(path, encoding="utf-8").read().split("\n")
    head, blocks, cur, fence, tail = [], [], None, False, []
    in_reqs = False
    for line in lines:
        if line.strip().startswith("```"):
            fence = not fence
        if not fence and line.startswith("## ") and cur is not None:
            blocks.append(cur)
            cur = None
            in_reqs = False
        if not fence and line.startswith("### Requirement: "):
            if cur is not None:
                blocks.append(cur)
            cur = [line[len("### Requirement: "):].strip(), [line]]
            in_reqs = True
            continue
        if cur is not None:
            cur[1].append(line)
        elif not in_reqs and not blocks:
            head.append(line)
        else:
            tail.append(line)
    if cur is not None:
        blocks.append(cur)
    out = []
    for name, raw in blocks:
        while raw and raw[-1].strip() == "":
            raw.pop()
        out.append((name, "\n".join(raw)))
    return head, out, tail


def body_and_scenarios(raw):
    lines = raw.split("\n")[1:]
    body, scen, cur, fence = [], [], None, False
    for line in lines:
        if line.strip().startswith("```"):
            fence = not fence
        if not fence and line.startswith("#### "):
            if cur:
                scen.append(cur)
            cur = [line]
            continue
        if cur is not None:
            cur.append(line)
        else:
            body.append(line)
    if cur:
        scen.append(cur)
    scen = ["\n".join(s).strip() for s in scen]
    return [l.strip() for l in body if l.strip()], scen


def sentences(lines):
    out = []
    for l in lines:
        for s in re.split(r"(?<=。)", l):
            s = s.strip()
            if s:
                out.append(s)
    return out


def load(d, cap):
    return parse(os.path.join(d, cap, "spec.md"))


def keep_scenarios(target_raw, before_raw):
    """MODIFIED may not drop scenarios: append the original ones the target moved away."""
    _, tscen = body_and_scenarios(target_raw)
    _, bscen = body_and_scenarios(before_raw)
    theads = {s.split("\n")[0] for s in tscen}
    extra = [s for s in bscen if s.split("\n")[0] not in theads]
    if not extra:
        return target_raw
    return target_raw + "\n\n" + "\n\n".join(extra)


def cmd_delta(before, target, outdir):
    for cap in CAPS:
        _, b, _ = load(before, cap)
        _, t, _ = load(target, cap)
        bmap = dict(b)
        tnames = [n for n, _ in t]
        missing = [n for n in bmap if n not in tnames]
        if missing:
            sys.exit(f"{cap}: removed requirements {missing}")
        if len(set(tnames)) != len(tnames):
            sys.exit(f"{cap}: duplicate names")
        mod = [(n, keep_scenarios(r, bmap[n])) for n, r in t if n in bmap and bmap[n] != r]
        add = [(n, r) for n, r in t if n not in bmap]
        if not mod and not add:
            continue
        parts = []
        if add:
            parts.append("## ADDED Requirements\n\n" + "\n\n".join(r for _, r in add))
        if mod:
            parts.append("## MODIFIED Requirements\n\n" + "\n\n".join(r for _, r in mod))
        os.makedirs(os.path.join(outdir, cap), exist_ok=True)
        with open(os.path.join(outdir, cap, "spec.md"), "w", encoding="utf-8") as f:
            f.write("\n\n".join(parts) + "\n")
        print(f"{cap}: modified {len(mod)}, added {len(add)}")


def cmd_check(before, target):
    problems = 0
    for cap in CAPS:
        _, b, _ = load(before, cap)
        _, t, _ = load(target, cap)
        tbodies = "\n".join("\n".join(body_and_scenarios(r)[0]) for _, r in t)
        tscen = [s for _, r in t for s in body_and_scenarios(r)[1]]
        tall = "\n".join(r for _, r in t)
        bmap = dict(b)
        for name, raw in b:
            body, scen = body_and_scenarios(raw)
            for s in sentences(body):
                if NORM.search(s):
                    if s not in tbodies:
                        problems += 1
                        print(f"[NORM MISSING] {cap}「{name}」: {s}")
                elif s not in tall:
                    print(f"[INFO moved/changed] {cap}「{name}」: {s}")
            for sc in scen:
                if sc not in tscen:
                    head = sc.split("\n")[0]
                    if any(x.split("\n")[0] == head for x in tscen):
                        print(f"[INFO scenario edited] {cap}「{name}」: {head}")
                    else:
                        problems += 1
                        print(f"[SCENARIO MISSING] {cap}「{name}」: {head}")
        for name, raw in t:
            body, scen = body_and_scenarios(raw)
            text = "\n".join(body)
            if len(text) > 500:
                problems += 1
                print(f"[TOO LONG] {cap}「{name}」: {len(text)}")
            elif len(text) > 450:
                print(f"[INFO >450] {cap}「{name}」: {len(text)}")
            if not NORM.search(text):
                problems += 1
                print(f"[NO SHALL/MUST] {cap}「{name}」")
            if not scen:
                problems += 1
                print(f"[NO SCENARIO] {cap}「{name}」")
            if name in bmap:
                continue
            for s in sentences(body):
                if s not in "\n".join(bmap.values()):
                    print(f"[INFO new text] {cap}「{name}」: {s}")
            for sc in scen:
                if sc not in "\n".join(bmap.values()):
                    print(f"[INFO new scenario] {cap}「{name}」: {sc.splitlines()[0]}")
        # sentences added to existing requirements
        for name, raw in t:
            if name not in bmap:
                continue
            body, scen = body_and_scenarios(raw)
            for s in sentences(body):
                if s not in bmap[name]:
                    print(f"[INFO new text] {cap}「{name}」: {s}")
            for sc in scen:
                if sc not in "\n".join(bmap.values()):
                    print(f"[INFO new scenario] {cap}「{name}」: {sc.splitlines()[0]}")
    print(f"problems: {problems}")
    return problems


def cmd_verify_archive(before, target, archived):
    """archived == target, except MODIFIED requirements keep the scenarios moved away."""
    bad = 0
    for cap in CAPS:
        _, a, _ = load(archived, cap)
        _, t, _ = load(target, cap)
        _, b, _ = load(before, cap)
        tm, bm = dict(t), dict(b)
        if sorted(n for n, _ in a) != sorted(tm):
            bad += 1
            print(f"{cap}: requirement names differ")
            continue
        for name, raw in a:
            exp = keep_scenarios(tm[name], bm[name]) if name in bm and bm[name] != tm[name] else tm[name]
            if raw.strip() != exp.strip():
                bad += 1
                print(f"{cap}: unexpected「{name}」")
    print(f"unexpected: {bad}")
    return bad


def cmd_same(a, bdir):
    bad = 0
    for cap in CAPS:
        ha, xa, ta = load(a, cap)
        hb, xb, tb = load(bdir, cap)
        if sorted(xa) != sorted(xb):
            bad += 1
            na, nb = dict(xa), dict(xb)
            for n in set(na) | set(nb):
                if na.get(n) != nb.get(n):
                    print(f"{cap}: differs「{n}」")
        if "\n".join(ha).strip() != "\n".join(hb).strip() or "\n".join(ta).strip() != "\n".join(tb).strip():
            bad += 1
            print(f"{cap}: head/tail differs")
    print(f"differences: {bad}")


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "delta":
        cmd_delta(*sys.argv[2:5])
    elif cmd == "check":
        sys.exit(1 if cmd_check(*sys.argv[2:4]) else 0)
    elif cmd == "verify-archive":
        sys.exit(1 if cmd_verify_archive(*sys.argv[2:5]) else 0)
    elif cmd == "same":
        cmd_same(*sys.argv[2:4])

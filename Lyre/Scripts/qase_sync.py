#!/usr/bin/env python3
"""
qase_sync.py: keeps Lyre's test cases and test results in Qase (https://qase.io).

QA/test-cases.json in the repo is the source of truth for the hand-checked cases;
Qase is where they are run and reported. Automated tests need no list: every test
in an Xcode result bundle becomes (or updates) a case under "Automated" in Qase.

Setup, once:
    1. In Qase, create a project with the code LYRE (or change "project" in
       QA/test-cases.json).
    2. In Qase: your avatar > API tokens > Create new token.
    3. export QASE_API_TOKEN=<the token>          (or put it in your shell profile)

Commands:
    python3 Scripts/qase_sync.py push-cases
        Creates or updates the suites and cases in QA/test-cases.json, then the
        test plans (Smoke, Release Regression, …) made from their tags.

    python3 Scripts/qase_sync.py push-results <path/to/Result.xcresult> [--title "…"] [--include-linked]
        Creates a test run in Qase from an Xcode result bundle and records every
        test's result. --include-linked also records a result for each hand-checked
        case whose `automated_by` tests all ran: passed if they all passed, failed if
        any failed. Use it only once you trust those links.

    python3 Scripts/qase_sync.py check
        Checks the token and project, and lists the field values Qase accepts.

The Qase ids of everything created are kept in QA/qase-map.json, so running a
command again updates rather than duplicates. Commit that file.

Only the Python standard library is used.
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CASES_FILE = ROOT / "QA" / "test-cases.json"
MAP_FILE = ROOT / "QA" / "qase-map.json"
API = "https://api.qase.io/v1"
AUTOMATED_ROOT = "Automated"


# MARK: - API

class Qase:
    def __init__(self, token: str, project: str):
        self.token = token
        self.project = project

    def request(self, method: str, path: str, body=None, query: str = ""):
        url = f"{API}/{path.format(code=self.project)}{query}"
        data = json.dumps(body).encode() if body is not None else None
        for attempt in range(5):
            request = urllib.request.Request(url, data=data, method=method, headers={
                "Token": self.token, "Content-Type": "application/json", "Accept": "application/json",
            })
            try:
                with urllib.request.urlopen(request, timeout=60) as response:
                    payload = json.loads(response.read() or b"{}")
                    return payload.get("result", payload)
            except urllib.error.HTTPError as error:
                if error.code == 429:
                    wait = int(error.headers.get("Retry-After", "5"))
                    print(f"  rate limited; waiting {wait}s", file=sys.stderr)
                    time.sleep(wait)
                    continue
                detail = error.read().decode(errors="replace")
                sys.exit(f"Qase {method} {path} failed: HTTP {error.code}\n{detail}")
            except urllib.error.URLError as error:
                if attempt < 4:
                    time.sleep(2 ** attempt)
                    continue
                sys.exit(f"Couldn't reach Qase: {error.reason}")
        sys.exit("Qase kept rate-limiting; try again later.")

    def all(self, path: str, extra: str = ""):
        entities, offset = [], 0
        while True:
            page = self.request("GET", path, query=f"?limit=100&offset={offset}{extra}")
            batch = page.get("entities", [])
            entities += batch
            offset += len(batch)
            if not batch or offset >= page.get("total", offset):
                return entities


# MARK: - Field values

class Fields:
    """Qase stores priority, severity and the like as numbers, which differ between
    workspaces. They're looked up by name from the workspace's own field list."""

    NAMES = ("priority", "severity", "type", "layer", "behavior", "status")

    def __init__(self, qase: Qase):
        self.values: dict[str, dict[str, int]] = {}
        for field in qase.request("GET", "system_field"):
            slug = field.get("slug")
            if slug in self.NAMES:
                options = {}
                for option in field.get("options") or []:
                    for name in (option.get("slug"), option.get("title")):
                        if name:
                            options[name.lower().replace(" ", "-")] = int(option["id"])
                self.values[slug] = options

    def value(self, field: str, name: str | None):
        if not name:
            return None
        found = self.values.get(field, {}).get(name.lower().replace(" ", "-"))
        if found is None:
            print(f"  warning: Qase has no {field} called '{name}'; left unset", file=sys.stderr)
        return found

    def describe(self):
        for field, options in sorted(self.values.items()):
            print(f"  {field}: {', '.join(sorted(set(options)))}")


# MARK: - The map of Qase ids

def load_map():
    if MAP_FILE.exists():
        return json.loads(MAP_FILE.read_text())
    return {"suites": {}, "cases": {}, "automated": {}, "plans": {}}


def save_map(ids):
    MAP_FILE.write_text(json.dumps(ids, indent=2, sort_keys=True) + "\n")


def ensure_suite(qase: Qase, ids, path: list[str], descriptions=None):
    """The suite at `path` (titles from the top), creating any part that's missing."""
    parent = None
    for depth in range(len(path)):
        key = " › ".join(path[: depth + 1])
        if key not in ids["suites"]:
            body = {"title": path[depth], "parent_id": parent}
            if descriptions and depth == len(path) - 1 and path[depth] in descriptions:
                body["description"] = descriptions[path[depth]]
            ids["suites"][key] = qase.request("POST", "suite/{code}", body)["id"]
            print(f"  + suite {key}")
        parent = ids["suites"][key]
    return parent


# MARK: - push-cases

def case_body(case, suite_id, fields: Fields):
    automated_by = case.get("automated_by", [])
    description = case.get("description", "")
    if automated_by:
        description += ("\n\n" if description else "") + "Automated by:\n" + "\n".join(f"- `{t}`" for t in automated_by)
    body = {
        "title": f"{case['key']} · {case['title']}",
        "description": description,
        "preconditions": case.get("preconditions", ""),
        "suite_id": suite_id,
        "tags": sorted(set(case.get("tags", [])) | {case["key"]}),
        # The API reference says true/false; the server only accepts 0 or 1.
        "isManual": 0 if automated_by else 1,
        "steps_type": "classic",
        "steps": [{"action": action, "expected_result": expected, "data": ""} for action, expected in case["steps"]],
    }
    for field in ("priority", "severity", "type", "layer", "behavior"):
        value = fields.value(field, case.get(field, "e2e" if field == "layer" else None))
        if value is not None:
            body[field] = value
    return body


def push_cases(qase: Qase, spec):
    ids = load_map()
    fields = Fields(qase)
    descriptions = {suite["title"]: suite.get("description", "") for suite in spec["suites"]}
    keys = [case["key"] for case in spec["cases"]]
    if len(keys) != len(set(keys)):
        sys.exit("Two cases share a key in QA/test-cases.json; every key must be unique.")

    new = []
    for case in spec["cases"]:
        body = case_body(case, ensure_suite(qase, ids, [case["suite"]], descriptions), fields)
        if case["key"] in ids["cases"]:
            qase.request("PATCH", f"case/{{code}}/{ids['cases'][case['key']]}", body)
            print(f"  ~ {case['key']}")
        else:
            new.append((case["key"], body))
    save_map(ids)

    for start in range(0, len(new), 50):
        batch = new[start:start + 50]
        created = qase.request("POST", "case/{code}/bulk", {"cases": [body for _, body in batch]})["ids"]
        for (key, _), case_id in zip(batch, created):
            ids["cases"][key] = case_id
            print(f"  + {key}")
        save_map(ids)

    push_plans(qase, spec, ids)
    save_map(ids)
    print(f"Done: {len(spec['cases'])} cases ({len(new)} new) in project {qase.project}.")


def push_plans(qase: Qase, spec, ids):
    for plan in spec.get("plans", []):
        tag = plan["tag"]
        cases = [ids["cases"][c["key"]] for c in spec["cases"]
                 if c["key"] in ids["cases"] and (tag == "*" or tag in c.get("tags", []))]
        if not cases:
            continue
        body = {"title": plan["title"], "description": plan.get("description", ""), "cases": cases}
        if plan["title"] in ids["plans"]:
            qase.request("PATCH", f"plan/{{code}}/{ids['plans'][plan['title']]}", body)
            print(f"  ~ plan {plan['title']} ({len(cases)} cases)")
        else:
            ids["plans"][plan["title"]] = qase.request("POST", "plan/{code}", body)["id"]
            print(f"  + plan {plan['title']} ({len(cases)} cases)")


# MARK: - push-results

def read_results(bundle: Path):
    """Every test in the bundle: (target, suite, test identifier, status, ms, message)."""
    output = subprocess.run(
        ["xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(bundle), "--format", "json"],
        capture_output=True, text=True,
    )
    if output.returncode != 0:
        sys.exit(f"Couldn't read {bundle}:\n{output.stderr}")
    tree = json.loads(output.stdout)

    results = []

    def failures(node):
        found = []
        for child in node.get("children", []):
            if child.get("nodeType") == "Failure Message":
                found.append(child.get("name", ""))
            found += failures(child)
        return found

    def walk(node, target=None, suite=None):
        kind = node.get("nodeType")
        if kind in ("Unit test bundle", "UI test bundle"):
            target = node["name"]
        elif kind == "Test Suite":
            suite = node["name"] if suite is None else f"{suite}/{node['name']}"
        elif kind == "Test Case":
            status = {"Passed": "passed", "Failed": "failed", "Skipped": "skipped",
                      "Expected Failure": "passed"}.get(node.get("result"), "invalid")
            identifier = node.get("nodeIdentifier") or f"{suite}/{node['name']}"
            results.append((target, suite or "Tests", f"{target}/{identifier}", node["name"], status,
                            int(float(node.get("durationInSeconds", 0)) * 1000), "\n".join(failures(node))))
            return
        for child in node.get("children", []):
            walk(child, target, suite)

    for node in tree.get("testNodes", []):
        walk(node)
    # A test that ran under several configurations or repetitions counts once, failed if any failed.
    merged = {}
    for result in results:
        previous = merged.get(result[2])
        if previous is None or result[4] == "failed":
            merged[result[2]] = result
    return list(merged.values())


def push_results(qase: Qase, spec, bundle: Path, title: str | None, include_linked: bool):
    ids = load_map()
    fields = Fields(qase)
    results = read_results(bundle)
    if not results:
        sys.exit("No tests found in the result bundle.")
    print(f"{len(results)} tests in {bundle.name}")

    # Make sure every automated test has its case.
    new = []
    for target, suite, identifier, name, *_ in results:
        if identifier not in ids["automated"]:
            suite_id = ensure_suite(qase, ids, [AUTOMATED_ROOT, target, *suite.split("/")])
            body = {"title": name, "suite_id": suite_id, "isManual": 0,
                    "description": f"Xcode test `{identifier}`.", "tags": ["automated", target]}
            layer = fields.value("layer", "e2e" if target.endswith("UITests") else "unit")
            if layer is not None:
                body["layer"] = layer
            new.append((identifier, body))
    save_map(ids)
    for start in range(0, len(new), 50):
        batch = new[start:start + 50]
        created = qase.request("POST", "case/{code}/bulk", {"cases": [body for _, body in batch]})["ids"]
        for (identifier, _), case_id in zip(batch, created):
            ids["automated"][identifier] = case_id
        save_map(ids)
        print(f"  + {len(batch)} automated cases")

    records = [{"case_id": ids["automated"][identifier], "status": status, "time_ms": ms,
                **({"comment": message, "stacktrace": message} if message else {})}
               for _, _, identifier, _, status, ms, message in results]

    if include_linked:
        by_identifier = {identifier: status for _, _, identifier, _, status, _, _ in results}
        for case in spec["cases"]:
            links = case.get("automated_by", [])
            if not links or case["key"] not in ids["cases"]:
                continue
            statuses = [status for identifier, status in by_identifier.items()
                        if any(identifier == link or identifier.startswith(link + "/") for link in links)]
            if statuses:
                status = "failed" if "failed" in statuses else "passed"
                records.append({"case_id": ids["cases"][case["key"]], "status": status,
                                "comment": f"From {len(statuses)} automated test(s) linked in automated_by."})

    run_title = title or f"Xcode · {bundle.stem}"
    run = qase.request("POST", "run/{code}", {
        "title": run_title, "is_autotest": True,
        "cases": sorted({record["case_id"] for record in records}),
        "description": f"Uploaded by Scripts/qase_sync.py from {bundle.name}.",
    })
    for start in range(0, len(records), 200):
        qase.request("POST", f"result/{{code}}/{run['id']}/bulk", {"results": records[start:start + 200]})
    qase.request("POST", f"run/{{code}}/{run['id']}/complete")

    counts = {}
    for record in records:
        counts[record["status"]] = counts.get(record["status"], 0) + 1
    print(f"Run '{run_title}' (#{run['id']}): " + ", ".join(f"{n} {s}" for s, n in sorted(counts.items())))
    print(f"https://app.qase.io/run/{qase.project}/dashboard/{run['id']}")


# MARK: - Main

def main():
    parser = argparse.ArgumentParser(description="Sync Lyre's test cases and results with Qase.")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("check", help="check the token and project, and list field values")
    commands.add_parser("push-cases", help="create or update suites, cases and plans")
    results = commands.add_parser("push-results", help="upload an Xcode result bundle as a test run")
    results.add_argument("bundle", type=Path)
    results.add_argument("--title")
    results.add_argument("--include-linked", action="store_true")
    args = parser.parse_args()

    token = os.environ.get("QASE_API_TOKEN")
    if not token:
        sys.exit("Set QASE_API_TOKEN first (Qase: your avatar > API tokens).")
    spec = json.loads(CASES_FILE.read_text())
    qase = Qase(token, os.environ.get("QASE_PROJECT", spec["project"]))

    if args.command == "check":
        project = qase.request("GET", "project/{code}")
        print(f"Project {project.get('code')}: {project.get('title')}")
        Fields(qase).describe()
    elif args.command == "push-cases":
        push_cases(qase, spec)
    else:
        if not args.bundle.exists():
            sys.exit(f"No result bundle at {args.bundle}")
        push_results(qase, spec, args.bundle, args.title, args.include_linked)


if __name__ == "__main__":
    main()

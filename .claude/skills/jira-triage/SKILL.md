---
name: jira-triage
description: Pick up the next Lyre Jira issue labeled "claude" (project LYRE on lyre-app.atlassian.net), fix or build it on a local branch, test it, and merge it into local main once it passes. Use when the user says "check Jira", "/jira-triage", or the 15-minute loop fires. Also covers pushing to GitHub and TestFlight when the user asks.
---

# Jira triage for Lyre

Daniel files bugs and feature requests in Jira (site `lyre-app.atlassian.net`, cloudId
`0e15c93f-24fb-41a9-99bc-9cc27b5a944f`, project **LYRE**). Issues he labels `claude` are
handed to you. You fix or build them on a branch, test them, and once they pass, merge
them into the **local** `main` yourself and leave `main` checked out, so Daniel can run
the latest from Xcode without approving each one (his standing instruction, 2026-10-22).
You never push to GitHub or upload to TestFlight until he asks for it here, in Claude Code,
in so many words.

Workflow statuses (transition ids): To Do (11) · In Progress (21) · In Review (31) · Done (41).
Look them up with `getTransitionsForJiraIssue` if an id is refused.

Every comment you post starts with `🤖 Claude:`. Comments are posted as Daniel's account,
so the prefix is the only way to tell yours from his.

## 1. Find work

Run this JQL (`searchJiraIssuesUsingJql`):

```
project = LYRE AND labels = claude AND labels != needs-info AND status = "To Do"
ORDER BY priority DESC, created ASC
```

- Nothing found: say so in one line ("No LYRE issues labeled claude are waiting.") and stop.
- Otherwise take the **first** issue only. One at a time, so builds and the simulator never collide.

## 2. Check it's safe to start

In the repo (`/Users/danielbuzlea/Desktop/code/Programs/Swift/Projects/Lyre`):

- `git status --porcelain`: if there are uncommitted changes, **stop**. Don't pick the
  issue up. Report which files are dirty and ask Daniel what to do. Never stash, reset or
  commit work you didn't make for this issue.
- If the current branch is a `LYRE-*` branch, an earlier issue was left unfinished (its
  tests failed). That's fine: branch the new issue from `main`, not from it.

## 3. Read the issue

Get the issue with `getJiraIssue` (fields: summary, description, issuetype, priority,
labels, comment, attachment; `responseContentFormat: markdown`). Attachments can't be
downloaded through the connector. If a screenshot matters, ask Daniel to paste it here.

Decide whether you can act on it:

- **A bug** needs steps to reproduce, expected and actual results. Device and build help.
- **A feature request** needs what it should do and where. If it has open design
  questions, or is more than a contained change (several players, new screens, data
  model changes), don't build it yet: go to "Ask first" with a short plan and your questions.

**Ask first:** comment with exactly what's missing or the plan and the questions, add the
label `needs-info` (`editJiraIssue`, keep the existing labels), leave it in To Do, and
tell Daniel here. He removes `needs-info` once he's answered, and the next check picks it
up again.

## 4. Work on it

1. Transition to **In Progress**; comment `🤖 Claude: Picked this up. Working on branch LYRE-N-short-slug.`
2. `git switch main && git switch -c LYRE-N-short-slug` (lowercase slug from the summary, ≤ 5 words).
3. Reproduce or locate the problem in code before changing anything. Find the cause, not a workaround.
4. Make the change in the style of the surrounding code (comment density, naming, idiom).
5. Add a test that would have caught it. Prefer a unit test in `Lyre/LyreTests` (Swift
   Testing); add a UI test in `Lyre/LyreUITests` when the bug is about what's on screen.
   Name the issue key in a comment on the test (`/// LYRE-N: …`).
6. If it's something checked by hand on a device, add a case to `QA/test-cases.json` with
   `automated_by` set where a test covers it (Daniel pushes it to Qase with
   `python3 Lyre/Scripts/qase_sync.py push-cases`).

## 5. Test it

Use the booted **Lyre iPhone Duo** simulator (`xcrun simctl list devices booted`).

```sh
cd Lyre
xcodebuild build-for-testing -scheme Lyre -destination 'id=<sim>'
xcodebuild test-without-building -scheme Lyre -testPlan Unit -destination 'id=<sim>'
# UI tests must name a plan that includes them:
xcodebuild test-without-building -scheme Lyre -testPlan Regression -destination 'id=<sim>' \
  -parallel-testing-enabled NO -only-testing:LyreUITests/<Suite>/<test>
```

- Run the Unit plan, your new test, and the UI tests for the area you touched.
- For anything visual, look at the test's screenshots (`xcrun xcresulttool export
  attachments`) and check them yourself before reporting.
- Known failures that aren't yours: `SpoolSoundTests/theGramophonesSoundsAreShortEnoughToKeepUp`
  (LYRE-4) and 7 LiquidUITests (LYRE-3). Report them as known, not as new.
- If it doesn't build or your tests fail and you can't fix it, say so plainly in the
  comment and leave the issue In Progress.

## 6. Merge it

Only when it builds and your tests pass (known failures aside). Otherwise leave it on its
branch, In Progress, and tell Daniel.

1. Commit on the branch:
   `git commit -m "LYRE-N: <what changed>"` plus a body (cause, fix, tests) and the
   attribution lines the session asks for. Don't commit unrelated files.
2. Merge into the local `main` and stay there:
   `git switch main && git merge --no-ff LYRE-N-slug -m "Merge LYRE-N: <summary>"`.
   If it conflicts, resolve it if the resolution is obvious; if not, `git merge --abort`,
   leave the issue In Progress and ask Daniel.
3. Build `main` once more (`xcodebuild build-for-testing …`) so what Xcode runs compiles.
4. Comment on the issue:
   ```
   🤖 Claude: Merged into local main (not pushed, not on TestFlight).
   Cause: …
   Change: …
   Tests: … (passed / known failures)
   To verify on your phone: run from Xcode, then …
   ```
5. Transition to **Done**.
6. Tell Daniel here in two or three lines: the key, what changed, and how to check it.

## When Daniel asks to push or ship

Only when he says so here, and only for what he names:

1. Push to GitHub (`git push origin main`) only if he asked for GitHub.
2. TestFlight only if he asked for TestFlight: confirm the version and build number with him
   first, then archive and upload.
3. Comment on the issues it carried what was shipped where.

"Push" doesn't mean TestFlight. Ask if it's unclear which he meant.

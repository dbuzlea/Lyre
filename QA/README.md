# QA

How Lyre is tested, and how the tests get into Qase.

| File | What it is |
|---|---|
| [TestPlan.md](TestPlan.md) | The master test plan: scope, approach, environments, when each plan runs, when a build can ship, known defects |
| [test-cases.json](test-cases.json) | Every hand-written test case, grouped into suites, with the Xcode tests that cover each one |
| `qase-map.json` | Created by the sync script: which Qase id belongs to which case. Commit it. |
| `../Lyre/TestPlans/*.xctestplan` | The Xcode test plans: Unit, Smoke, Regression, Screenshots, Performance |
| `../Lyre/Scripts/qase_sync.py` | Pushes cases and Xcode results to Qase |

## How the pieces fit

```
QA/test-cases.json ──push-cases──▶  Qase: suites, cases, test plans
                                        │
Xcode test plan ──▶ .xcresult ──push-results──▶  Qase: a test run with every automated result
                                        │
You, on a device ─────────────────▶  Qase: manual test runs, defects
```

- **Cases live in the repo**, so they're versioned with the code they test and reviewed
  in the same commit. Edit `test-cases.json`, then push. Don't edit cases in Qase's
  editor: the next push overwrites them.
- **Automated tests need no list.** Each test in a result bundle becomes a case under
  *Automated › LyreTests / LyreUITests › Suite* the first time it's uploaded.
- **Manual results are recorded in Qase**, in a test run made from one of the test
  plans (Smoke, Release Regression, …).

## One-time setup

1. Sign up at [qase.io](https://qase.io) (the free plan is enough).
2. Create a project named **Lyre** with the code **LYRE**.
3. Create an API token: avatar (bottom left) > **API Tokens** > **Create new token**.
4. In Terminal:
   ```sh
   echo 'export QASE_API_TOKEN=<paste the token>' >> ~/.zshrc && source ~/.zshrc
   cd ~/Desktop/code/Programs/Swift/Projects/Lyre/Lyre
   python3 Scripts/qase_sync.py check        # shows the project and the field values it accepts
   python3 Scripts/qase_sync.py push-cases   # creates 14 suites, 75 cases and 5 test plans
   ```

## Everyday use

**Run the automated tests and send the results to Qase.**
```sh
xcodebuild test -scheme Lyre -testPlan Smoke \
  -destination 'platform=iOS Simulator,name=Lyre iPhone Duo' \
  -resultBundlePath /tmp/Smoke.xcresult
python3 Scripts/qase_sync.py push-results /tmp/Smoke.xcresult --title "Smoke · 2.5.2 (8)"
```
(In Xcode: choose the plan from Product > Test Plan, then ⌘U. The result bundle is
under Report navigator > the run > right-click > Show in Finder.)

**Run one UI test from the command line.** ⌘U and plain `xcodebuild test` use the
**Unit** plan, which has no UI tests, so name a plan that does:
`xcodebuild test -scheme Lyre -testPlan Regression -only-testing:LyreUITests/LiquidUITests/testSearchFindsAnAlbum …`.
In Xcode, the diamond beside any test runs it under whichever plan includes it.

**Run the manual cases.** In Qase: **Test Runs** > **Start new test run** > *From test
plan* > pick Smoke (or Release Regression) > set the build in the title. Walk each
case on a device and mark it Passed / Failed / Blocked / Skipped. On a failure, use
**Create defect** so the bug links back to its case.

**Add a case.** Add an entry to `test-cases.json` with a new key in its area's series
(`ONB-09`, `NET-09`, …), then `push-cases`. Keys are permanent: never reuse one, even
after a case is deleted.

**Link a case to automation.** List the tests under `automated_by` as
`Target/Suite/test()`, or `Target/Suite` for a whole suite. A case with links counts as
automated in Qase; one without is manual. `push-results --include-linked` then also
marks a linked case passed (all its tests passed) or failed (any failed). Only use it
when the links really cover the case.

## Vocabulary

| Term | Meaning here |
|---|---|
| Test case | One behavior to check, with steps and expected results (`ONB-01`) |
| Suite | A group of cases for one area (Onboarding) |
| Test plan | A chosen set of cases run together for a purpose (Smoke) |
| Test run | One execution of a plan against one build, with a result per case |
| Defect | A failure worth fixing, linked to the run and case that found it |
| Priority / Severity | How much testing a case deserves / how bad its failure is |
| Flaky | A test that passes and fails without the code changing: fix it, don't retry it |
| Regression | Something that used to work and broke |
| Smoke test | A quick check that the build is fit to test further |
| Exploratory testing | Unscripted, time-boxed testing guided by a charter |

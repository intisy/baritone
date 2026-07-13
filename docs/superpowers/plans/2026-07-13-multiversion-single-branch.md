# Multi-Version Single-Branch Baritone — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse the fork's ~35 branches into one `master` branch that builds Baritone for every Minecraft version 1.16.5 → 1.21.11 (all upstream loaders per version), verified by CI, with the fork's 8 custom features shared across all versions.

**Architecture:** A single branch based on `upstream/1.21.11` + the 8 custom commits. [Stonecutter](https://stonecutter.kikugie.dev) (`dev.kikugie.stonecutter`) adds the version dimension on top of the existing **unimined** toolchain; version-specific code becomes Stonecutter comment conditionals. Migration proceeds newest→oldest, one version per step, each step ending in a buildable state. Versions 1.16.5–1.18.2 are on a different toolchain/mappings and are **ported onto unimined+Mojmap** before folding in.

**Tech Stack:** Gradle (Groovy DSL), unimined (`xyz.wagyourtail.unimined`), Stonecutter `0.9`, Java 8/16/17/21 toolchains, Fabric/Forge/NeoForge/Tweaker loaders, JUnit 4, GitHub Actions.

## Global Constraints

- **Single branch name:** `master` on `origin` (`https://github.com/intisy/baritone.git`).
- **Base commit:** `upstream/1.21.11` HEAD; the 8 custom commits `cf8fb197 ca87ec8c a4ed2b68 3b8ce5f7 5927b205 f82d6ad9 0bc3f099 20e5bb8d` cherry-picked on top, in that order (oldest→newest).
- **Nothing irreversible before green:** tag + push `archive/1.21.4-custom` before deleting any branch; delete branches only after new `master` builds.
- **Never force-delete unmerged work without the archive tag existing first.**
- **Mapping/toolchain:** unimined + Mojmap is the only toolchain for every target. Legacy versions (1.16.5, 1.17.1, 1.18.2) must be ported to it before folding in — Stonecutter cannot bridge toolchains.
- **Loaders per version = whatever that upstream branch ships** (see Version Matrix). Do not add loaders a version never had.
- **CLAUDE.md rules:** never delete existing code without asking; comments only on non-obvious logic; meaningful names.
- **Every milestone ends buildable:** all previously-integrated versions must still compile before starting the next.

### Version Matrix (verified from upstream branches 2026-07-13)

| MC version | Java | Loaders | Toolchain state |
| --- | --- | --- | --- |
| 1.21.11 (base) | 21 | fabric, forge, neoforge, tweaker | native unimined |
| 1.21.10, 1.21.8, 1.21.5, 1.21.4, 1.21.3, 1.21.1, 1.21 | 21 | fabric, forge, neoforge, tweaker | native unimined |
| 1.20.5 | 21 | fabric, forge, neoforge, tweaker | native unimined |
| 1.20.4 | 17 | fabric, forge, neoforge, tweaker | native unimined |
| 1.20.2, 1.20.1 | 17 | fabric, forge, tweaker | native unimined |
| 1.19.4, 1.19.3, 1.19.2 | 17 | fabric, forge, tweaker | native unimined |
| 1.18.2 | 17 (confirm) | fabric, forge, tweaker | **PORT to unimined** |
| 1.17.1 | 16 (confirm) | fabric, forge, tweaker | **PORT to unimined** |
| 1.16.5 | 8 (confirm) | fabric, forge, tweaker(launchwrapper) | **PORT from ForgeGradle3+loom(MCP)** |

---

## File Structure

Files created / modified across the whole plan:

- `settings.gradle` — **Modify.** Add Stonecutter plugin + `pluginManagement` repo; wrap subproject includes so they work under Stonecutter nodes.
- `stonecutter.gradle` (root controller) — **Create.** Declares active version; registers `chiseledBuild`; per-version params (constants/swaps).
- `build.gradle` — **Modify.** Read `minecraft_version`/`java_version`/loaders from the active Stonecutter node instead of the single hard-coded `gradle.properties`.
- `gradle.properties` — **Modify.** Strip the single `minecraft_version=1.21.4`; keep shared, version-independent props (mod_version, maven_group, mixin/asm).
- `versions/<mcver>/gradle.properties` — **Create per version.** Per-target constants (minecraft_version, java_version, forge/fabric/neoforge versions, available_loaders).
- `src/**/*.java`, `fabric/**`, `forge/**`, `neoforge/**`, `tweaker/**` — **Modify incrementally.** Stonecutter conditionals added as each older version is folded in.
- `.github/workflows/build.yml` — **Create.** CI matrix building every version×loader via `chiseledBuild`.
- `.github/workflows/release.yml` — **Modify/Create.** Publish full jar set on tag.
- `docs/superpowers/plans/PROGRESS.md` — **Create.** Running log of which versions are folded in and green (survives context breaks).

---

## Phase M0 — Consolidate to one branch

### Task 1: Safety archive of current custom work

**Files:** none (git refs only)

- [ ] **Step 1: Verify the 8 custom commits are exactly what's expected**

Run:
```bash
cd "F:/Documents/GitHub/minecraft/mod/baritone"
git log --oneline upstream/1.21.4..origin/1.21.4
```
Expected: exactly these 8, newest first:
```
20e5bb8d Added smoothLook support for Sprint Swimming
0bc3f099 Added support for swimming up single water blocks
f82d6ad9 Cleaned up Swimming and Jumping logic
5927b205 Removed the Sneak Input from the Sprint Swim
3b8ce5f7 Added Sprint Swimming
a4ed2b68 Added Spint Jumping and Head Hitters
ca87ec8c Added some conditions to ignore NPCs
cf8fb197 Added player avoidance
```
If the list differs, STOP and re-confirm with the user before proceeding.

- [ ] **Step 2: Create and push the archive tag**

```bash
git tag -a archive/1.21.4-custom origin/1.21.4 -m "Archive of pre-restructure custom work (8 commits on 1.21.4)"
git push origin archive/1.21.4-custom
```

- [ ] **Step 3: Verify the tag exists on the remote**

Run: `git ls-remote --tags origin archive/1.21.4-custom`
Expected: one line showing the tag SHA. If empty, STOP — the archive must exist before any deletion.

- [ ] **Step 4: Commit** — no commit (refs only). Record in progress log:

```bash
mkdir -p docs/superpowers/plans
printf '# Restructure progress\n\n- M0 Task1: archive/1.21.4-custom pushed. Custom commits preserved.\n' > docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "chore: start restructure progress log; archive tag pushed"
```

### Task 2: Build the new `master` (1.21.11 base + custom commits)

**Files:** none (git history); this establishes the branch all later tasks build on.

**Interfaces:**
- Produces: local branch `master` at `upstream/1.21.11` + 8 cherry-picked commits, plus the M0-Task1 progress commit.

- [ ] **Step 1: Fetch and create the branch from upstream/1.21.11**

```bash
git fetch upstream --prune && git fetch origin --prune
git switch -c restructure-master upstream/1.21.11
```
(We build on a temp name `restructure-master`; it becomes `master` in Task 4 after it's green.)

- [ ] **Step 2: Cherry-pick the 8 custom commits (oldest→newest), then carry the docs**

The spec + plan docs currently live only on the old `1.21.4` branch and must be carried onto the new branch or they are lost when `1.21.4` is deleted in Task 4.

```bash
git cherry-pick cf8fb197 ca87ec8c a4ed2b68 3b8ce5f7 5927b205 f82d6ad9 0bc3f099 20e5bb8d
# Carry all restructure docs from 1.21.4 (SHA-independent, survives extra doc commits):
git checkout 1.21.4 -- docs/superpowers
git commit -m "docs: carry spec + plan onto restructured branch"
```

- [ ] **Step 3: Resolve conflicts per commit if they arise**

The custom commits were authored on 1.21.4; against 1.21.11 the movement/input classes may have moved. For each conflicted file:
- Open the file, find `<<<<<<<`/`=======`/`>>>>>>>` markers.
- Keep the custom-feature intent (player avoidance, sprint jump/swim), adapt to 1.21.11 signatures.
- `git add <file>` then `git cherry-pick --continue`.
If a commit is wholly obsolete on 1.21.11, `git cherry-pick --skip` and note it in PROGRESS.md with the reason.

- [ ] **Step 4: Verify the custom feature code is present**

Run:
```bash
git log --oneline -9
git grep -l -iE "sprint.?swim|player.?avoid|head.?hitter" -- 'src/**/*.java' | head
```
Expected: the 8 (or fewer, if any skipped) commits listed; grep returns at least one source file. If grep is empty, the features didn't land — investigate before continuing.

- [ ] **Step 5: Build the untouched 1.21.11 base to confirm a clean starting point**

Run: `./gradlew build --console=plain`
Expected: `BUILD SUCCESSFUL`. This is vanilla-upstream + custom code with NO Stonecutter yet, so it must pass. If it fails, the failure is in conflict resolution — fix before Task 3.

- [ ] **Step 6: Commit** — history already recorded by cherry-pick. Log progress:

```bash
printf -- '- M0 Task2: restructure-master = upstream/1.21.11 + custom commits; base build green.\n' >> docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "chore: master base built (1.21.11 + custom), build green"
```

### Task 3: Confirm custom features still behave on 1.21.11 (manual smoke)

**Files:** none.

- [ ] **Step 1: Build the fabric jar and launch a dev client**

Run: `./gradlew runClient` (or the project's documented run task from `SETUP.md`).
Expected: client launches, Baritone loads (check log for `Baritone` init line).

- [ ] **Step 2: Manually verify one custom feature**

In-game or via logs, confirm sprint-swimming/player-avoidance settings are registered (e.g. run `#help` and look for the added settings, or check the settings class loaded without error). Record result in PROGRESS.md. This is a spot-check, not automated.

- [ ] **Step 3: Commit** — log only:

```bash
printf -- '- M0 Task3: manual smoke on 1.21.11 client OK (features load).\n' >> docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "chore: manual smoke of custom features on 1.21.11"
```

### Task 4: Promote to `master`, push, and delete all other branches

**Files:** none (git refs). **This is the irreversible step — the archive tag from Task 1 MUST exist.**

**Interfaces:**
- Consumes: `restructure-master` (green), `archive/1.21.4-custom` (pushed).
- Produces: `origin/master` as the sole branch; all others deleted.

- [ ] **Step 1: Re-verify the archive tag is on the remote (guard)**

Run: `git ls-remote --tags origin archive/1.21.4-custom`
Expected: non-empty. If empty, STOP and redo Task 1.

- [ ] **Step 2: Rename local branch to `master` and push**

```bash
git branch -M restructure-master master
git push -u origin master
```

- [ ] **Step 3: Set origin's default branch to `master`** (so `origin/HEAD` no longer points at `1.19.4`)

Run: `gh repo edit intisy/baritone --default-branch master`
Expected: no error. (If `gh` is unavailable, tell the user to set the default branch to `master` in GitHub settings before Step 4.)

- [ ] **Step 4: Delete all other origin branches**

Delete exactly these (every origin branch except `master`):
```bash
for b in 1.13.2 1.14.4 1.15.2 1.16.5 1.17.1 1.18.2 1.19.2 1.19.3 1.19.4 \
         1.20.1 1.20.2 1.20.4 1.20.5 1.21 1.21.1 1.21.10 1.21.3 1.21.4 1.21.5 1.21.8 \
         benchmark bepitone binary-heap-optims-maybe bot-system builder-2 builder-2-mutating \
         mapping originalblockpos sounds tenor walkthrough-walkon-export zephreo-suggestion \
         pr/elytra/basedWorkQueue pr/inventoryImprovements; do
  git push origin --delete "$b" || echo "WARN: could not delete $b (may not exist)"
done
git push origin --delete master 2>/dev/null; echo "(the origin 'master' above refers to the OLD upstream-mirror master if present — verify it is not our new one)"
```
NOTE: origin currently has an old `master` branch (upstream mirror). Our new branch is also `master`. Do **not** delete our new one. Since we pushed our `master` in Step 2, the old mirror is already overwritten — skip the last line if `git log origin/master` shows our custom commits.

- [ ] **Step 5: Delete stale local branches**

```bash
git branch -D 1.19.4 1.20.4 1.21.4 2>/dev/null || true
```

- [ ] **Step 6: Verify only `master` remains on origin**

Run: `git ls-remote --heads origin`
Expected: a single line ending in `refs/heads/master`. Record in PROGRESS.md.

- [ ] **Step 7: Commit** — log only:

```bash
printf -- '- M0 Task4: master pushed, default branch set, all other origin+local branches deleted. Single-branch achieved.\n' >> docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "chore: single-branch consolidation complete" && git push
```

---

## Phase M1 — Stonecutter scaffold (single version first)

### Task 5: Integration spike — Stonecutter × unimined × multi-loader

**Files:** throwaway branch; no permanent changes yet.

The open question: Baritone builds all loaders as Gradle subprojects from one version; Stonecutter models versions (optionally × loader "variants") as its own nodes. We must pick the layout where **one Stonecutter node = one MC version, and that node still builds all of Baritone's loader subprojects.**

- [ ] **Step 1: Create a spike branch**

```bash
git switch -c spike/stonecutter master
```

- [ ] **Step 2: Add Stonecutter to `settings.gradle` (Groovy) with a single version node**

Add to the top of `settings.gradle`, inside `pluginManagement { repositories { ... } }`:
```groovy
maven { url = 'https://maven.kikugie.dev/releases' }
```
Add after the existing `plugins { }` block:
```groovy
plugins {
    id 'dev.kikugie.stonecutter' version '0.9'
}
stonecutter {
    create(rootProject) {
        versions('1.21.11')
        vcsVersion = '1.21.11'
    }
}
```

- [ ] **Step 3: Create a minimal root `stonecutter.gradle`**

```groovy
plugins { id 'dev.kikugie.stonecutter' }
stonecutter active '1.21.11'
```

- [ ] **Step 4: Try to build through Stonecutter**

Run: `./gradlew "Set active project to 1.21.11" build --console=plain` (or `./gradlew chiseledBuild`).
Expected outcome is one of:
  - **A (success):** builds green → the "version-only node, keep loader subprojects" layout works. Record layout A in PROGRESS.md.
  - **B (conflict):** Stonecutter and unimined fight over subproject creation → try declaring the loader subprojects *inside* the Stonecutter node, or move to the **fallback** (Task 5b).

- [ ] **Step 5: Decide and record**

Write the chosen layout (A, B, or fallback) into `docs/superpowers/plans/PROGRESS.md` with the exact working `settings.gradle`/`stonecutter.gradle` snippet. This decision governs Tasks 6–8.

- [ ] **Step 6: Discard the spike (keep only the notes)**

```bash
git switch master && git branch -D spike/stonecutter
```
Commit the notes:
```bash
git add docs/superpowers/plans/PROGRESS.md && git commit -m "docs: record Stonecutter integration layout decision (M1 spike)"
```

### Task 5b (FALLBACK, only if Task 5 outcome = unworkable): property-swap multi-version

If Stonecutter cannot coexist with unimined's subproject model, use the same single branch but switch versions via a Gradle property instead of comment-preprocessing.

- [ ] **Step 1: Add version selection to `build.gradle`**

Replace the hard-coded read with:
```groovy
def mcVersion = project.hasProperty('mc') ? project.mc : '1.21.11'
def vprops = new Properties()
file("versions/${mcVersion}/gradle.properties").withInputStream { vprops.load(it) }
```
Then use `vprops.minecraft_version`, `vprops.java_version`, `vprops.available_loaders`.

- [ ] **Step 2: Build a chosen version**

Run: `./gradlew build -Pmc=1.21.11`
Expected: `BUILD SUCCESSFUL`.

- [ ] **Step 3: Commit and STOP for user decision**

The fallback drops source-level conditionals (versions that need different *code* can't share one file this way — they'd need per-version source dirs). If reached, commit notes and ask the user whether to accept per-version source overlays for divergent files or reconsider the version floor.

### Task 6: Make `build.gradle` read per-version constants

**Files:** Modify `build.gradle`, `gradle.properties`; Create `versions/1.21.11/gradle.properties`.

**Interfaces:**
- Produces: `build.gradle` sources `minecraft_version`, `java_version`, `available_loaders` from the active version node (per Task 5's chosen layout).

- [ ] **Step 1: Create `versions/1.21.11/gradle.properties`**

```properties
minecraft_version=1.21.11
java_version=21
available_loaders=fabric,forge,neoforge,tweaker
forge_version=54.0.5
neoforge_version=9-beta
fabric_version=0.16.9
```
(Confirm the forge/neoforge/fabric versions from `upstream/1.21.11:gradle.properties`; copy its exact values.)

- [ ] **Step 2: Remove the single hard-coded version from root `gradle.properties`**

Delete the line `minecraft_version=1.21.4` and the single `available_loaders=` / `java_version=` / per-loader version lines that are now per-version. Keep `mod_version`, `maven_group`, `archives_base_name`, `mixin_version`, `asm_version`, `nether_pathfinder_version`, `org.gradle.jvmargs`.

- [ ] **Step 3: Point `build.gradle` at the active node's properties**

Per Task 5 layout A, Stonecutter exposes the node dir; read `versions/${stonecutter.current.version}/gradle.properties` (exact accessor recorded in PROGRESS.md from the spike). Wire `minecraft_version`, `java_version`, and the `available_loaders.split(',')` include loop in `settings.gradle` to use it.

- [ ] **Step 4: Build**

Run: `./gradlew chiseledBuild --console=plain`
Expected: `BUILD SUCCESSFUL`, producing 1.21.11 fabric/forge/neoforge/tweaker jars under `build/libs` (or per-node build dirs).

- [ ] **Step 5: Verify jars exist**

Run: `ls build/libs || find . -path '*/build/libs/*.jar'`
Expected: jars for each of the 4 loaders. Record in PROGRESS.md.

- [ ] **Step 6: Commit**

```bash
git add settings.gradle stonecutter.gradle build.gradle gradle.properties versions/1.21.11/gradle.properties docs/superpowers/plans/PROGRESS.md
git commit -m "build: Stonecutter scaffold; 1.21.11 builds all loaders via per-version props"
```

---

## Phase M2–M5 — Fold in older versions (repeatable recipe)

> These phases add one MC version at a time. Each addition is the **same recipe**; only the version numbers and (for M5) the port step differ. Do NOT try to add multiple versions at once. Order: 1.21.10, 1.21.8, 1.21.5, 1.21.3, 1.21.1, 1.21 (M2) → 1.20.5, 1.20.4, 1.20.2, 1.20.1 (M3) → 1.19.4, 1.19.3, 1.19.2 (M4) → 1.18.2, 1.17.1, 1.16.5 (M5, port-first).

### Task 7: RECIPE — fold in one native-unimined version `V` (the M2–M4 loop)

Repeat this entire task for each version in M2–M4 order. `PREV` = the nearest already-integrated newer version (start: PREV=1.21.11, V=1.21.10).

**Files:** Create `versions/<V>/gradle.properties`; Modify `src/**` / loader dirs where code diverges.

**Interfaces:**
- Consumes: a green tree containing `PREV`.
- Produces: a green tree that also builds `V`; `versions/<V>/gradle.properties`; Stonecutter conditionals for each diverging file.

- [ ] **Step 1: Add `V` to the Stonecutter version list**

In `settings.gradle`, add `V` to `versions(...)`. Keep `vcsVersion = '1.21.11'` (dev default stays newest).

- [ ] **Step 2: Create `versions/<V>/gradle.properties`**

Copy the exact values from `upstream/<V>:gradle.properties`:
```bash
git show upstream/<V>:gradle.properties
```
Populate `minecraft_version`, `java_version`, `available_loaders`, and the loader versions per the Version Matrix.

- [ ] **Step 3: Compute the exact code delta between `PREV` and `V`**

```bash
git diff upstream/<PREV> upstream/<V> -- '*.java' > /tmp/delta-<V>.patch
git diff --stat upstream/<PREV> upstream/<V> -- '*.java'
```
This patch is the authoritative list of files/lines that differ. Every hunk here becomes a conditional.

- [ ] **Step 4: For each differing file, wrap the divergent lines in a Stonecutter conditional**

Stonecutter conditional syntax (verify exact form against the version recorded in PROGRESS.md; `0.9` uses `//?`):
```java
//? if <1.21.11 {
/*oldApiCall();*/
//?} else {
newApiCall();
//?}
```
Worked example (hypothetical rename `Foo.bar()`→`Foo.baz()` introduced in 1.21.11):
- Shared source (active=1.21.11) has `foo.baz();`.
- To support `V=1.21.10` which used `foo.bar();`, edit the file to:
```java
//? if >=1.21.11 {
foo.baz();
//?} else {
/*foo.bar();*/
//?}
```
Apply one file at a time; re-run the switch+build between files if a file is large.

- [ ] **Step 5: Switch active version to `V` and build only it**

Run: `./gradlew "Set active project to <V>" build --console=plain`
Expected: `BUILD SUCCESSFUL`. Fix remaining conditionals until green.

- [ ] **Step 6: Switch back to 1.21.11 and build — prove no regression**

Run: `./gradlew "Set active project to 1.21.11" build --console=plain`
Expected: `BUILD SUCCESSFUL`. (Conditionals must not break the newest version.)

- [ ] **Step 7: Build ALL integrated versions**

Run: `./gradlew chiseledBuild --console=plain`
Expected: `BUILD SUCCESSFUL` for every version added so far. This enforces the "all prior versions stay green" constraint.

- [ ] **Step 8: Run tests for `V`**

Run: `./gradlew "Set active project to <V>" test --console=plain`
Expected: existing JUnit tests pass. Record failures (some tests may be version-sensitive) in PROGRESS.md.

- [ ] **Step 9: Commit and log**

```bash
printf -- '- Folded in <V> (loaders: <list>). chiseledBuild green across N versions.\n' >> docs/superpowers/plans/PROGRESS.md
git add -A && git commit -m "build: fold in Minecraft <V> via Stonecutter conditionals"
```

- [ ] **Step 10: Advance** — set `PREV=V`, `V=`next version in order, repeat Task 7. When 1.19.2 is done, proceed to Task 8.

### Task 8: RECIPE — port then fold in a legacy version (M5: 1.18.2 → 1.17.1 → 1.16.5)

Legacy versions are NOT on unimined+Mojmap. Each must be ported first. Do them strictly in order 1.18.2, then 1.17.1, then 1.16.5 (each easier as a stepping stone to the next). `V` = legacy version, `PREV` = nearest integrated newer version.

**Files:** Create `versions/<V>/gradle.properties`; Modify `build.gradle`/loader configs for the older toolchain constants; Modify `src/**` for conditionals.

- [ ] **Step 1: Study the upstream legacy build to know what must change**

```bash
git show upstream/<V>:gradle.properties
git show upstream/<V>:build.gradle | head -120
```
Identify: mapping provider (1.16.5 = MCP/SRG via ForgeGradle3+loom; 1.17.1/1.18.2 = OFFICIAL), Java version, loader versions, tweaker/launchwrapper specifics.

- [ ] **Step 2: Create `versions/<V>/gradle.properties` targeting unimined+Mojmap**

Set `minecraft_version=<V>`, correct `java_version` (1.16.5→8, 1.17.1→16, 1.18.2→17; confirm), `available_loaders`, and loader versions valid for `<V>`. The mappings block in `build.gradle` stays Mojmap (unimined) — we are porting, not preserving the old mapping set.

- [ ] **Step 3: Switch active to `V` and attempt an unimined build; fix toolchain errors**

Run: `./gradlew "Set active project to <V>" build --console=plain`
Work through unimined/toolchain errors first (Java toolchain availability, mapping resolution, missing intermediary for old versions). These are configuration errors, not source conditionals. Record each fix in PROGRESS.md. For 1.16.5, expect to also handle launchwrapper/tweaker and possibly a Java 8 toolchain install.

- [ ] **Step 4: Compute source delta and add conditionals (same as Task 7 Steps 3–4)**

```bash
git diff upstream/<PREV> upstream/<V> -- '*.java' > /tmp/delta-<V>.patch
```
Because mappings differ from upstream-legacy (they used obfuscated/OFFICIAL names, we use Mojmap), the *diff will not apply cleanly as names* — use it to locate WHICH classes/methods diverge behaviorally, then express the Mojmap-equivalent change as a conditional. This is the manual, expensive part, especially for 1.16.5.

- [ ] **Step 5–9: Same as Task 7 Steps 5–9** (build V, build 1.21.11, `chiseledBuild` all, test, commit).

- [ ] **Step 10: If 1.16.5 proves too costly, STOP and consult user**

Per spec, M5 is pausable after any sub-milestone. If 1.16.5 blocks, commit progress, ensure 1.17.1-and-up are green, and ask the user whether to ship with a higher floor. Do not leave the tree non-building.

---

## Phase M6 — CI matrix and releases

### Task 9: GitHub Actions build matrix

**Files:** Create `.github/workflows/build.yml`.

**Interfaces:**
- Consumes: a repo where `./gradlew chiseledBuild` builds all integrated versions locally.

- [ ] **Step 1: Write the workflow**

```yaml
name: build
on:
  push:
    branches: [master]
  pull_request:
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: |
            8
            16
            17
            21
      - name: Build all versions
        run: ./gradlew chiseledBuild --console=plain --stacktrace
      - uses: actions/upload-artifact@v4
        with:
          name: baritone-jars
          path: '**/build/libs/*.jar'
```

- [ ] **Step 2: Validate locally (dry sanity)**

Run: `./gradlew chiseledBuild --console=plain`
Expected: `BUILD SUCCESSFUL`. (CI mirrors this.)

- [ ] **Step 3: Commit and push; watch the run**

```bash
git add .github/workflows/build.yml && git commit -m "ci: build all Minecraft versions via chiseledBuild" && git push
```
Then: `gh run watch` (or check Actions tab). Expected: green. Fix multi-JDK/toolchain issues surfaced only in CI.

- [ ] **Step 4: Log**

```bash
printf -- '- M6 Task9: CI build matrix green.\n' >> docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "docs: CI matrix green" && git push
```

### Task 10: Release workflow (publish all jars on tag)

**Files:** Create/Modify `.github/workflows/release.yml`.

- [ ] **Step 1: Write the release workflow**

```yaml
name: release
on:
  push:
    tags: ['v*']
jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: |
            8
            16
            17
            21
      - run: ./gradlew chiseledBuild --console=plain --stacktrace
      - name: Publish jars to the release
        uses: softprops/action-gh-release@v2
        with:
          files: '**/build/libs/*.jar'
```

- [ ] **Step 2: Test with a pre-release tag**

```bash
git tag v-test-multiversion && git push origin v-test-multiversion
gh run watch
```
Expected: a GitHub Release draft/publish with jars for every version×loader. Then delete the test tag/release:
```bash
gh release delete v-test-multiversion -y || true
git push origin --delete v-test-multiversion
```

- [ ] **Step 3: Commit and log**

```bash
git add .github/workflows/release.yml && git commit -m "ci: publish all version jars on release tag" && git push
printf -- '- M6 Task10: release workflow verified (all jars published).\n' >> docs/superpowers/plans/PROGRESS.md
git add docs/superpowers/plans/PROGRESS.md && git commit -m "docs: release workflow verified" && git push
```

---

## Self-Review Notes (author)

- **Spec coverage:** branch consolidation (M0), Stonecutter+unimined scaffold (M1), native-version fold-in 1.19.2–1.21.11 (M2–M4), legacy port 1.16.5–1.18.2 (M5), CI matrix + releases (M6), archive-tag safety, per-version loader matrix — all present.
- **Known non-concreteness (intentional):** Tasks 7 & 8 are recipes, not pre-written diffs — the ~thousands of conditional lines are discovered by diffing upstream at execution time; pre-writing them is impossible. One worked conditional example is given. The exact Stonecutter accessor for the active node's props is resolved by the M1 spike (Task 5) and recorded in PROGRESS.md before Tasks 6–8 rely on it.
- **Risk gates:** irreversible deletion (Task 4) is guarded by the pushed archive tag (Task 1) and a green build (Tasks 2–3); M5 has an explicit stop-and-consult (Task 8 Step 10).

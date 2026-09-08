# SP-3 Phase 1: loader subprojects as Stonecutter nodes

**Written 2026-09-08.** Design for removing SP-3's recorded blocker and carrying the result
through to a Nylium universal Baritone jar.

Read `docs/superpowers/HANDOFF.md` first. This spec assumes its "SP-3 blocker, and the spike that
answered it" section and does not repeat the spike findings.

## Problem

Nylium dispatches pre-remapped modules, so SP-3's required input is one already-built loader jar
per Minecraft version. Baritone cannot produce that in a single invocation, because the loader
subprojects bind to the ACTIVE Stonecutter version at configuration time in four places:

- `rootProject.active_loaders`, the self-skip guard at the top of each loader script
- `rootProject.fabric_version` / `forge_version` / `neoforge_version`
- the `commonNode` lookup keyed on `project(':common').stonecutter.current.version`
- unimined's Minecraft version, applied to loaders from root `allprojects {}`

Root `build.gradle` regex-parses `common/stonecutter.gradle` for the active version and loads that
node's `gradle.properties` into root `ext`. That mechanism exists only because loaders are not
Stonecutter nodes.

## Baseline

Measured 2026-09-08, before any change: `./gradlew help --offline` exits 0. All six projects
configure (four loaders plus both `:common` nodes), and both `STONECUTTER-PARAMS` lines fire with
1.21.11 active. Any configuration failure after this change is caused by this change.

## Decisions

| Decision | Choice | Rejected alternative and why |
| --- | --- | --- |
| Slice width | All four loaders become nodes at once | A Fabric-only slice leaves root's active-version mechanism alive in hybrid form, so it would have to be designed twice. |
| Per-version constants | Loader node reads `common/versions/<ver>/gradle.properties` from disk, keyed on its own version | Per-node `gradle.properties` under each loader duplicates the same constants four times per version (72 files at the full 18-target matrix), each a place to drift. Using `evaluationDependsOn` on the common node forces its full configuration, applying unimined and resolving mappings, even for a loader about to self-skip. |
| Shared loader config | `gradle/loader-conventions.gradle`, applied by each loader node | Keeping `allprojects {}` in root means root configures projects it no longer has version context for, and its skip list grows with every loader. A buildSrc convention plugin would add the groovy-gradle-plugin toolchain to a buildSrc that currently holds only plain Java tasks. |
| Done criterion | Through to a Nylium universal jar | Stopping at the build restructure defers the question the owner actually asked. |

## Design

### Tree shape

`settings.gradle` moves the loader include loop above the `stonecutter { }` block, because
`create()` requires the projects to exist, then registers all five projects against one shared
version set:

```groovy
include('common')
for (platform in available_loaders.split(",")) { include(platform) }

stonecutter {
    kotlinController = false
    shared { versions('1.21.11', '1.21.10'); vcsVersion = '1.21.11' }
    create(project(':common'), project(':fabric'), project(':forge'),
           project(':neoforge'), project(':tweaker'))
}
```

Verified against `stonecutter-0.7.11.jar` rather than assumed:

- `StonecutterSettingsExtension` declares both `create(Object[], Action)` and `create(Object...)`,
  so the varargs form is valid. The spike's failing form was three arguments in Groovy and binds to
  `create(Object, File, Action)` instead.
- `kotlinController` is a settable `Property<Boolean>`. Without it `create()` generates
  `fabric/stonecutter.gradle.kts`, which is what surprised the spike. Setting it false keeps every
  auto-generated controller on Groovy, matching `:common`.
- `StonecutterBuildImpl.getNode()` returns a `ProjectNode`, whose `getMetadata()` is a
  `StonecutterProject` carrying `getVersion()`. So a node reads its own version as
  `stonecutter.node.metadata.version`.

Result: `:fabric:1.21.10`, `:fabric:1.21.11`, `:forge:1.21.10` and so on coexist.
Each `<loader>/build.gradle` becomes the PER-NODE script and `<loader>/stonecutter.gradle` the
controller, which stays non-buildable, exactly as `:common` is arranged today.

`ProjectNode` also exposes `peer(String)` and `sibling(String)`, which may resolve the matching
`:common` node directly. Their semantics are unverified; treat them as a possible simplification to
confirm during implementation, not as the designed mechanism.

### Root becomes a pure aggregator

Deleted from root `build.gradle`: the active-version regex parse, the properties loading into
`rootProject.ext`, `rootProject.ext.active_loaders`, and the whole `allprojects {}` block. Root
keeps its license header and nothing else.

`available_loaders` stays in root `gradle.properties`, because `settings.gradle` still needs the
union at settings-evaluation time to include every loader subproject. It is no longer read as a
gate at configuration time.

### The conventions script

New `gradle/loader-conventions.gradle`, applied by each loader node as its first statement. It:

1. resolves its own version via `stonecutter.node.metadata.version`;
2. loads `common/versions/<ver>/gradle.properties` from disk, the single source of truth, keyed on
   this node's version rather than a global active one;
3. gates on that file's `available_loaders`, replacing the `rootProject.active_loaders` self-skip
   in all four loader scripts. `:neoforge:1.21.10` self-skips because 1.21.10 does not list
   neoforge; `:neoforge:1.21.11` builds;
4. applies java, unimined and maven-publish, the repositories, shared dependencies, toolchain and
   the compiler release setting, everything the deleted `allprojects` block did;
5. applies unimined IMMEDIATELY, never the lateApply overload, because a Stonecutter version node
   swallows unimined's deferred `afterEvaluate` and fails with "minecraft config never applied for
   source set 'main'";
6. wires the `:common` node of THE SAME version, not the active one. This is the specific coupling
   SP-3 was blocked on.

The four loader scripts are around 85 percent identical, so the conventions script also absorbs the
shared `configurations` block, the common-outputs bundling loop, `shadowJar`, `remapJar`, `jar`,
`proguard`, `createDist` and `publishing`. Each loader script then holds only what genuinely
differs: its loader-specific unimined block, its `archivesBaseName` suffix, its `processResources`
target and its manifest attributes. Four scripts of around 120 lines each become around 30 lines
each.

### Per-version loader metadata

`fabric/src/main/resources/fabric.mod.json` hardcodes Minecraft 1.21.11, and both
`forge/src/main/resources/META-INF/mods.toml` and
`neoforge/src/main/resources/META-INF/neoforge.mods.toml` hardcode the same version range.

Today that is invisible, because only one version builds per invocation. Once both nodes build,
the 1.21.10 Fabric node would ship a jar declaring it requires 1.21.11. Fix: add
`minecraft_version` to each loader's existing `processResources` expand and template the value,
keeping one shared resource file per loader rather than introducing a per-node overlay.

Out of scope and deliberately not fixed: `mods.toml` declares the mod id as `baritoe`, an upstream
typo. Changing a published mod id is the owner's call.

### The universal jar

New `:universal` subproject. It is a plain project, not a Stonecutter node, because there is
exactly one universal jar. It applies `io.github.intisy.nylium` and declares one module per
(loader, version) pair that actually produced a jar, each pointing at that node's `remapJar` output
through the `RegularFile` provider the Nylium DSL already accepts:

```groovy
module('fabric-1.21.11') {
    jar        = project(':fabric:1.21.11').tasks.named('remapJar').flatMap { it.archiveFile }
    platforms  = ['FABRIC']
    minecraft  = '1.21.11'
    mixins     = ['mixins.baritone.json']
}
```

No entrypoint is declared. Baritone's `fabric.mod.json` carries an empty entrypoints block and
works purely through mixins, and Nylium's `ManifestRenderer` null-checks that field. So this needs
no new Baritone entrypoint class.

Dedupe stays on, which is the default for two or more modules, and is where the measured 33.7
percent reduction comes from.

Prerequisite: Nylium is at `0.1.0-SNAPSHOT`, and mavenLocal currently holds only the pre-rename
`io.github.intisy.rutter` artifacts. The slice therefore starts by publishing Nylium to mavenLocal
under its new name and deleting the stale `rutter` tree, so a mis-resolution cannot hide behind a
working build.

## What this will and will not deliver

The build restructure covers all four loaders. The universal jar carries only modules for loaders
that actually produce a jar:

| Module | Expected | Why |
| --- | --- | --- |
| Fabric 1.21.10 and 1.21.11 | yes | The load-bearing pair. The same jar selecting a different module per version is what proves dispatch rather than mere loading. Fabric carries none of Nylium's four limitations. |
| Forge 1.21.10 and 1.21.11 | probably | Nylium unblocks Forge 1.17 and later. Unproven for Baritone specifically. |
| NeoForge 1.21.11 | no | Blocked by Nylium limitation 2 and SP-1b. 1.21.10 does not list neoforge at all. |
| tweaker, both versions | no | LaunchWrapper, blocked by Nylium limitation 4, which crashes the server after correct dispatch. Both version nodes list `tweaker` in `available_loaders` despite LaunchWrapper not being a real 1.21.x target; this is likely stale and should be investigated, not silently relied on. |

The delivered module set will be reported from the built artifact, not promised in advance.

## Acceptance

1. `./gradlew :common:1.21.10:build :common:1.21.11:build` is green. No regression on the one thing
   that works today.
2. A single `./gradlew build` produces loader jars for BOTH versions, for the loaders each version
   lists. This is SP-3's blocker measurably gone. Verified by listing the produced jars, never by
   exit code alone.
3. `./gradlew :universal:nyliumUniversalJar` produces one jar. Verified by unzipping it and reading
   the Nylium manifest for the expected module set, plus a deduped versus undeduped size comparison
   on Baritone's real output.

## Risks

- **unimined on a loader node is unproven.** The spike got as far as the "minecraft config never
  applied" error and stopped. The immediate-apply fix is known to work for `:common`, but `:common`
  turns runs off and disables the default remap jar, and the loaders do neither. If immediate apply
  is insufficient for a loader node, this is where the slice stalls.
- **Eight loader nodes configure where four did before.** Each applies unimined and resolves
  mappings, so configuration time roughly doubles, and any per-version mapping resolution failure
  that was previously latent becomes visible.
- **Folding the shared 85 percent into the conventions script is a refactor mixed into a
  structural change.** Mitigated by landing it as its own commit, after the tree shape change and
  before the universal jar, so a bisect can separate them.

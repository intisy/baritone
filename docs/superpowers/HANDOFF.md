# READ FIRST: where the multi-version work actually lives

**Written 2026-09-06.** This repo's 2026-07-13 spec and plan are **partly superseded**. Read this
before acting on them.

## The library that now carries the multi-version job

`F:\Documents\GitHub\intisy\minecraft\mods\Nylium`, branch `development`. Start at its
`docs/superpowers/HANDOFF.md`.

Nylium is a standalone library (own repo, own name, intended to be usable by mods other than
Baritone) that lets one jar boot on every mod loader from Minecraft 1.7 to 26.2. Its kernel is
complete and proven on five real servers across four loader bootstrap families. Baritone is
sub-project **SP-3** in Nylium's program overview: one Baritone jar for all versions and loaders,
with the fork's 8 custom features intact.

## What of the 2026-07-13 documents still stands

- **Superseded:** the packaging goal. That plan produces "the same per-version loader jars upstream
  ships today" (18 targets). The goal is now ONE universal jar, shadowing only the needed parts of
  Nylium. Phase M6's per-version release matrix goes with it.
- **Still valid, and still needed:** everything up to that point. The single-branch collapse, the
  Stonecutter version dimension over unimined, and above all the ports of 1.16.5, 1.17.1 and 1.18.2
  onto unimined+Mojmap. Nylium dispatches pre-remapped modules; it is **not** a runtime remapper, so
  per-version compiled modules remain exactly what the build must produce. That work is SP-3's input,
  not dead.

## How Nylium's known limits land on this repo's 18 targets

Nylium's kernel design spec now records **four** known limitations with bytecode evidence, not
three. Three of them bite specific Baritone targets:

- **1.16.5 Forge is blocked.** It is the only target in the ModLauncher 8 range (Forge 1.13 to
  1.16), where Nylium dispatches but cannot yet reach Minecraft classes. 1.16.5 Fabric and its
  launchwrapper tweaker are unaffected.
- **NeoForge is blocked on 10 targets** (1.20.4 and every 1.21.x) until Nylium SP-1b. NeoForge turned
  out to share no infrastructure with Forge: it ships zero ModLauncher classes and needs its own
  bootstrap.
- **LaunchWrapper is now blocked on every target in its range, Forge 1.7.10 through 1.12.2.**
  Found 2026-09-06, previously undocumented, and more serious than the other three: dispatch
  succeeds and the server then crashes. `NyliumBootTransformer` bootstraps Mixin from inside its own
  `transform()` call, and Mixin's own init registers a new transformer into the list LaunchWrapper's
  class loader is currently iterating, which throws `ConcurrentModificationException` on
  LaunchWrapper's own subsequent load of `net.minecraft.server.MinecraftServer`. This is independent
  of what a module does (reproduces with a module whose entrypoint only writes a marker file), and
  Nylium's own smoke harness structurally could not see it before now: it force-kills the server the
  instant a module's marker file appears, and the marker is written before this crash, so every
  LaunchWrapper smoke run in Nylium's history had been green over a server that goes on to die. This
  repo's earlier note above ("1.16.5 Fabric and its launchwrapper tweaker are unaffected") is now
  wrong for the launchwrapper case: LaunchWrapper is not a viable route to any Forge 1.7.10-1.12.2
  target until Nylium fixes this, which is its own spike, not yet started. See Nylium's kernel design
  spec and its content-addressed dedupe design spec for the full stack and reasoning.
- Everything else, Fabric and Forge 1.17+, is unblocked today.

So SP-3 can ship most of the matrix now and must not promise 1.16.5 Forge, any NeoForge jar, or any
Forge 1.7.10-1.12.2 (LaunchWrapper) jar until those Nylium items land.

## Per-version duplication: solved by Nylium, measured on this repo's own bytecode

**Nylium's SP-2b shipped content-addressed dedupe 2026-09-06** and it is done, not merely designed.
Nylium's Gradle plugin now deduplicates entries across a mod's module jars by default: every
distinct entry is stored once inside the universal jar, each module becomes a small index, and the
kernel rebuilds a real jar into its extraction cache on first launch. `nylium { dedupe = false }` is
an escape hatch back to whole, undeduped module jars. This does not by itself unblock SP-3 (see
below), but it is the fix for the duplication problem this handoff previously recorded as
"raised by the owner... and it is the next thing to fix" with no design chosen; a design is now
chosen, implemented and measured.

**Measured on this repo's own bytecode as part of Nylium's Task 10** (Nylium's
`docs/superpowers/sdd/2026-09-06-nylium-content-addressed-dedupe/task-10-report.md`, and the design
spec's "Measured result" section): both `:common:1.21.10` and `:common:1.21.11` were built for real
and their jars measured directly. Combined jar size 1,671,373 bytes (835,252 plus 836,121), 1,067
total entries (533 plus 534, including 66 directory entries per jar that never produce a blob). The
apples-to-apples entry-count ratio: 494 distinct blobs against 1,067 entries, meaning 46.3% of
entries are unique content and 53.7% collapse to a shared blob (52.8% unique when restricted to the
935 file entries, excluding directories). The raw object-store byte total (1,961,552 bytes,
uncompressed) came out *larger* than the two compressed jars combined; that is an artifact of
comparing uncompressed blob storage to zip-deflated jars, not a sign dedupe does not work, since a
real universal jar re-compresses the deduped blobs the same way (the conformance mod's own jar
measurement, 24.8% smaller deduped versus undeduped, both compressed identically, is the fair
comparison). **Caveat carried from the original measurement below: 1.21.10 and 1.21.11 are adjacent
versions, so this ratio is a best case; a distant pair such as 1.16.5 against 1.21.11 would show
substantially less duplicate content and a correspondingly smaller win.**

**SP-3's own blocker is unchanged by any of this.** Dedupe fixes what happens to duplicate bytecode
once Baritone can produce one pre-remapped module jar per Minecraft version per invocation; it does
not address the reason Baritone cannot do that yet, which is that loaders are not Stonecutter
nodes. See "SP-3 blocker, and the spike that answered it" below; that spike and its remaining design
work stand exactly as recorded.

**The constant-folding trap found in Nylium's conformance mod applies directly to this repo's own
shared-source-plus-Stonecutter-overlay layout.** A shared class that reads a per-version
`public static final` constant from a per-version overlay class gets that constant inlined by
`javac` at the shared class's own compile time (JLS 4.12.4), not resolved per node at runtime. In
Nylium's conformance mod this meant a shared entrypoint compiled once against an identity stub
silently baked the stub's value into every module, even though the stub was never packaged; "the
stub class is never shipped" was true and did not prevent the leak, because it is the constant's
*value*, not the stub's class file, that leaks. This repo's `common` source set is exactly this
shape: shared source compiled once per Stonecutter node, with per-node overlay files (see
`IRenderer`'s convergence work above) providing the pieces that differ. Any future shared class in
`common` that reads a `public static final` field from a per-version overlay class is exposed to
this same trap; the fix, proven in the conformance mod, is to expose such per-version values through
methods, never through constants, since a method call resolves against whichever class the node
actually compiled against and cannot be folded.

## State of the Stonecutter version dimension

**Both version nodes compile as of 2026-09-06.** `./gradlew :common:1.21.10:build` and
`:common:1.21.11:build` are each green. Two pieces got them there.

**1. `common/stonecutter.gradle` carries a `stonecutter.parameters {}` block** with six per-version
source replacements porting the 1.21.11-authored shared source down to 1.21.10 mappings (Identifier
to ResourceLocation, ResourceKey.identifier() to location(), camera.position() to getPosition(), the
Util and monster-class package moves). The version gate is correct: the block evaluates once per
node and reports `pre1_21_11=true` for 1.21.10 and `false` for 1.21.11, so 1.21.11 is untouched.

Note that **Stonecutter generates five source sets here** (`api`, `launch`, `main`,
`schematica_api`, `test`). The `camera.position()` replacement only ever appears in `launch`.
Grepping the generated `main` tree alone makes a working replacement look dead.

**2. The 1.21.10 `IRenderer` overlay was converged on 1.21.11's signature set.** This could not be
done with a source replacement, and the reason is worth keeping:

- 1.21.11 carries line width as a **per-vertex attribute**
  (`DefaultVertexFormat.POSITION_COLOR_NORMAL_LINE_WIDTH` plus `setLineWidth` per vertex), so width
  is passed at emit time. 1.21.10 has no such attribute and sets width as **global GL state** via
  `RenderSystem.lineWidth`, read at draw time. The arities differ, so no textual rewrite bridges
  them.
- Worse, `startLines(Color, float)` **already existed in both and meant different things**: alpha on
  1.21.11, line width on 1.21.10. Both compile. The shared source calls it with opacity
  (`SelCommand`, `SelectionRenderer`) while 1.21.10's own `PathRenderer` called it with a width, so
  the same signature had two meanings in one compilation unit. Adding overloads cannot fix that.

The fix converges 1.21.10's public shape on 1.21.11's: `startLines(Color, float)` now means alpha,
`startLines(Color)` was added, and the width-taking `emitLine`/`emitAABB` overloads route through a
named `applyLineWidth` helper whose `@implNote` records that width is per-batch on this version.
1.21.10's `PathRenderer` moved to the explicit 3-arg `startLines(color, .4f, width)`, preserving its
previous alpha exactly.

**Every call site uses a single line width per batch**, which is what makes the global-state
approach equivalent to 1.21.11's per-vertex one. Check that invariant still holds before adding a
batch that mixes widths on 1.21.10: it would silently render every line at the last width set.

## SP-3 blocker, and the spike that answered it

**Spiked 2026-09-06. Throwaway edits reverted; the tree is clean and both nodes still build.**

Nylium dispatches **pre-remapped** modules, so SP-3's required input is one already-built loader jar
per Minecraft version. Baritone cannot currently produce that in a single invocation.

**Why.** Per-node *common* jars are fine: `:common:1.21.10:build` works while `1.21.11` is active.
But the loader subprojects bind to the ACTIVE version at configuration time in four places, so one
invocation yields one version's loader jars:

- `rootProject.active_loaders` (the self-skip guard at the top of each loader script)
- `rootProject.fabric_version` / `forge_version` / `neoforge_version`
- `def commonNode = project(":common:${project(':common').stonecutter.current.version}")`
- unimined's Minecraft version, applied to loaders from root `allprojects {}`

Root `build.gradle` even regex-parses `common/stonecutter.gradle` for `active(...)` and loads that
node's `gradle.properties` into root `ext`. That whole mechanism exists **only** because loaders are
not Stonecutter nodes, and making them nodes removes the need for it.

**The fix is to make each loader a Stonecutter-versioned project**, so `:fabric:1.21.10` and
`:fabric:1.21.11` coexist and each reads its own node `gradle.properties`. Four things the spike
established, so nobody has to rediscover them:

1. `stonecutter { create(project(':common'), project(':fabric')) { versions(...) } }` is **not**
   valid and fails settings evaluation with `No versions have been registered`. The multi-project
   form is a `shared { versions(...); vcsVersion = ... }` block followed by one bare
   `create(project(':x'))` per project. That form evaluates successfully.
2. Loader `include(...)` calls must move **above** the `stonecutter { }` block, since `create()`
   needs the project to exist.
3. `create()` **auto-generates the controller script** (it wrote `fabric/stonecutter.gradle.kts`
   containing `stonecutter active "1.21.11"`). Expect it; do not hand-write it. As with `:common`,
   the controller takes `stonecutter.gradle` and `fabric/build.gradle` becomes the PER-NODE script.
4. The next failure after that is `minecraft config never applied for source set 'main'` on
   `:fabric`. This is the gotcha already documented at the top of `common/build.gradle`: a
   Stonecutter version node swallows unimined's deferred `afterEvaluate`, so unimined must be
   applied **immediately** as `unimined.minecraft(sourceSets.main) { }`, never the lateApply
   overload. Each loader script needs that change.

Remaining design work, which is why this stopped at the spike rather than landing half of it: each
`:fabric:<version>` node must depend on `:common:<the same version>` instead of the active one, and
the per-node `available_loaders` subset has to replace the current `active_loaders` self-skip guard
now that "active" stops being a global. Root `build.gradle`'s active-version parsing should then be
deleted rather than adapted.

**Recommended first slice once that lands:** Fabric only, 1.21.10 plus 1.21.11. Both nodes already
compile, Fabric carries none of Nylium's three limitations, and a two-version Fabric pair is exactly
the discrimination case Nylium's own smoke matrix uses to prove dispatch rather than mere loading.
It also gives Nylium the second real consumer its handoff wants before retiring the testmod's
hand-rolled `universalJar`.

## Branch model, and what must NOT be deleted yet

**Adopted 2026-09-06.** This fork now follows the global two-branch rule: `main` (the default
branch) and `development`, both currently at the same commit, with feature branches off
`development` for anything else. The old milestone branch `m2-mc1.21.10` was renamed to
`development`. `main` is the Nylium-based single-jar line, not a legacy per-version line.

`origin` is `intisy/baritone`. `upstream` is `cabaletta/baritone` and must never be pushed to.
Note that the local `restructure-master` branch tracks **upstream**, so a careless `git push` on
it aims at the wrong repository.

**The remaining per-version branches are scheduled for deletion, but deleting them now would
destroy work that has not been folded in yet.** `origin` carries 20 per-version branches
(`1.13.2` through `1.21.10`) while `development` carries only two Stonecutter nodes, `1.21.10` and
`1.21.11`. Measured, not assumed:

| Branch | Java files | Ancestor of `development`? | Safe to delete? |
| --- | --- | --- | --- |
| `1.21.10` | 363 | yes | **deleted 2026-09-06** |
| `1.21.4` | 360 | no | **NO** |
| `1.16.5` | 340 | no | **NO** |
| `1.17.1` | 316 | no | **NO** |
| `1.18.2` | 334 | no | **NO** |
| the other 14 | not yet measured | not checked | **NO** |

**The only sound test is `git merge-base --is-ancestor origin/<branch> development`.** `1.21.4` was
briefly and wrongly marked safe here on the grounds that its four unpushed local commits were
docs-only with byte-identical blobs. That was a conflation: those four commits are redundant, but
the branch itself still carries 360 Java files of 1.21.4 source that exists nowhere else. Judge the
branch, never the commits sitting on top of it.

`git merge-base --is-ancestor origin/1.16.5 development` returns false, and that branch holds its
own `baritone/utils/IRenderer.java` and `PathRenderer.java`. Those per-version overlays are exactly
what the 1.21.10 port needed, and they are the input for every version still to be folded in. The
2026-07-13 plan's requirement to port 1.16.5, 1.17.1 and 1.18.2 onto unimined+Mojmap is still live.

**So: delete a version branch only once its version exists as a Stonecutter node under
`common/versions/`, and check `--is-ancestor` first.** Deleting them as a batch before the collapse
finishes would leave 18 targets with no source to fold.

## Known rule violation, not yet fixed

`development` still carries a hand-written `README.md` inherited from upstream. The global rule is
that READMEs are generated onto the default branch only, and a development branch carries the
generator's template instead. Migrating means adding `CONTENT.md` plus `.github/docs-config.yml`
and dropping `README.md` from `development`, the same shape Nylium uses. Left alone here because it
removes upstream's README, which is the owner's call.

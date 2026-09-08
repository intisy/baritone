# READ FIRST: where the multi-version work actually lives

**Written 2026-09-06, substantially updated 2026-09-08.** This repo's 2026-07-13 spec and plan are
**partly superseded**. Read this before acting on them.

**Start here if you are new:** SP-3's blocker was removed on 2026-09-08. One `./gradlew build` now
produces a remapped loader jar per Minecraft version, and `:universal` assembles them into a Nylium
universal jar. Jump to "SP-3 blocker: REMOVED 2026-09-08" for what exists and what is still open.
**The jar has now been booted**, on three servers and on a real Fabric 1.21.10 client, verified
2026-09-08 evening. The client run found a blocker and it was fixed the same day: Fabric jar-in-jar
did not survive Nylium's dispatch, so Baritone's `nether-pathfinder` was unreachable and the client
crashed during startup. Nylium's kernel now extracts a module's nested jars, and the same client
reaches the main menu and stays up. See "The Fabric modules crashed the client" for the mechanism
and the verification, and "The universal jar has now been booted" for the server runs.

**The largest remaining item is no longer about booting.** It is folding the other versions in:
`development` carries four Stonecutter nodes against `origin`'s 20 per-version branches, and the
2026-07-13 requirement to port 1.16.5, 1.17.1 and 1.18.2 onto unimined+Mojmap is still live, though
it is no longer a precondition for deleting those branches: see the retraction under "Branch model".

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
comparison).

**The headline figure, the one that directly answers "how much smaller is the jar": 33.7%
smaller, measured on this repo's own two node jars.** A throwaway two-module consumer project
(deleted after measuring, built under a system temp directory, never committed) pointed the
published Nylium plugin straight at Baritone's two built `common` node jars and built the same
`nylium { }` declaration twice, once with `dedupe = false` and once with dedupe on, both producing
a real zip-compressed universal jar the same way. Undeduped: 1,594,345 bytes. Deduped: 1,057,001
bytes, carrying the same 494 distinct blobs measured above. Difference: 537,344 bytes, 33.7%
smaller. Both jars are compressed identically, so unlike the raw object-store number above, this
comparison is apples to apples, and it is the number that directly answers the duplication question
the owner asked. **Caveat carried from the original measurement: 1.21.10 and 1.21.11 are adjacent
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

**Three version nodes as of 2026-09-08 evening: 1.21.11, 1.21.10 and 1.21.8.** All three
`:common:<version>:build` invocations are green, as are `:fabric:1.21.8:build` and
`:forge:1.21.8:build`, and the universal jar now spans all three in six modules. The 1.21.8 fold-in
is written up in "Folding in 1.21.8, and the recipe that actually works" below; the two pieces that
got 1.21.10 working are still the mechanism, so read this section first.

**1. `common/stonecutter.gradle` carries a `stonecutter.parameters {}` block** with six per-version
source replacements porting the 1.21.11-authored shared source down to 1.21.10 mappings (Identifier
to ResourceLocation, ResourceKey.identifier() to location(), camera.position() to getPosition(), the
Util and monster-class package moves). The version gate is correct: the block evaluates once per
node and reports `pre1_21_11=true` for 1.21.10 and `false` for 1.21.11, so 1.21.11 is untouched.
**All six also apply to 1.21.8**, which is correct since each is a rename 1.21.11 introduced, and
compilation on 1.21.8 is the proof.

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

## Folding in 1.21.8, and the recipe that actually works

**Done 2026-09-08 evening.** This is the first version folded in since the two-node state, so treat
it as the worked example for the rest of the matrix rather than the 2026-07-13 plan's Task 7, whose
Step 4 proposes Stonecutter `//? if` conditionals in the shared source. Nothing here uses those. The
mechanism is source replacements plus per-node overlays, and it worked without touching one line of
shared source.

**The delta is the authoritative work list.** `git diff upstream/1.21.10 upstream/1.21.8 -- '*.java'`
is 9 files, 49 insertions and 30 deletions. That is far smaller than the 37-file
1.21.11-to-1.21.10 diff, so a version that looks distant by number can be cheap. **Measure before
estimating.**

Split the 9 by shape, which is the judgement the recipe needs:

- **13 string replacements** in a new `isPre1_21_10` block for the 6 files whose divergence is a
  rename or a signature shuffle: the `ServerLevelStub` constructor gaining a `ChunkProgressListener`,
  the mixin target descriptor form (`Lowner;method` against `owner.method`), `Minecraft.setLevel`
  carrying a `ReceivingLevelScreen.Reason`, `renderLevel` taking one fewer `Matrix4f`,
  `Palette.write` taking the block-state registry, and `Palette` lacking `maybeHas` and the
  resize-hint `idFor` overload.
- **4 per-node overlay files** under `common/versions/1.21.8/src` for the renderer, where the
  divergence is structural. Two are verbatim copies of the 1.21.10 overlay
  (`mixins.baritone.json`, which is byte-identical between upstream 1.21.10 and 1.21.8, and
  `IRenderer`, which does not appear in the delta at all), and two are authored: `BaritoneRenderType`
  drops the `pipeline()` override and uses `RenderSystem.getModelOffset()`, and `PathRenderer`
  restores the working `BeaconRenderer.renderBeaconBeam` call that 1.21.10 has commented out.

Note the overlay cost: a file that is identical on 1.21.8 and 1.21.10 but differs on 1.21.11 has to
be **duplicated** into both node directories, because an overlay is per node with no way to share
one between some nodes. `IRenderer` is now three near-identical copies. That is the standing tax of
this design and it grows with the matrix.

**The replacements stack, and that is the load-bearing trick.** The shared source is authored for
1.21.11; the `<1.21.11` block ports it to 1.21.10; the new `<1.21.10` block carries it the rest of
the way to 1.21.8. Verified by the gate's own output, which prints
`pre1_21_11=true pre1_21_10=true` for 1.21.8 and `pre1_21_10=false` for both older nodes, so
neither existing node is touched. `:common:1.21.10:build` and `:common:1.21.11:build` were re-run
and stayed green.

**Let the compiler adjudicate; do not reason it out.** Two of the nine were wrong on first pass and
six errors named both: `PaletteResize` is package-private before 1.21.10, so its import had to be
replaced out rather than merely left unused, and `GuiClick` had been read in the delta and then not
encoded at all. Both are the sort of thing that is cheaper to compile than to argue about.

### The measured payoff of a third version

Deduped universal jar: 4,284,645 bytes over 6 modules, 1092 object-store blobs, against 3,993,028
bytes over 4 modules for two versions. So 1.21.8's two loader jars, **3,620,565 bytes raw**, added
**291,617 bytes**, about 8 percent of their own size. Approximate, since the two jars were built at
different commits and the version string differs in length, but not by anything near that margin.

This is the answer to the adjacency caveat recorded further down: it predicted a distant version
pair would dedupe far worse. Across 1.21.8 to 1.21.11 that has not happened, because Baritone's own
bytecode barely moves between these Minecraft versions. Do not read it as settled for a genuinely
distant target; 1.16.5 is a different proposition.

### 1.21.5 is folded in too, 2026-09-08

`:common:1.21.5`, `:fabric:1.21.5` and `:forge:1.21.5` are green, all four earlier version nodes
were re-checked and stayed green, and the universal jar carries **eight modules over four
versions**. The analysis this section originally recorded is below and held up, except that
`MixinWorldRenderer` needed no overlay after all.

**Three traps this one produced, all worth knowing before folding the next version:**

1. **Stonecutter rejects a replacement it cannot reverse.** `'if (...) {' -> '{'` fails outright
   with `Replacement ... is irreversible`, and so does replacing anything with an empty string,
   because it has to undo replacements when switching the active node. Every replacement target has
   to be uniquely invertible, which also means two replacements must not converge on the same text:
   the two `sendPacket` signatures had to keep their distinct parameter names for that reason.
2. **A multi-line replacement source silently matches nothing.** The working tree is CRLF and a
   Groovy `'''...'''` literal is LF, so the source never matches. One such replacement failed
   loudly as a compile error and a second failed **silently**, leaving a `renderBackground` override
   in place that upstream does not have. Worse, anchoring on CRLF would break on a Linux checkout
   where the same files are LF. **Never use a multi-line replacement source.** Multi-line
   *targets* are fine. Where a one-line anchor did not exist, the fix was to make one: the shared
   `MixinScreen` parameter was renamed `ci` to `callback` so `callback.cancel();` is unique
   (`ci.cancel();` appears in two other mixins), and `MATRICES_FOG_SNIPPET`'s `@Final @Shadow` was
   folded onto its declaration line.
3. **A gate that is cumulative for renames is wrong for signatures.** `renderLevel`'s parameter list
   changes on nearly every version, so a `<1.21.10` and a `<1.21.8` block would both fire on 1.21.5
   and the second would have to match the first's output. It is now range-exclusive
   (`isPre1_21_10 && !isPre1_21_8`), so each range rewrites the shared signature exactly once. One-way
   renames stay cumulative.

**A mixin that compiles is not a mixin that applies.** `MixinRenderPipelines` shadows
`MATRICES_FOG_SNIPPET`, which does not exist before 1.21.8. It compiles anyway, because a `@Shadow`
is only a declaration, and the build said so once in a line easy to scroll past:
`[WARN] Could not find target field for @Shadow MATRICES_FOG_SNIPPET`. At runtime that is a mixin
apply failure, not a warning. The field could not simply be dropped from the shared source either:
its only reader is **1.21.11's** `IRenderer` overlay, for the beacon-beam pipelines. So a
`<1.21.8` replacement turns the shadow into a plain added field, whose null nothing on those
versions observes. **Grep loader build output for `Could not find target` after every fold.**

### The duplicate blob that costs 982 KB

1.21.5's marginal cost is **1,133,564 bytes**, 31 percent of its two module jars' 3,618,903 raw
bytes, against 1.21.8's 8 percent. But it added only **37 new blobs**, which does not square with
a megabyte, and the reason is a real defect rather than distance:

| Blob | Size | Referenced by |
| --- | --- | --- |
| `5bf06c2406b80c86...` | 982,181 | fabric 1.21.8, 1.21.10, 1.21.11 |
| `4cda0d7cbe9769af...` | 982,181 | fabric **1.21.5** only |
| `2c26396b165e57fb...` | 941,296 | all four forge modules |

The first two are the same `META-INF/jars/nether-pathfinder-1.4.1.jar`, the same library at the
same version and **the same byte count**, stored twice because the two re-zips differ in framing,
not content. So content-addressed dedupe misses on the single largest artifact in the jar. Those
three blobs are 2.9 MB of a 5.4 MB jar.

**The cause is nailed down, and it is not the loader version.** Both nested jars are 982,181 bytes
with identical entry listings, and the first differing byte is at 977,140, inside the local file
header of the `fabric.mod.json` entry *within* the nested jar:

```
1.21.5 : 14 00 08 08 08 00 00 b8 3f 00   ->  DOS 1980-01-31 23:00
1.21.8 : 14 00 08 08 08 00 00 00 41 00   ->  DOS 1980-02-01 00:00
```

That is the same normalised instant written one hour apart, a timezone artifact in whatever re-zips
that entry, not wall-clock drift: the three matching modules were built hours apart on the same day
and still agree. My first guess, that `fabric_version=0.16.10` against `0.16.14` was responsible,
is **wrong** and worth recording as wrong so nobody bumps a loader version expecting a megabyte
back.

Not fixed. The fix is to make the `include` path write a fixed timestamp, and it is a
build-determinism task rather than part of a fold; note that `preserveFileTimestamps = false` on the
node's own `jar` task will not reach an entry inside a nested jar. **Roughly 1 MB is recoverable**,
and it will recur for any version whose nested jar is re-zipped on the other side of that boundary.

### What the rest of the matrix costs, measured

Fold cost is wildly uneven, so pick the order from this table rather than counting version numbers.
Each row is `git diff --shortstat upstream/<from> upstream/<to> -- '*.java'`:

| Step | Java files | Note |
| --- | --- | --- |
| 1.21.5 to 1.21.4 | 31 | the render overhaul boundary, the expensive one |
| 1.21.4 to 1.21.3 | **3** | nearly free once 1.21.4 exists |
| 1.21.3 to 1.21.1 | 24 | |
| 1.21.1 to 1.21 | 68 | |
| 1.21 to 1.20.5 | 81 | largest measured so far |
| 1.20.5 to 1.20.4 | 13 | |

**This corrects the 2026-07-13 plan's order, which skips 1.21.4 entirely** and goes
1.21.5 to 1.21.3. Do 1.21.4 next instead: it crosses the render overhaul once, and 1.21.3 then costs
3 files instead of a second crossing. Going straight to 1.21.3 pays the 31-file cliff and leaves
1.21.4 still owing it.

The cliff is where Minecraft replaced the immediate-mode renderer with the `RenderPipeline` system,
which is exactly the area this repo already carries four per-node `IRenderer` copies for. Expect the
overlay set to change shape there rather than just grow, and budget for it as its own unit of work.

### The 1.21.5 analysis, as recorded before doing it

The measuring below was done first; it is kept because it held up.
`git diff upstream/1.21.8 upstream/1.21.5 -- '*.java'` is 8 files, 55 insertions and 75 deletions.
It is more work than 1.21.8 despite being smaller, because more of it is structural:

| File | Shape | How |
| --- | --- | --- |
| `MixinNetworkManager` | `ChannelFutureListener` becomes `PacketSendListener` | 3 replacements |
| `PathingBehavior`, `CustomGoalProcess`, `ElytraProcess` | the `instanceof ClientLevel` disconnect block collapses to `ctx.world().disconnect()` | 1 block replacement, same text in all three |
| `GuiClick` | the `renderBackground` override does not exist | 1 block replacement, removing it |
| `MixinScreen` | different target method, injection point, signature and body | overlay |
| `MixinWorldRenderer` | `onStartHand` gains `GameRenderer`, loses `GpuBufferSlice` and `Vector4f` | overlay |
| `BaritoneRenderType` | 77 lines: `getRenderPipeline()`, `GpuTexture`, no `ScissorState` | overlay |

`MixinWorldRenderer` is an overlay rather than a replacement on purpose: 1.21.8 already rewrites
that signature, and a second replacement would have to match the first one's output, which couples
two gates to each other's text.

**Three of 1.21.8's four overlays can be copied verbatim**: `IRenderer`, `PathRenderer` and
`mixins.baritone.json` are all byte-identical between upstream 1.21.8 and 1.21.5. Only
`BaritoneRenderType` has to be authored. Note this makes `IRenderer` a fourth copy of the same file.

Keep `settings.gradle` un-updated until the node builds, or a half-finished fold leaves the whole
tree unable to configure.

### The blocker this hit, and the change it forced

**parchmentmc is still down** (measured: `https://maven.parchmentmc.org/` returns nothing, HTTP 000,
while GitHub returns 200), and the Gradle cache here holds parchment only for 1.21.10 and 1.21.11.
`parchment(...)` was mandatory in both `common/build.gradle` and `gradle/loader-conventions.gradle`,
so a new node could not resolve mappings at all.

It is now **optional per node**: declare no `parchment_version` and the node builds on
intermediary plus mojmap, which is what `common/versions/1.21.8/gradle.properties` does. mojmap
already supplies every name the source compiles against; parchment only adds parameter names and
javadoc. 1.21.10 and 1.21.11 still declare theirs and are unchanged.

**A consequence worth knowing before trusting CI:** those two nodes still require parchment, and a
fresh runner has no cache, so **this repo's CI is red for an external reason** until parchmentmc
returns. Dropping parchment from them would change their mappings and is the owner's call.

### Defect found, not fixed: `dist/` collides across version nodes

`CreateDistTask` copies each artifact into a flat `dist/` under the artifact's own file name, which
carries the loader and the mod version but **not the Minecraft version**. With three version nodes
per loader, `:fabric:1.21.8:createDist` and `:fabric:1.21.10:createDist` write the same path, so
after a whole-tree build `dist/` holds one arbitrary version per loader and `checksums.txt` is
computed over whatever survived. Latent since loaders became Stonecutter nodes, and invisible while
only one version was ever active.

Left as is on the owner's decision of 2026-09-08: the universal jar is the deliverable and the
per-version release matrix is superseded, so `dist/` is legacy. Fixing it means changing published
artifact file names.

## SP-3 blocker: REMOVED 2026-09-08

**Loaders are now Stonecutter dimensions and one invocation builds every version.** This section
previously described the blocker and the spike that answered it; both are history. See
`docs/superpowers/specs/2026-09-08-loader-stonecutter-nodes-design.md` for the design and
`docs/superpowers/plans/2026-09-08-loader-stonecutter-nodes.md` for the executed plan, whose
"Deviations found while executing Task 3" section is the part worth reading.

### What one `./gradlew build` now produces

Measured when this was written, at two versions and nine nodes. **1.21.8 has since been folded in**,
so the tree is now nineteen nodes; the counts below were not re-measured at four versions, and
`:common:1.21.8`, `:fabric:1.21.8` and `:forge:1.21.8` were each built individually rather than as
one invocation.

| Project | Nodes |
| --- | --- |
| `:common` | 1.21.5, 1.21.8, 1.21.10, 1.21.11 |
| `:fabric` | 1.21.5, 1.21.8, 1.21.10, 1.21.11 |
| `:forge` | 1.21.5, 1.21.8, 1.21.10, 1.21.11 |
| `:neoforge` | 1.21.5, 1.21.8, 1.21.11 |
| `:tweaker` | 1.21.5, 1.21.8, 1.21.10, 1.21.11 |

At two versions that was seven remapped loader jars and 42 in total counting the api, dev,
unoptimized and standalone variants. **All four of 1.21.8's declared loaders build**: `:fabric`,
`:forge`, `:neoforge` and `:tweaker` were each run individually and are green, so the new version is
folded in across every loader it declares, not only the two the universal jar ships. Each node's jar declares its OWN Minecraft version: `:fabric:1.21.10`'s `fabric.mod.json`
says `"minecraft": ["1.21.10"]`, which before this work was hardcoded to 1.21.11 in a single shared
resource and would have shipped wrong the moment two versions built together.

### The shape

- `settings.gradle` registers `:common` over every version, and **each loader over only the versions
  whose `available_loaders` declares it**. So `:neoforge:1.21.10` does not exist at all.
- Root `build.gradle` is a pure aggregator: 151 lines deleted, including the `active(...)` regex
  parse, the properties load into `rootProject.ext`, `active_loaders`, and the whole `allprojects {}`
  block.
- `gradle/loader-conventions.gradle` carries everything the four loader scripts shared. They are now
  33 to 58 lines each, 16 of which is the license header, and hold only their unimined block,
  `ext.metadataFile`, `ext.mixinManifest` and their own extra dependencies.
- `gradle/mod-version.gradle` carries the `git describe` version logic, shared by the loader
  conventions and `:universal`.
- Per-version constants still live in exactly one place, `common/versions/<ver>/gradle.properties`.
  A loader node reads the file keyed on its own version. No per-loader duplicate of it exists.

### The universal jar exists

`:universal` applies `io.github.intisy.nylium` and produces
`universal/build/distributions/baritone-<version>-universal.jar`, carrying six modules:

| Module | Platform | Minecraft |
| --- | --- | --- |
| `baritone-fabric-1.21.11` | `FABRIC` | 1.21.11 |
| `baritone-fabric-1.21.10` | `FABRIC` | 1.21.10 |
| `baritone-fabric-1.21.8` | `FABRIC` | 1.21.8 |
| `baritone-forge-1.21.11` | `MODLAUNCHER_9` | 1.21.11 |
| `baritone-forge-1.21.10` | `MODLAUNCHER_9` | 1.21.10 |
| `baritone-forge-1.21.8` | `MODLAUNCHER_9` | 1.21.8 |

Note **Forge 1.21.x is `MODLAUNCHER_9`, not a "FORGE" platform**; Nylium's `PlatformId` enum is
`LAUNCHWRAPPER, MODLAUNCHER_8, MODLAUNCHER_9, NEOFORGE, FABRIC`, keyed on the bootstrap family
rather than the loader brand.

No `entrypoint` is declared. Baritone's `fabric.mod.json` carries an empty entrypoints block and
works purely through mixins, and Nylium's `ManifestRenderer` null-checks the field, so **no new
Baritone entrypoint class was needed**.

**Dedupe measured on Baritone's own four-module jar: 43.3 percent smaller.** Undeduped 7,039,630
bytes, deduped 3,991,203 bytes, saving 3,048,427. Both zip-compressed identically, so this is the
apples-to-apples number. It beats the 33.7 percent recorded earlier in this file because that
measured two `common` node jars while this measures four whole loader jars, which share more.
The adjacency caveat still stands: 1.21.10 and 1.21.11 are neighbours, so a distant pair would
show less.

### What the universal jar deliberately omits

`:neoforge` and `:tweaker` build, and are deliberately NOT modules:

- **NeoForge** needs a bootstrap Nylium does not have (its SP-1b). Shipping the module would ship
  something that cannot dispatch.
- **tweaker** is LaunchWrapper, Nylium's limitation 4, which dispatches correctly and then crashes
  the server.

**`tweaker` in `available_loaders` is NOT stale; that earlier note was wrong and is retracted.**
This file previously said both version nodes list `tweaker` even though "LaunchWrapper is not a real
1.21.x target", and called it stale. That conflated two different LaunchWrapper uses. Baritone's
`:tweaker` is not the Forge 1.7.10-1.12.2 bootstrap family at all: it is the **vanilla-client
standalone** target, injected with `net.minecraft.launchwrapper.Launch --tweakClass
baritone.launch.tweaker.BaritoneTweaker` over OptiFine's `net.minecraft:launchwrapper:of-2.3` plus
ImpactDevelopment's `SimpleTweaker`, which is exactly why it is the one loader published unsuffixed
(`ext.distClassifier = null`). Vanilla-client injection is version-independent, so listing it for
1.21.x is correct and both nodes should keep it.

Excluding the tweaker module from the universal jar still stands, but for the other reason: Nylium's
LaunchWrapper *backend* is broken (its limitation 4), and that is a property of the backend, not of
the target's legitimacy. The mechanism, `MixinBootstrap.init()` mutating the transformer list
`LaunchClassLoader.runTransformers` is iterating, lives in `LaunchClassLoader`, which OptiFine's
`of-2.3` shares with Forge 1.7.10's, so a vanilla-client launch is expected to hit it too. Nobody
has measured that, and it is not worth measuring until Nylium's LaunchWrapper spike lands.

### Traps this work produced

- **A loader node's `plugins { shadow }` block defeats any configuration-time loader gate.** Shadow
  applies the java plugin, so a node that "skips" itself still compiles loader source against a
  classpath with no loader on it. This is exactly how `:neoforge:1.21.10:compileJava` failed. Gate
  structurally in `settings.gradle` by not creating the node, never at configuration time.
- **`ext.loaderBlock` must be set BEFORE `apply from:`**, and must take the loader version as a
  closure parameter. Inside `unimined.minecraft { }` the delegate is unimined's config, not the
  project, so `ext.anything` read in there resolves against the wrong object.
- **`ProguardTask` reads `getProject().findProperty("java_version")`.** That used to resolve through
  root's `ext` and is null on a node, so the conventions script sets `ext.java_version`.
- **parchmentmc is a latent build-stopper, now fixed.** `maven.parchmentmc.net` and
  `maven.parchmentmc.org` (same IP) were unreachable on 2026-09-08, and Gradle probes every declared
  repository on a cache miss, so an unrelated miss on the synthesized
  `net.minecraft:minecraft_fabric_1.21.10` coordinate timed out and failed resolution outright.
  `gradle/mc-repositories.gradle` now holds the one repository list, scoping any parchmentmc
  repository to `org.parchmentmc.data` as it is added, which catches the one unimined adds itself.
  Both `common/build.gradle` and `gradle/loader-conventions.gradle` apply it, and it must be applied
  BEFORE unimined or the hook misses unimined's own repository. Verified from a wiped `common`.
- The Stonecutter `create()` finding in the old spike was over-generalised. The MULTI-project block
  form does fail, but the single-project `create(Object, Action)` overload works fine and is what
  every loader now uses, so no `shared { }` block is needed.
- `kotlinController = false` is required, or `create()` writes `.gradle.kts` controllers.

### Configuration memory roughly doubled, and it will not scale as-is

The tree went from 4 unimined applications to 8, and unimined configures Minecraft eagerly per
node, so a plain `./gradlew build` now configures 8 loader nodes plus 2 common nodes in one pass.
On 2026-09-08 that was enough to have the OS kill three separate build attempts on a 64 GB machine
sitting at 85 GB commit charge with other applications loaded. It died during CONFIGURATION, before
any compilation.

`--configure-on-demand` is the mitigation and it works: `./gradlew :fabric:1.21.11:assemble
--configure-on-demand` completes in about two minutes where the full build could not start.

**This matters more as the matrix grows.** At the full 18 targets it is up to 4 times 18 unimined
applications in a single configuration pass.

**`org.gradle.configureondemand=true` is now set in `gradle.properties`**, on the owner's decision
of 2026-09-08, so no invocation needs the flag any more. Verified after setting it:
`./gradlew :fabric:1.21.11:assemble` with no flag is green in 1m13s. The consequence to remember is
that a task path now configures only the projects it needs, so a whole-tree invocation is no longer
the default behaviour anything is tested under.

### How the conventions refactor was verified

A full from-clean rebuild, run per node rather than as one invocation, because a single whole-build
invocation does not fit in this machine's memory (see above).

1. Every `build` directory under `common/versions/*`, the four loaders' `versions/*`, and
   `universal/` was deleted outright, then each of the seven loader nodes was built with
   `:<loader>:<version>:build --configure-on-demand`. All seven green, and `build` rather than
   `assemble` means **proguard and createDist really executed**.
2. The resulting jar set is identical to the pre-refactor set, **42 for 42**, once the
   `git describe` version is normalised out. Normalising is necessary because that version string
   changes with every commit, so raw filenames never compare equal across a commit boundary.
3. Dist filenames confirm the hoisted `compType` per loader:
   `baritone-api-fabric-<ver>.jar`, `-forge-`, `-neoforge-`, and for tweaker the unsuffixed
   `baritone-api-<ver>.jar`. That unsuffixed case is the one the refactor could most easily have
   broken, since tweaker is the only loader with a null `compType`.
4. The universal jar rebuilt from clean is **byte-identical** to the pre-clean one: 3,991,169 bytes,
   1043 object-store blobs, 4 module indexes.

The one thing still unverified post-refactor: whether all nine nodes CONFIGURE in a single
invocation. That was green before the refactor (a 10 minute `./gradlew build`), and
`./gradlew projects` lists the full tree after it, but the whole-build single invocation could not
be re-run here for memory reasons. Nothing in the refactor touches project registration, so the
risk is low, but it is not zero and it is worth one run on a machine with free memory.

**Still not run as of 2026-09-08 evening, and the reason is now measured rather than assumed.** The
machine was at 94.7 GB commit charge against a 101.4 GB limit, 6.7 GB free, with 4.3 GB of 63.9 GB
physical free: *less* headroom than the 85 GB that killed the three earlier attempts. Gradle daemons
were not the problem, holding about 2.9 GB between six JVMs; the charge is WSL at 20.2 GB, three
JetBrains IDEs and a QEMU VM. Freeing that means closing the owner's own applications, so this was
left alone. Note `--dry-run` is NOT a cheaper way to settle it: unimined configures Minecraft
eagerly, and configuration is exactly the phase that dies, so a dry run costs the same memory as
the real one.

### Still open

- `mods.toml` declares the mod id as `baritoe`, an upstream typo. Changing a published mod id is the
  owner's call, so it was left alone.
- The fourth module, `baritone-forge-1.21.10`, has never been dispatched: Nylium's harness has no
  Forge 1.21.10 server, only 1.7.10, 1.16.5 and 1.21.11. The other three are proven; see below.
- **Baritone has still never been seen doing anything beyond starting.** The 1.21.10 client reaches
  the main menu from a universal jar, but no world has been loaded and no Baritone command has ever
  been issued, so no pathing and no rendering has been exercised. A client on 1.21.11 is untested
  too, for the asset reason recorded below.

## The universal jar has now been booted, 2026-09-08

**Three of its four modules dispatch on real servers.** This replaces the "nothing has been RUN"
item that led this file until now. Each run booted to Minecraft's own `Done (` readiness line, then
shut down on a `stop` command written to the server's stdin, and exited 0. None was force-killed.

| Server | Module the kernel selected | Extraction cache | Ready |
| --- | --- | --- | --- |
| Fabric 1.21.11 | `baritone-fabric-1.21.11.index` | `baritone-fabric-1.21.11-77ca8a47887004ac.jar` | `Done (0.537s)` |
| Fabric 1.21.10 | `baritone-fabric-1.21.10.index` | `baritone-fabric-1.21.10-f641e2d9453d6d48.jar` | `Done (4.270s)` |
| Forge 1.21.11 (ML9) | `baritone-forge-1.21.11.index` | `baritone-forge-1.21.11-aafe1a736d07e963.jar` | `Done (5.038s)` |

Evidence, not inference. The kernel's Fabric and ML9 bootstraps print the descriptor they chose, so
each log carries a line like
`[Nylium] booted modules/baritone-fabric-1.21.11.index (platforms=[FABRIC], minecraft=1.21.11, environment=any)`.
The `.index` suffix is itself proof dedupe is live: the module is an index over the shared object
store, not a whole jar, and the cache entry is the real jar the kernel rebuilt from it. The two
Fabric rows are the load-bearing pair, the same universal jar picking a different module per server,
with different content hashes. Fabric also lists Baritone among its own mods
(`- baritone 1.15.0-41-g96b804da`). On ML9 the log additionally carries
`Successfully loaded Mixin Connector [baritone.launch.BaritoneMixinConnector]`, which is Baritone's
own class loading and running, not merely a module being extracted.

### What these boots prove, and what they cannot

Proven: per-version module selection, extraction from the deduped object store, mixin-config
registration, Baritone's own connector class loading on ML9, and no crash across a full boot and a
clean shutdown.

**Not proven: that Baritone does anything.** Every entry in `mixins.baritone.json` sits in its
`client` block, 21 of them on 1.21.11 and 20 on 1.21.10, and its `mixins` block is empty on both, so
on a dedicated server not one Baritone mixin applies; the ML9 connector registers the config and
Mixin then skips every entry. Baritone is a
client mod, so this is the ceiling for server-side verification. Do not read these three green rows
as "Baritone works on one jar" - read them as "the jar dispatches the right Baritone to the right
version, and nothing crashes." The client run below shows how much that gap mattered.

Two log lines are worth recognising so nobody debugs them as regressions. Mixin logs
`Mixin config mixins.baritone.json does not specify "minVersion" or "requiredFeatures" property`
at ERROR; that is an upstream Baritone config gap, non-fatal, and predates this work. The Forge run
also carries a log4j `MLClassLoaderContextSelector` `ClassCastException` and a netty
`Epoll ... Only supported on Linux` failure, both ordinary Forge-on-Windows noise that fire before
Nylium boots.

## The Fabric modules crashed the client, found and FIXED 2026-09-08

**Fixed in Nylium, not here.** Its kernel now extracts a module's own `META-INF/jars` entries and
puts them on the classpath, so `include`d dependencies survive dispatch; see Nylium's limitation 5
and `Nylium/docs/superpowers/specs/2026-09-08-nylium-nested-jars-design.md`. Nothing in this repo
changed, and the universal jar's `nylium-modules.properties` is byte-identical, still 16 lines.

**Verified on the client that failed.** Rebuilt against the fixed Nylium
(`baritone-1.15.0-49-g2100312f-universal.jar`), the Fabric 1.21.10 client reaches the sound engine
and is still alive twenty seconds later, with no `NoClassDefFoundError` and no crash report. Both
Fabric servers now extract `nether-pathfinder-1.4.1-5bf06c2406b80c86.jar` beside their module, with
the same content hash on each; the Forge server extracts only its module, since Forge flattens the
dependency, so the fix is correctly inert there. All three server boots were re-run and stayed
green.

**The native loads, which is a stronger claim than the class resolving.** The client log carries
`[nether-pathfinder] Created temp file at ...nether_pathfinder-x86_64...dll` followed by
`[nether-pathfinder] Loaded shared library`. That matters because
`NetherPathfinderContext.isSupported()` is a bare call into the native: a resolved class with an
unloadable native would have been a different failure wearing the same clothes. Its
`[nether-pathfinder] Failed to delete temp file` line is nether-pathfinder's own benign Windows
message, since a mapped DLL cannot be deleted while loaded.

**Still not seen: Baritone doing anything.** The client reaches the main menu. No world has been
loaded and no Baritone command has ever been issued from a universal jar.

The original diagnosis follows, kept because the mechanism is worth understanding before anyone
changes how modules are packaged.

### The original finding

**A real Fabric 1.21.10 client was booted with the universal jar and it crashed during startup.**
This is the blocker SP-3 has to clear before it can ship, and it is worth understanding exactly how
much of the way it got first, because almost everything worked:

- Nylium dispatched **on a client**, the first time that has ever happened on any backend:
  `[Nylium] booted modules/baritone-fabric-1.21.10.index (platforms=[FABRIC], minecraft=1.21.10, environment=any)`.
- Mixin reported `Detected Side : CLIENT`, selected `mixins.baritone.json`, prepared all 20 mixins
  and applied them against intermediary names (`MixinMinecraft` into `net.minecraft.class_310`,
  `MixinWorldRenderer` into `class_761`, and so on). So a production-remapped module dispatched by
  the kernel resolves correctly against a production client's namespace.
- Baritone itself ran and spoke to the player:
  `[CHAT] [Baritone] Baritone settings file not found, resetting.`
- Then the game died with `NoClassDefFoundError: dev/babbaj/pathfinder/NetherPathfinder`.

### Root cause: Fabric jar-in-jar does not survive dispatch

The stack is unambiguous and fires on every startup, from Baritone's own mixin:

```
MixinMinecraft handler$zzh000$postInit -> BaritoneAPI.<clinit> -> BaritoneProvider
  -> Baritone.<init> -> registerProcess -> ElytraProcess.create
  -> NetherPathfinderContext.isSupported -> NetherPathfinder.isThisSystemSupported()
```

`fabric/build.gradle` declares `include "dev.babbaj:nether-pathfinder:..."`, which is Fabric's
**jar-in-jar**: the dependency is nested at `META-INF/jars/nether-pathfinder-1.4.1.jar` and named in
that jar's own `fabric.mod.json` `jars` array. Fabric Loader unpacks nested jars during **mod
discovery**, but Nylium extracts the module and adds it to the classpath at **prelaunch**, long
after discovery is over, and the universal jar's generated outer `fabric.mod.json` carries no `jars`
key of its own. The bytes are present in the extracted module and simply unreachable: a jar nested
inside a jar is not on any classpath.

`NetherPathfinderContext.isSupported()` is a bare `return NetherPathfinder.isThisSystemSupported();`
with no guard, so a missing class is a hard crash during `Initializing game` rather than a disabled
elytra feature.

**Only Fabric is affected, and it is measured, not assumed.** `forge` and `neoforge` declare
`shadowCommon "dev.babbaj:nether-pathfinder:..."`, which flattens the classes into the jar:

| Module jar | `META-INF/jars` entries | `dev/babbaj` class entries |
| --- | --- | --- |
| `baritone-fabric` 1.21.10 and 1.21.11 | 2 | 0 |
| `baritone-forge` 1.21.11 | 0 | 62 |
| `baritone-neoforge` 1.21.11 | 0 | 62 |

So both Fabric modules in the universal jar are broken and both Forge modules are fine.

**No server boot could ever have caught this.** Baritone's mixins are client-only, so on a dedicated
server `BaritoneAPI` is never initialised and `NetherPathfinder` is never touched, which is exactly
why all three server rows above are green. Anyone tempted to treat the server matrix as SP-3's
acceptance test should read this as the counterexample.

### Which fix was taken, and why

Two routes were on the table. **Route 2 was taken.**

1. **Flatten in Baritone.** Make the Fabric node shade `nether-pathfinder` the way `forge` and
   `neoforge` already do. Narrow and immediate, but `include` is the idiomatic Fabric mechanism, so
   it would either change the standalone Fabric release jar too or need a module-only variant built
   just for `:universal`. Not taken; nothing in this repo was changed.
2. **Handle nested jars in Nylium.** Taken, because a Fabric mod with `include`d dependencies is an
   ordinary shape and every future consumer would otherwise hit this. Note the implemented design is
   NOT the one first written down: declaring nested jars in the module manifest was withdrawn
   mid-execution once it turned out the manifest is rendered at configuration time, before a
   consumer's module jars exist. The kernel discovers them at runtime instead, so no wire format
   changed and jars built earlier are fixed by upgrading alone.

### How the client was booted, since no harness does it

Nylium's smoke harness provisions servers only, and a dev client is the wrong environment: unimined
runs the game in the `named` namespace while the universal jar's modules are remapped to
`intermediary`, and the kernel extracts them at prelaunch, after Fabric's dev remapping step. So the
client has to be a production one. `scripts/launch-production-client.ps1` does it, reusing an
existing vanilla installation read-only: it merges the Fabric profile JSON from `meta.fabricmc.net`
over the vanilla version JSON, resolves libraries, extracts the windows natives and launches
`net.fabricmc.loader.impl.launch.knot.KnotClient` against a scratch game directory. Copy the
universal jar into `<GameDirectory>/mods` first; pass `-ResolveOnly` to check the classpath without
launching. On this machine 85 of 93 classpath entries came from `libraries/`, assets came
from its `assets/` with index 27, and only 7 small Fabric jars were downloaded. The game directory is
a scratch directory, never the real `.minecraft`, so the real `mods/` is untouched.

Three traps, all of which cost a launch attempt:

- **A java `@argfile` treats backslash as an escape inside quotes**, so a Windows classpath written
  into one arrives mangled and the launch dies with `ClassNotFoundException` on the main class.
  Write those paths with forward slashes, which Java accepts on Windows.
- **Libraries must be deduplicated by `group:artifact`, with the Fabric profile winning.** Fabric
  ships ASM 9.7.1 and vanilla 1.21.10 ships 9.6, and Fabric Loader refuses to start with both:
  `duplicate ASM classes found on classpath`. That precedence is what the vanilla launcher applies
  when merging an `inheritsFrom` profile.
- **Fabric Loader 0.16.9 is too old for a 1.21.10 client.** It works, but its bundled Mixin caps at
  `JAVA_13`/class version 61 and warns on every 1.21.10 class it touches
  (`Class version 65 required is higher than the class version supported`). The nested-jar crash is
  independent of this, but pick a newer loader before reading any client result as clean.

The 401 `Failed to fetch user properties` and Realms errors are expected: the launch is offline with
`--accessToken 0`, and single-player is unaffected.

### 1.21.11 on a client is still untested

Its asset index is 29 and this machine has 26, 27, 30 and 32, so verifying it means downloading an
asset set. It was skipped while the crash stood, since 1.21.11's Fabric module has the identical
nested layout and would have failed identically. Now that the crash is fixed it is worth doing, and
it is the obvious next verification: its module is the one whose source is authored directly rather
than ported down, and its server boot already extracts the same nested jar.

### How to re-run this, and the two traps in doing so

**Do not use `./gradlew :smoke:test` for Baritone.** That harness asserts on a marker file written
by a module's entrypoint, and Baritone declares no entrypoint, so it can only ever fail. Worse, it
force-kills the server the instant a marker appears, which is the exact structural blindness that
kept LaunchWrapper green over a dying server for this project's whole history.

Install the jar through Nylium's provisioning tasks, which clear `mods/` and delete the stale
extraction cache first, then boot by hand and wait for `Done (`:

```
cd ../Nylium
./gradlew :smoke:provisionFabricServers -PnyliumSmoke "-PnyliumSmokeJar=<abs path to universal jar>"
./gradlew :smoke:provisionForge12111   -PnyliumSmoke "-PnyliumSmokeJar=<abs path to universal jar>"
```

Provisioning renames the jar to `nylium-testmod-universal.jar` regardless of what it holds, because
`ModLauncher9SmokeTest` launches a literal `-cp` naming that file. Fabric boots with
`-jar fabric-server-launch.jar nogui`; ML9 cannot, because its `ILaunchPluginService` is enumerated
from the boot layer ModLauncher builds from the literal JVM classpath and never from a `mods/` scan,
so it needs
`-cp nylium-testmod-universal.jar;forge-1.21.11-61.1.5-shim.jar net.minecraftforge.bootstrap.shim.Main nogui`.
Delete each server's `nylium/` directory between runs or the cache hides a failure to extract.

**The stdin trap, if you drive the server from PowerShell.** `Process.StandardInput` is a
`StreamWriter` over `Console.InputEncoding` with `AutoFlush = true`, and the `AutoFlush` setter
flushes immediately, so a preamble-carrying encoding writes a UTF-8 BOM into the pipe at
`Process.Start`, before anything you send. The server reads it as part of the first command name and
answers `Unknown or incomplete command` on a line that renders as `﻿stop<--[HERE]`, the server never
stops, and a driver that waits for exit hangs. Writing raw bytes to `.BaseStream` does not help; the
BOM is already in the pipe. Set an encoding with no preamble before `Start`
(`[Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false`). Confirmed by hexdump:
`ef bb bf 73 74 6f 70`.

## Branch model, and what must NOT be deleted yet

**Adopted 2026-09-06.** This fork now follows the global two-branch rule: `main` (the default
branch) and `development`, both currently at the same commit, with feature branches off
`development` for anything else. The old milestone branch `m2-mc1.21.10` was renamed to
`development`. `main` is the Nylium-based single-jar line, not a legacy per-version line.

`origin` is `intisy/baritone`. `upstream` is `cabaletta/baritone` and must never be pushed to.
Note that the local `restructure-master` branch tracks **upstream**, so a careless `git push` on
it aims at the wrong repository.

**RETRACTED 2026-09-08: every per-version branch is safe to delete, and the claim below that
deleting them would destroy unfolded work was wrong.** It rested on `--is-ancestor` alone and never
asked the other question: whether the fork's copy holds anything `upstream` does not. Measured for
all 19:

| Group | Branches | Evidence |
| --- | --- | --- |
| Ancestors of `development` | 1.19.2, 1.19.3, 1.19.4, 1.20.1, 1.20.2, 1.20.4, 1.20.5, 1.21, 1.21.1, 1.21.3, 1.21.5, 1.21.8 | every commit already reachable from `development` |
| Byte-identical to upstream | 1.13.2, 1.14.4, 1.15.2, 1.16.5, 1.17.1, 1.18.2 | `git log upstream/<v>..origin/<v>` is **0 commits** |
| Genuinely unique | 1.21.4 | 8 commits not in upstream: the fork's custom features |

So the 1.16.5, 1.17.1 and 1.18.2 source that the note below called irreplaceable is sitting at
`upstream/1.16.5` and friends, a public remote that is not going anywhere. Only `1.21.4` ever held
anything of its own.

**And `1.21.4` is now guarded too.** The 2026-07-13 plan's Phase M0 was supposed to create an
archive tag and push it; the tag `archive/1.21.4-custom` existed **locally only**, so the guard the
whole deletion plan depended on was never published. It is now pushed and verified on the remote at
`20e5bb8d5`, and `git merge-base --is-ancestor origin/1.21.4 archive/1.21.4-custom` confirms it
covers that branch's tip.

**The deletion itself was refused by this environment's permission layer**, not declined on the
merits: `git push origin --delete` for the 19 branches was blocked by the sandbox classifier even
with the owner's explicit authorisation, so it needs either a Bash permission rule or a manual run.
Nothing about the analysis above is waiting on anything else.

The original note follows, superseded.

**The remaining per-version branches are scheduled for deletion, but deleting them now would
destroy work that has not been folded in yet.** `origin` carries 20 per-version branches
(`1.13.2` through `1.21.10`) while `development` carries only two Stonecutter nodes, `1.21.10` and
`1.21.11`. Measured, not assumed:

| Branch | Java files | Ancestor of `development`? | Safe to delete? |
| --- | --- | --- | --- |
| `1.21.10` | 363 | yes | **deleted 2026-09-06** |
| `1.21.8` | 363 | yes | **YES, not yet deleted** |
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

**`1.21.8` now satisfies both conditions, measured 2026-09-08:** its version exists as a Stonecutter
node, and `git merge-base --is-ancestor origin/1.21.8 development` returns true, so every commit on
it is reachable from `development` and the ref carries no unique work. It was left in place anyway,
because deleting someone else's remote branch is not a side effect to take unasked.

**So: delete a version branch only once its version exists as a Stonecutter node under
`common/versions/`, and check `--is-ancestor` first.** Deleting them as a batch before the collapse
finishes would leave 18 targets with no source to fold.

## Known rule violations

### CI workflows: half closed, 2026-09-08

The global rule is that a consumer repo's `.github/workflows/*` are thin callers and any workflow
carrying `runs-on`, `steps` or logic belongs in a shared workflows repo. Both of this repo's
workflows violated it.

`run_tests.yml` **is fixed**: it now calls
`intisy/workflows/.github/workflows/test.yml@main` with `java_version`, `gradle_test` and a raised
timeout, the same shape Nylium uses, with no behaviour lost.

`gradle_build.yml` **is not**, and cannot be closed from inside this repo. It builds and uploads
`dist/` and `mapping/` as artifacts, and no reusable workflow in `intisy/workflows` uploads
artifacts. Two inputs also have to exist there before a caller can work:

- `artifact_paths` / `artifact_name`, since nothing uploads artifacts today.
- `fetch_depth`. The shared `test.yml` checks out at the default shallow depth with no tags, and
  this repo's version comes from `git describe --tags`, so a converted build would silently fall
  back to the static `mod_version` instead of failing visibly.

**The change is written and committed but NOT pushed:** the push to `intisy/workflows` was refused
by this environment's permission layer, so it exists only as a patch. Re-create it there (add the
two artifact inputs and `fetch_depth`, pass `fetch-depth` to the primary checkout, and upload after
`post_test` with `if-no-files-found: error` and the runner label appended to the artifact name),
push it, and only then convert `gradle_build.yml`. Converting the caller first would point it at
inputs that do not exist and break CI outright.

Note that `intisy/workflows` itself has only `main` and one stale feature branch, with no
`development`, which the global two-branch rule expects. Not restructured here.

### README on `development`: FIXED 2026-09-08

`development` no longer carries a hand-written `README.md`. It now holds `CONTENT.md` plus
`.github/docs-config.yml` and a thin `readme.yml` caller, the same shape Nylium uses, so the README
is generated onto the default branch only.

`CONTENT.md` is not upstream's README with the badges stripped. Upstream's version table is wrong
for this fork, the badge rows and stargazer chart point at `cabaletta/baritone`, and the donation
line is upstream's. What was kept: the getting-started links, the API example, the FAQ, and the
credits to leijurv and YourKit, which a fork has no business dropping. What was added: what this
fork actually ships, since "one universal jar over Stonecutter nodes" is the whole point and
upstream's README says nothing about it.

**`main` still has the old README until the generator runs.** The rule is satisfied on
`development`; regenerating `main` needs a `workflow_dispatch` of `Generate README`, or a release.
Note also that `kind: java-library` in the docs config is copied from Nylium because it is the only
value known to work here; the generator's other kinds were not checked.

# READ FIRST: where the multi-version work actually lives

**Written 2026-09-06, substantially updated 2026-09-08.** This repo's 2026-07-13 spec and plan are
**partly superseded**. Read this before acting on them.

**Start here if you are new:** SP-3's blocker was removed on 2026-09-08. One `./gradlew build` now
produces a remapped loader jar per Minecraft version, and `:universal` assembles them into a Nylium
universal jar. Jump to "SP-3 blocker: REMOVED 2026-09-08" for what exists and what is still open.
**The jar has now been booted**: three of its four modules dispatch on real servers, verified
2026-09-08 evening. Jump to "The universal jar has now been booted" for what that does and does not
prove. The single most important open item is now that **no client has ever run it**, and Baritone
is a client mod, so nothing yet shows Baritone itself working.

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

**Both version nodes compile, re-confirmed 2026-09-08** as part of a full nine-node build.
`./gradlew :common:1.21.10:build` and `:common:1.21.11:build` are each green. Two pieces got them
there.

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

## SP-3 blocker: REMOVED 2026-09-08

**Loaders are now Stonecutter dimensions and one invocation builds every version.** This section
previously described the blocker and the spike that answered it; both are history. See
`docs/superpowers/specs/2026-09-08-loader-stonecutter-nodes-design.md` for the design and
`docs/superpowers/plans/2026-09-08-loader-stonecutter-nodes.md` for the executed plan, whose
"Deviations found while executing Task 3" section is the part worth reading.

### What one `./gradlew build` now produces

Measured, not assumed. Nine version nodes build in a single invocation:

| Project | Nodes |
| --- | --- |
| `:common` | 1.21.10, 1.21.11 |
| `:fabric` | 1.21.10, 1.21.11 |
| `:forge` | 1.21.10, 1.21.11 |
| `:neoforge` | 1.21.11 only |
| `:tweaker` | 1.21.10, 1.21.11 |

Seven remapped loader jars, 42 jars in total counting the api, dev, unoptimized and standalone
variants. Each node's jar declares its OWN Minecraft version: `:fabric:1.21.10`'s `fabric.mod.json`
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
`universal/build/distributions/baritone-<version>-universal.jar`, carrying four modules:

| Module | Platform | Minecraft |
| --- | --- | --- |
| `baritone-fabric-1.21.11` | `FABRIC` | 1.21.11 |
| `baritone-fabric-1.21.10` | `FABRIC` | 1.21.10 |
| `baritone-forge-1.21.11` | `MODLAUNCHER_9` | 1.21.11 |
| `baritone-forge-1.21.10` | `MODLAUNCHER_9` | 1.21.10 |

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
applications in a single configuration pass. Someone should decide whether
`org.gradle.configureondemand=true` belongs in `gradle.properties` before more versions are folded
in. It was NOT set here, because it changes behaviour for every invocation and that is the owner's
call, not a side effect of this work.

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
- **Baritone's own behaviour is still unverified**, and a dedicated server cannot verify it. See the
  boundary in the next section.

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

**Not proven: that Baritone does anything.** All 21 entries in `mixins.baritone.json` sit in its
`client` block and its `mixins` block is empty, so on a dedicated server not one Baritone mixin
applies; the ML9 connector registers the config and Mixin then skips every entry. Baritone is a
client mod, so this is the ceiling for server-side verification, and the remaining gap is Nylium's
limitation 3: CLIENT is unverified on every backend and no client smoke test exists anywhere.
Do not read these three green rows as "Baritone works on one jar" - read them as "the jar dispatches
the right Baritone to the right version, and nothing crashes."

Two log lines are worth recognising so nobody debugs them as regressions. Mixin logs
`Mixin config mixins.baritone.json does not specify "minVersion" or "requiredFeatures" property`
at ERROR; that is an upstream Baritone config gap, non-fatal, and predates this work. The Forge run
also carries a log4j `MLClassLoaderContextSelector` `ClassCastException` and a netty
`Epoll ... Only supported on Linux` failure, both ordinary Forge-on-Windows noise that fire before
Nylium boots.

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

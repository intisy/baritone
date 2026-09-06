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

Nylium's three limitations are recorded with bytecode evidence in its kernel design spec. Two of
them bite specific Baritone targets:

- **1.16.5 Forge is blocked.** It is the only target in the ModLauncher 8 range (Forge 1.13 to
  1.16), where Nylium dispatches but cannot yet reach Minecraft classes. 1.16.5 Fabric and its
  launchwrapper tweaker are unaffected.
- **NeoForge is blocked on 10 targets** (1.20.4 and every 1.21.x) until Nylium SP-1b. NeoForge turned
  out to share no infrastructure with Forge: it ships zero ModLauncher classes and needs its own
  bootstrap.
- Everything else, Fabric and Forge 1.17+, is unblocked today.

So SP-3 can ship most of the matrix now and must not promise 1.16.5 Forge or any NeoForge jar until
those two Nylium items land.

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

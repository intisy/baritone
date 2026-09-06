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

## Uncommitted work in this tree

`common/stonecutter.gradle` carries roughly 36 uncommitted lines: a `stonecutter.parameters {}`
block with six per-version source replacements porting 1.21.11-authored source down to 1.21.10
mappings (Identifier to ResourceLocation, ResourceKey.identifier() to location(), camera.position()
to getPosition(), the Util and monster-class package moves).

**Verified 2026-09-06. The block itself works; the node still does not compile, for an unrelated
reason.** All six replacements land in Stonecutter's generated sources, and the version gate is
correct: the block evaluates once per node and reports `pre1_21_11=true` for 1.21.10 and `false`
for 1.21.11, so the shared source is untouched for 1.21.11.

Two things to know before re-checking that:

- **Stonecutter generates five source sets here** (`api`, `launch`, `main`, `schematica_api`,
  `test`). The `camera.position()` replacement only ever appears in `launch`. Grepping the
  generated `main` tree alone makes a working replacement look dead.
- **`:common:1.21.10:build` fails with 8 errors that no source replacement can fix.** `IRenderer`
  is a per-version overlay and the two copies have divergent signatures: 1.21.11 threads
  `lineWidth` through as a parameter, the 1.21.10 overlay is the older upstream shape that does
  not. The arities differ, so this needs the 1.21.10 overlay ported to 1.21.11's signature set,
  implemented against 1.21.10's render API. Three overloads are missing:

  | File | Line(s) | Missing overload |
  | --- | --- | --- |
  | `ElytraBehavior.java` | 427, 434, 441 | `startLines(Color)` |
  | `ElytraBehavior.java` | 429, 436, 446 | `emitLine(BufferBuilder, PoseStack, Vec3, Vec3, float)` |
  | `GuiClick.java` | 134 | `startLines(Color)` |
  | `SelectionRenderer.java` | 35 | `emitAABB(BufferBuilder, PoseStack, AABB, double, float)` |

So the block is safe to commit on its own merit, but committing it does not make the node green.

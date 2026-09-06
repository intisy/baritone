# READ FIRST: where the multi-version work actually lives

**Written 2026-09-06.** This repo's 2026-07-13 spec and plan are **partly superseded**. Read this
before acting on them.

## The library that now carries the multi-version job

`F:\Documents\GitHub\intisy\minecraft\mods\Rutter`, branch `development`. Start at its
`docs/superpowers/HANDOFF.md`.

Rutter is a standalone library (own repo, own name, intended to be usable by mods other than
Baritone) that lets one jar boot on every mod loader from Minecraft 1.7 to 26.2. Its kernel is
complete and proven on five real servers across four loader bootstrap families. Baritone is
sub-project **SP-3** in Rutter's program overview: one Baritone jar for all versions and loaders,
with the fork's 8 custom features intact.

## What of the 2026-07-13 documents still stands

- **Superseded:** the packaging goal. That plan produces "the same per-version loader jars upstream
  ships today" (18 targets). The goal is now ONE universal jar, shadowing only the needed parts of
  Rutter. Phase M6's per-version release matrix goes with it.
- **Still valid, and still needed:** everything up to that point. The single-branch collapse, the
  Stonecutter version dimension over unimined, and above all the ports of 1.16.5, 1.17.1 and 1.18.2
  onto unimined+Mojmap. Rutter dispatches pre-remapped modules; it is **not** a runtime remapper, so
  per-version compiled modules remain exactly what the build must produce. That work is SP-3's input,
  not dead.

## How Rutter's known limits land on this repo's 18 targets

Rutter's three limitations are recorded with bytecode evidence in its kernel design spec. Two of
them bite specific Baritone targets:

- **1.16.5 Forge is blocked.** It is the only target in the ModLauncher 8 range (Forge 1.13 to
  1.16), where Rutter dispatches but cannot yet reach Minecraft classes. 1.16.5 Fabric and its
  launchwrapper tweaker are unaffected.
- **NeoForge is blocked on 10 targets** (1.20.4 and every 1.21.x) until Rutter SP-1b. NeoForge turned
  out to share no infrastructure with Forge: it ships zero ModLauncher classes and needs its own
  bootstrap.
- Everything else, Fabric and Forge 1.17+, is unblocked today.

So SP-3 can ship most of the matrix now and must not promise 1.16.5 Forge or any NeoForge jar until
those two Rutter items land.

## Uncommitted work in this tree

`common/stonecutter.gradle` carries roughly 36 uncommitted lines: a `stonecutter.parameters {}`
block with six per-version source replacements porting 1.21.11-authored source down to 1.21.10
mappings (Identifier to ResourceLocation, ResourceKey.identifier() to location(), camera.position()
to getPosition(), the Util and monster-class package moves). **Its build state was never verified in
the session that wrote it.** Build the 1.21.10 node before trusting or committing it.

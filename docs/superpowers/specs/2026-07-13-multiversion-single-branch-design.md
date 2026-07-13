# Multi-Version Single-Branch Baritone — Design

**Date:** 2026-07-13
**Status:** Approved (design), pending spec review
**Repo:** `F:\Documents\GitHub\minecraft\mod\baritone` (fork `intisy/baritone`, upstream `cabaletta/baritone`)

## Goal

Collapse the fork's ~35 origin branches and 3 local branches into **one branch** that
builds Baritone for **every supported Minecraft version from 1.16.5 through 1.21.11**,
producing the same per-version loader jars upstream ships today, verified by CI. The
fork's 8 custom commits (player/NPC avoidance, sprint jumping + head hitters, sprint
swimming and its refinements) become shared features that apply across all versions.

## Non-Goals

- Minecraft 26.1 / 26.2 support. Upstream baritone stops at 1.21.11; 26.x is deferred to
  a later phase once this foundation works. (Reference forks exist: `dysnasia/baritone-26.2`.)
- Pre-1.16.5 versions (1.13.2–1.15.2). Their APIs and code differ by ~12k+ lines from the
  modern tree; not worth the conditional burden.
- Automated in-game/gameplay testing. CI verifies *compilation* of all targets; in-game
  behavior is spot-checked manually.
- Unrelated refactoring of baritone internals.

## Requirements (locked with user)

| Decision | Choice |
| --- | --- |
| Version range | 1.16.5 → 1.21.11 (18 upstream targets) |
| 26.x | Deferred — cap at 1.21.11 for now |
| Loaders | Match upstream per version (Fabric everywhere; Forge/NeoForge/Tweaker where upstream ships them) |
| Verification | CI builds every version×loader jar on push; release publishes all jars. In-game testing manual |
| Build system | Stonecutter (preprocessor) on top of existing unimined toolchain |

## Target Matrix

18 targets, all Mojmap:

`1.16.5, 1.17.1, 1.18.2, 1.19.2, 1.19.3, 1.19.4, 1.20.1, 1.20.2, 1.20.4, 1.20.5, 1.21, 1.21.1, 1.21.3, 1.21.4, 1.21.5, 1.21.8, 1.21.10, 1.21.11`

Each target ships exactly the loaders its upstream branch ships today (e.g. NeoForge from
1.20.2+; Tweaker/launchwrapper on the legacy end). Per-version constants (MC version,
Java version 8/16/17/21, loader versions, enabled loaders) live in a per-version
properties file.

**Divergence measured** (`git diff upstream/1.21.4 upstream/<v>`, Java only):
1.21.5 ≈31 files; 1.21.1 ≈25; 1.20.4 ≈45; 1.20.1 ≈51; 1.19.4 ≈74/2.7k lines;
1.16.5 ≈237 files/11.6k lines. Confirms the low end is cheap and the 1.16–1.18 floor is
the bulk of the work.

## Architecture

### Branch & remote layout
- One branch: **`master`** on origin.
- Base = `upstream/1.21.11` (newest, cleanest) + the 8 custom commits cherry-picked on top.
- Before any deletion: tag current `1.21.4` tip `archive/1.21.4-custom` and push to origin,
  so original work stays reachable regardless of branch cleanup.
- Delete all other branches, local and on origin (~35 origin + 2 other local), **after**
  the new `master` builds green.
- Keep the `upstream` remote — its version branches are the recipe for every conditional.

### Build-system reality (verified 2026-07-13)

The single-branch approach requires **one Gradle toolchain and one mapping namespace**
across all targets — Stonecutter parameterizes *source text*, not the build toolchain or
the mapping namespace. Inspection of the upstream branches shows the range is **not**
uniform:

| Versions | Build system | Mappings | State |
| --- | --- | --- | --- |
| 1.19.2 – 1.21.11 | unimined | Mojmap (`official` fallback) | Native — joins directly |
| 1.17.1 / 1.18.2 | non-unimined (`OFFICIAL`-mapping setup, pre-`available_loaders`) | differs | **Must be ported to unimined+Mojmap first** |
| 1.16.5 | ForgeGradle 3 + fabric-loom 0.7 | MCP/SRG/Yarn (obfuscated) | **Must be ported to unimined+Mojmap first — largest single item** |

Consequence: 1.16.5–1.18.2 are **not** "just more conditionals." Each must first be
migrated onto unimined+Mojmap (work upstream never did) before it can share source with
the modern tree. The user has accepted this and requires the 1.16.5 floor regardless.

### Build system
- **Stonecutter** (`stonecutter.gradle.kts` + `settings.gradle` plugin, `dev.kikugie.stonecutter`)
  manages the version dimension; **unimined** is the single MC toolchain/mapping provider
  for **every** target (legacy targets are ported onto it — see above).
- Existing subproject layout is preserved: common `src/` + `fabric` / `forge` / `neoforge`
  / `tweaker`. Stonecutter selects the "active" version for IDE/dev and drives
  `chiseledBuild` to compile all targets in CI.
- Per-target constants (MC version, Java version, loader versions, enabled loaders) live in
  the Stonecutter version node / a per-version properties file.

### Source strategy
- Shared source == 1.21.11.
- Version-specific differences are expressed as Stonecutter comment conditionals
  (e.g. `//? if <1.20.5 {`), generated mechanically by walking `git diff` between adjacent
  upstream version branches, newest → oldest.
- Custom features live in shared code → apply to all versions (older versions that never
  had them need manual spot-testing).

### CI & releases
- GitHub Actions matrix builds all 18 targets (`chiseled build`) on every push; artifacts =
  per-loader jars per version.
- A release tag runs the full build and publishes the complete jar set to GitHub Releases.

## Migration Plan (each milestone ends in a buildable state)

- **M0 — Consolidate.** New `master` = `upstream/1.21.11` + 8 custom commits; build green;
  push `archive/1.21.4-custom` tag; delete all other local+origin branches.
- **M1 — Scaffold.** Integrate Stonecutter; 1.21.11 builds through it. Begins with a short
  spike validating Stonecutter↔unimined fit. **Fallback** if they fight: per-version
  `gradle.properties` swap driven by a Gradle property, no comment-preprocessor — same
  branch model, more manual.
- **M2 — 1.21.x floor** (1.21.10 → 1.21): small diffs; proves the walk-down workflow.
- **M3 — 1.20.x floor** (1.20.5 → 1.20.1).
- **M4 — 1.19.x floor** (1.19.4 → 1.19.2).
- **M5 — Legacy port + fold-in** (the heavy phase; each version is port-then-fold, done
  one at a time, every step ends buildable):
  - **M5a — 1.18.2:** port its subproject onto unimined+Mojmap as a standalone Stonecutter
    node, then express its diffs vs 1.19.2 as conditionals and fold into shared source.
  - **M5b — 1.17.1:** same, diffing vs 1.18.2.
  - **M5c — 1.16.5:** port from ForgeGradle3+loom(MCP) onto unimined+Mojmap — the largest
    single item — then fold in (launchwrapper-era tweaker, Java differences). Re-scopable
    or pausable here without wasting any prior work.
- **M6 — CI matrix + release workflow.**

## Testing & Verification

- Each milestone must keep **all previously-added targets compiling** before the next starts.
- Existing JUnit tests run per active version; CI runs them across the matrix.
- Definition of done per version: all its loader jars compile in CI.

## Risks

- **Stonecutter/unimined integration friction** — mitigated by the M1 spike and the
  gradle.properties-swap fallback.
- **1.16–1.18 build-system port (highest risk)** — 1.16.5–1.18.2 are on a different
  toolchain/mappings and must be ported to unimined+Mojmap before folding in; 1.16.5
  (ForgeGradle3+loom, MCP obfuscated names) is effectively its own mini-project. Upstream
  never did this port, so there is no reference. User has accepted this cost. Because
  migration walks downward, M5 can be paused after any sub-milestone with every higher
  version already shipping.
- **Custom features on old versions** — they compile everywhere but may misbehave on
  versions whose movement/water APIs differ; flagged for manual spot-check.
- **Irreversible branch deletion** — mitigated by the `archive/1.21.4-custom` tag and by
  deleting only after the new `master` is green.

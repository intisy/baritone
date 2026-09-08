## What this fork ships

Baritone is a pathfinding bot for Minecraft, originally by [leijurv](https://github.com/leijurv/)
and [cabaletta](https://github.com/cabaletta/baritone). This fork's goal is different from
upstream's: instead of one jar per Minecraft version per mod loader, it builds **one universal jar**
that carries a precompiled module per target and loads the right one at launch, using
[Nylium](https://github.com/intisy/nylium) to dispatch.

One source tree, one branch, one artifact. Minecraft versions are
[Stonecutter](https://github.com/kikugie/stonecutter) nodes over a
[unimined](https://github.com/unimined/unimined) build, and each loader is a dimension over those
nodes, so a single invocation produces every remapped loader jar and assembles them together.

### Coverage

The universal jar currently carries Fabric and Forge modules for Minecraft 1.21.5, 1.21.8, 1.21.10
and 1.21.11. Folding in the older versions is in progress.

NeoForge and the LaunchWrapper tweaker build but are deliberately not packaged yet: Nylium has no
NeoForge bootstrap, and its LaunchWrapper backend dispatches and then crashes the game. Forge 1.13
to 1.16 dispatches but cannot reach Minecraft classes. Those are Nylium limitations, recorded in its
own documentation, not gaps in this build.

## Getting started

- [Features](FEATURES.md)
- [Installation and setup](SETUP.md)
- [Usage, chat control](USAGE.md)
- [API Javadocs](https://baritone.leijurv.com/)
- [Settings](https://baritone.leijurv.com/baritone/api/Settings.html#field.detail)

## API

The API is heavily documented; Javadocs for upstream's latest release are
[here](https://baritone.leijurv.com/). Anything outside the `baritone.api` package is not supported
by the API release jar.

Basic usage, changing a couple of settings and then pathing to an X/Z goal:

```java
BaritoneAPI.getSettings().allowSprint.value = true;
BaritoneAPI.getSettings().primaryTimeoutMS.value = 2000L;

BaritoneAPI.getProvider().getPrimaryBaritone().getCustomGoalProcess().setGoalAndPath(new GoalXZ(10000, 20000));
```

## FAQ

### Can I use Baritone as a library in my own client?

That is what it is for, as long as your usage complies with the LGPL 3.0 licence.

### How is it so fast?

It is an updated version of [MineBot](https://github.com/leijurv/MineBot/), rebuilt with reliability
and performance as the point; upstream measured it as
[over 30x faster](https://github.com/cabaletta/baritone/pull/180#issuecomment-423822928) than
MineBot at calculating paths.

### Why is it called Baritone?

It is named for FitMC's deep sultry voice.

## Credits

Baritone is upstream's work. This fork only changes how it is built and shipped.

YourKit granted the original project an open source licence for its
[Java Profiler](https://www.yourkit.com/java/profiler/), which supports monitoring and profiling
Java and .NET applications.

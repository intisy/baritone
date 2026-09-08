# Loader Subprojects as Stonecutter Nodes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every loader subproject a Stonecutter version node so one Gradle invocation produces a pre-remapped loader jar per Minecraft version, then package those jars into a single Nylium universal Baritone jar.

**Architecture:** `settings.gradle` registers `:common` and all four loaders against one shared Stonecutter version set, so `:fabric:1.21.10` and `:fabric:1.21.11` coexist. Root `build.gradle` loses its active-version regex parse and its `allprojects {}` block entirely; the shared loader configuration moves to `gradle/loader-conventions.gradle`, which each loader node applies and which resolves per-version constants from `common/versions/<ver>/gradle.properties` keyed on the node's own version. A new `:universal` project applies the Nylium Gradle plugin and turns each node's `remapJar` into a module.

**Tech Stack:** Gradle 8.14.4 (Groovy DSL), Stonecutter 0.7.11, unimined 1.4.2-SNAPSHOT (via buildSrc), shadow 8.0.0, Nylium 0.1.0-SNAPSHOT.

**Spec:** `docs/superpowers/specs/2026-09-08-loader-stonecutter-nodes-design.md`

## Global Constraints

- Commit messages: Conventional Commits, `type(scope): summary`, imperative, lowercase summary, no trailing period, no task or phase archaeology anywhere in the message.
- Commit as `finn@birich.de`. Never pass `-c user.email` or `-c user.name`.
- Work on branch `development`. Never push to the `upstream` remote (`cabaletta/baritone`). The local `restructure-master` branch tracks upstream, so never push while it is checked out.
- Never use en-dashes or em-dashes in any file, comment, commit message or output. Plain hyphens only.
- Comments: default to zero. A comment may only carry non-obvious *why*. Never restate what the code does. Prefer extracting a well-named variable or method over writing a comment.
- Never delete existing code without asking first. Deletions named explicitly in this plan are pre-approved; anything else is not.
- Do not create a README on `development`.
- Verify every build result by reading artifacts or output, never by exit code alone. `grep -c` returning 0 exits non-zero and will break a `&&` chain.

## Baseline, measured 2026-09-08

`./gradlew help --offline` exits 0. Six projects configure: four loaders plus `:common:1.21.10` and `:common:1.21.11`. Both `STONECUTTER-PARAMS` lines print, with 1.21.11 active. Any configuration failure after Task 3 is caused by this work.

---

### Task 1: Publish Nylium to mavenLocal under its new name

Nylium was renamed from Rutter on 2026-09-06. mavenLocal still holds only `io.github.intisy.rutter`. Baritone cannot resolve the plugin until this is done, and a leftover `rutter` tree is exactly the kind of stale artifact that made a rename look like a kernel regression before.

**Files:**
- Modify: none in this repo.
- External: `F:\Documents\GitHub\intisy\minecraft\mods\Nylium` (publish only, no source change).

**Interfaces:**
- Produces: Maven coordinates `io.github.intisy.nylium:nylium-gradle:0.1.0-SNAPSHOT` and the marker artifact `io.github.intisy.nylium:io.github.intisy.nylium.gradle.plugin:0.1.0-SNAPSHOT` in `~/.m2/repository`, consumed by Task 5.

- [ ] **Step 1: Record what mavenLocal holds now**

```bash
ls /c/Users/finn/.m2/repository/io/github/intisy/
ls /c/Users/finn/.m2/repository/io/github/intisy/rutter/
```

Expected: `rutter` present, `nylium` absent.

- [ ] **Step 2: Delete the stale rutter tree**

This is a pre-rename artifact of a project never published under either name, so nothing consumes it.

```bash
rm -rf /c/Users/finn/.m2/repository/io/github/intisy/rutter
ls /c/Users/finn/.m2/repository/io/github/intisy/
```

Expected: `rutter` gone.

- [ ] **Step 3: Publish Nylium**

```bash
cd "F:/Documents/GitHub/intisy/minecraft/mods/Nylium" && ./gradlew publishToMavenLocal
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Verify the published coordinates**

```bash
find /c/Users/finn/.m2/repository/io/github/intisy/nylium -name "*.jar" -o -name "*.pom" | sort
```

Expected: at minimum `nylium-gradle`, `nylium-api`, `nylium-core` and the `io.github.intisy.nylium.gradle.plugin` marker. If the marker pom is missing, the `plugins { id 'io.github.intisy.nylium' }` block in Task 5 cannot resolve; stop and report rather than working around it.

- [ ] **Step 5: No commit**

Nothing in this repo changed. Do not create an empty commit.

---

### Task 2: Template the Minecraft version into loader metadata

`fabric.mod.json`, `mods.toml` and `neoforge.mods.toml` hardcode 1.21.11. Today only one version builds per invocation so this is invisible. From Task 3 onward the 1.21.10 nodes would ship jars declaring they need 1.21.11. Fixing it first keeps the failure out of the risky task.

**Files:**
- Modify: `fabric/src/main/resources/fabric.mod.json`
- Modify: `forge/src/main/resources/META-INF/mods.toml`
- Modify: `neoforge/src/main/resources/META-INF/neoforge.mods.toml`
- Modify: `fabric/build.gradle`, `forge/build.gradle`, `neoforge/build.gradle` (the `processResources` blocks)

**Interfaces:**
- Consumes: nothing.
- Produces: each loader's `processResources` expands both `version` and `minecraft_version`. Task 3 and Task 4 preserve both properties.

- [ ] **Step 1: Confirm the hardcoded values**

```bash
cd "F:/Documents/GitHub/intisy/minecraft/mods/baritone"
grep -n "1.21.11" fabric/src/main/resources/fabric.mod.json forge/src/main/resources/META-INF/mods.toml neoforge/src/main/resources/META-INF/neoforge.mods.toml
```

Expected: one hit in `fabric.mod.json` (the `depends.minecraft` array), one in each toml (`versionRange`).

- [ ] **Step 2: Template fabric.mod.json**

Replace the `depends` block's minecraft entry so it reads:

```json
  "depends": {
    "fabricloader": ">=0.14.22",
    "minecraft": ["${minecraft_version}"]
  },
```

- [ ] **Step 3: Template both toml files**

In `forge/src/main/resources/META-INF/mods.toml` and `neoforge/src/main/resources/META-INF/neoforge.mods.toml`, replace the hardcoded range:

```toml
versionRange="[${minecraft_version}]"
```

- [ ] **Step 4: Expand the new property in each loader script**

In `fabric/build.gradle`, `forge/build.gradle` and `neoforge/build.gradle`, change the `processResources` block so it supplies both properties. Fabric's becomes:

```groovy
processResources {
    inputs.property "version", project.version
    inputs.property "minecraft_version", rootProject.minecraft_version

    filesMatching("fabric.mod.json") {
        expand "version": project.version, "minecraft_version": rootProject.minecraft_version
    }
}
```

Forge and neoforge are identical apart from the `filesMatching` argument, which stays `META-INF/mods.toml` and `META-INF/neoforge.mods.toml` respectively.

`rootProject.minecraft_version` is correct for now because root still loads the active version's properties. Task 3 replaces it.

- [ ] **Step 5: Build and read the generated metadata**

```bash
cd "F:/Documents/GitHub/intisy/minecraft/mods/baritone"
./gradlew :fabric:processResources :forge:processResources :neoforge:processResources
cat fabric/build/resources/main/fabric.mod.json | grep -A3 '"depends"'
grep -n "versionRange" forge/build/resources/main/META-INF/mods.toml
```

Expected: `"minecraft": ["1.21.11"]` and `versionRange="[1.21.11]"`, that is, the same values as before, now produced by expansion rather than hardcoded. If a `$` survives unexpanded, the expand call is wrong.

- [ ] **Step 6: Commit**

```bash
git add fabric forge neoforge
git commit -m "build(loaders): template the minecraft version into loader metadata"
```

---

### Task 3: Register every loader as a Stonecutter node

The risky task. It answers the one open question the spike left: whether unimined configures on a loader version node. Sequence the steps so Fabric proves it before the other three are touched.

**Files:**
- Modify: `settings.gradle`
- Create: `gradle/loader-conventions.gradle`
- Modify: `build.gradle` (root, large deletion)
- Modify: `fabric/build.gradle`, `forge/build.gradle`, `neoforge/build.gradle`, `tweaker/build.gradle`
- Delete: nothing. The four `<loader>/stonecutter.gradle` controllers are generated by Stonecutter, not written by hand.

**Interfaces:**
- Consumes: nothing from earlier tasks except Task 2's two-property `processResources`.
- Produces: `gradle/loader-conventions.gradle` sets these on the applying project, read by Task 4 and Task 5:
  - `ext.loaderEnabled` (boolean) - false when this version does not list this loader. The caller MUST `return` immediately when false.
  - `ext.nodeVersion` (String) - this node's Minecraft version, for example `"1.21.10"`.
  - `ext.loaderName` (String) - `"fabric"`, `"forge"`, `"neoforge"` or `"tweaker"`.
  - `ext.loaderVersion` (String) - the value of `<loaderName>_version` from the node's properties. Null for `tweaker`, which has no loader version.
  - `ext.commonNode` (Project) - the `:common` node of the SAME version.

- [ ] **Step 1: Reorder settings.gradle and register all five projects**

Replace the `include('common')` / `stonecutter { }` / loader loop section at the bottom of `settings.gradle` with:

```groovy
include('common')
for (platform in available_loaders.split(",")) {
    include(platform)
}

stonecutter {
    kotlinController = false
    shared {
        versions('1.21.11', '1.21.10')
        vcsVersion = '1.21.11'
    }
    create(project(':common'), project(':fabric'), project(':forge'),
           project(':neoforge'), project(':tweaker'))
}
```

The loader loop moves ABOVE the `stonecutter` block because `create()` requires the projects to exist. `kotlinController = false` stops `create()` generating `.gradle.kts` controllers.

- [ ] **Step 2: Verify the project tree, expecting configuration to fail**

```bash
./gradlew projects 2>&1 | tail -40
```

Expected: the task may FAIL, because the loader scripts still read `rootProject.active_loaders`, which is fine at this point. What matters is that Stonecutter generated `fabric/stonecutter.gradle`, `forge/stonecutter.gradle`, `neoforge/stonecutter.gradle` and `tweaker/stonecutter.gradle`, and that the node directories exist:

```bash
ls fabric/stonecutter.gradle forge/stonecutter.gradle neoforge/stonecutter.gradle tweaker/stonecutter.gradle
```

If any controller was written as `.gradle.kts`, `kotlinController` did not take effect. Stop and report rather than hand-writing the controller.

- [ ] **Step 3: Create the conventions script**

Create `gradle/loader-conventions.gradle`:

```groovy
def versionProps = new Properties()
rootProject.file("common/versions/${stonecutter.node.metadata.version}/gradle.properties")
        .withInputStream { versionProps.load(it) }

ext.nodeVersion = stonecutter.node.metadata.version
ext.loaderName = project.parent.name
ext.loaderEnabled = versionProps.getProperty('available_loaders')
        .split(',').collect { it.trim() }.contains(ext.loaderName)
if (!ext.loaderEnabled) {
    return
}

ext.loaderVersion = versionProps.getProperty("${ext.loaderName}_version")

def minecraftVersion = versionProps.getProperty('minecraft_version')
def javaVersion = versionProps.getProperty('java_version')
def parchmentVersion = versionProps.getProperty('parchment_version')

apply plugin: 'java'
apply plugin: 'xyz.wagyourtail.unimined'
apply plugin: 'maven-publish'

archivesBaseName = rootProject.archives_base_name
group = rootProject.maven_group

def describedVersion = ""
try {
    describedVersion = 'git describe --always --tags --first-parent --dirty'.execute().text.trim()
} catch (Exception e) {
    println "Version detection failed: " + e
}
if (!describedVersion.startsWith("v")) {
    println "using version number: " + rootProject.mod_version
    version = rootProject.mod_version
} else {
    version = describedVersion.substring(1)
    println "Detected version " + version
}

sourceCompatibility = targetCompatibility = JavaVersion.toVersion(javaVersion)

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(javaVersion.toInteger()))
    }
}

repositories {
    maven { url = "https://files.minecraftforge.net/maven/" }
    maven { name = 'spongepowered-repo'; url = 'https://repo.spongepowered.org/repository/maven-public/' }
    maven { name = 'fabric-maven'; url = 'https://maven.fabricmc.net/' }
    maven { name = 'impactdevelopment-repo'; url = 'https://impactdevelopment.github.io/maven/' }
    maven { name = "ldtteam"; url = "https://maven.parchmentmc.net/" }
    maven {
        name = "multimc-maven"
        url = "https://files.multimc.org/maven/"
        metadataSources { artifact() }
    }
    mavenCentral()
    maven { name = 'babbaj-repo'; url = 'https://babbaj.github.io/maven/' }
}

dependencies {
    compileOnly "org.spongepowered:mixin:${rootProject.mixin_version}"
    compileOnly "org.ow2.asm:asm:${rootProject.asm_version}"
    implementation "dev.babbaj:nether-pathfinder:${rootProject.nether_pathfinder_version}"
    implementation 'com.google.code.findbugs:jsr305:3.0.2'
}

ext.commonNode = project(":common:${ext.nodeVersion}")
evaluationDependsOn(ext.commonNode.path)

// Immediate apply, never the lateApply overload: a Stonecutter version node swallows unimined's
// deferred afterEvaluate and fails with "minecraft config never applied for source set 'main'".
unimined.minecraft(sourceSets.main) {
    version minecraftVersion

    mappings {
        intermediary()
        mojmap()
        parchment(minecraftVersion, parchmentVersion)
    }

    if (ext.has('loaderBlock')) {
        ext.loaderBlock.delegate = delegate
        ext.loaderBlock.resolveStrategy = Closure.DELEGATE_FIRST
        ext.loaderBlock()
    }
}

tasks.withType(JavaCompile).configureEach {
    it.options.encoding = "UTF-8"
    if (JavaVersion.current().isJava9Compatible()) {
        it.options.release = javaVersion.toInteger()
    }
}
```

The single `unimined.minecraft` call folding in a caller-supplied `loaderBlock` closure exists because the loader-specific block (`fabric { }`, `minecraftForge { }`) must be part of the same immediate apply. Two separate `unimined.minecraft` calls worked when the first was a lateApply, which a node cannot use.

- [ ] **Step 4: Convert fabric/build.gradle**

Replace everything from the `plugins` block to the end of the `dependencies` block. The head becomes:

```groovy
plugins {
    id "com.github.johnrengelman.shadow" version "8.0.0"
}

ext.loaderBlock = {
    fabric {
        loader ext.loaderVersion
    }
}

apply from: rootProject.file('gradle/loader-conventions.gradle')
if (!loaderEnabled) {
    return
}

archivesBaseName = archivesBaseName + "-fabric"

configurations {
    common
    shadowCommon
    compileClasspath.extendsFrom common
    runtimeClasspath.extendsFrom common
}

dependencies {
    for (sourceSet in commonNode.sourceSets) {
        if (sourceSet == commonNode.sourceSets.test) continue
        if (sourceSet == commonNode.sourceSets.schematica_api) continue
        common sourceSet.output
        shadowCommon sourceSet.output
    }
    include "dev.babbaj:nether-pathfinder:${rootProject.nether_pathfinder_version}"
}
```

`ext.loaderBlock` must be set BEFORE the `apply from:`, because the conventions script reads it during its own `unimined.minecraft` call.

Then in the same file change `processResources` to use the node's version rather than root's:

```groovy
processResources {
    inputs.property "version", project.version
    inputs.property "minecraft_version", nodeVersion

    filesMatching("fabric.mod.json") {
        expand "version": project.version, "minecraft_version": nodeVersion
    }
}
```

Leave `shadowJar`, `remapJar`, `jar`, `components.java`, `proguard`, `createDist`, `build.finalizedBy` and `publishing` exactly as they are, except the publishing `artifactId`, which must not collide between nodes:

```groovy
            artifactId = rootProject.archives_base_name + "-" + loaderName + "-" + nodeVersion
```

- [ ] **Step 5: Delete root's active-version machinery**

In `build.gradle`, delete the `activeVersionMatcher` block, the `activeVersionProps` loading loop, the `rootProject.ext.active_loaders` assignment and the entire `allprojects { }` block. Keep the license header. Replace the explanatory comment block with a single line stating what root now is:

```groovy
// Root is a pure aggregator. Shared code lives in the Stonecutter node ':common:<version>';
// each loader is its own Stonecutter dimension configured by gradle/loader-conventions.gradle.
```

- [ ] **Step 6: Convert the other three loader scripts the same way**

Apply the identical head shape to `forge/build.gradle`, `neoforge/build.gradle` and `tweaker/build.gradle`. Their `ext.loaderBlock` closures are:

```groovy
// forge
ext.loaderBlock = {
    minecraftForge {
        loader ext.loaderVersion
        mixinConfig ["mixins.baritone.json"]
    }
}
```

```groovy
// neoforge
ext.loaderBlock = {
    neoForge {
        loader ext.loaderVersion
        mixinConfig ["mixins.baritone.json"]
    }
    minecraftRemapper.config {
        ignoreConflicts(true)
    }
}
```

```groovy
// tweaker
ext.loaderBlock = {
    runs {
        config("client") {
            mainClass = "net.minecraft.launchwrapper.Launch"
            args.addAll(["--tweakClass", "baritone.launch.tweaker.BaritoneTweaker"])
        }
    }
}
```

Keep each script's own `archivesBaseName` suffix, `processResources` target, manifest attributes, extra dependencies (tweaker's mixin, asm and launchwrapper set) and `proguard` / `createDist` `compType`. `tweaker` sets no `archivesBaseName` suffix, matching today.

Each script's `dependencies` block must use `commonNode` and `rootProject.nether_pathfinder_version`. Forge, neoforge and tweaker put nether-pathfinder on `shadowCommon`, not `include`; preserve that difference.

- [ ] **Step 7: Prove unimined configures on a node, the open question**

```bash
./gradlew :fabric:1.21.11:build 2>&1 | tail -30
```

Expected: BUILD SUCCESSFUL. If it fails with "minecraft config never applied for source set 'main'", the immediate-apply fix is insufficient for a loader node and this is the stall point the spec's first risk names. Stop and report the full stack rather than trying variations blindly.

Then confirm the jar exists and is not the dev jar:

```bash
ls -la fabric/versions/1.21.11/build/libs/
```

- [ ] **Step 8: Prove the other version node builds**

```bash
./gradlew :fabric:1.21.10:build 2>&1 | tail -30
ls -la fabric/versions/1.21.10/build/libs/
```

Expected: BUILD SUCCESSFUL and a jar. Confirm its metadata carries the right version:

```bash
unzip -p fabric/versions/1.21.10/build/libs/*.jar fabric.mod.json | grep -A3 '"depends"'
```

Expected: `"minecraft": ["1.21.10"]`. This is Task 2 paying off; if it says 1.21.11 the expand is keyed on the wrong version.

- [ ] **Step 9: The acceptance measurement, one invocation for both versions**

```bash
./gradlew build 2>&1 | tail -20
find . -path "*/versions/*/build/libs/*.jar" -not -path "./common/*" | sort
```

Expected: jars under BOTH `fabric/versions/1.21.10` and `fabric/versions/1.21.11`, plus whichever of forge, neoforge and tweaker configure. This is SP-3's blocker measurably gone. Record the exact list; it is the input to Task 5 and the evidence for the handoff.

- [ ] **Step 10: Confirm no regression on :common**

```bash
./gradlew :common:1.21.10:build :common:1.21.11:build 2>&1 | tail -10
```

Expected: BUILD SUCCESSFUL. This is the one thing that worked before this task and must still work.

- [ ] **Step 11: Commit**

```bash
git add settings.gradle build.gradle gradle/loader-conventions.gradle fabric forge neoforge tweaker
git commit -m "build(loaders): make each loader a stonecutter version dimension"
```

---

### Task 4: Fold the remaining loader duplication into the conventions script

After Task 3 the four loader scripts still repeat the `configurations` block, the common-outputs bundling loop, `shadowJar`, `remapJar`, `jar`, `proguard`, `createDist` and `publishing`. This task removes that repetition. It is a pure refactor: the set of produced jars must be byte-for-byte identical in name and count before and after.

**Files:**
- Modify: `gradle/loader-conventions.gradle`
- Modify: `fabric/build.gradle`, `forge/build.gradle`, `neoforge/build.gradle`, `tweaker/build.gradle`

**Interfaces:**
- Consumes: everything Task 3's conventions script produces.
- Produces: the conventions script additionally creates the `common` and `shadowCommon` configurations, the `shadowJar` / `remapJar` / `jar` wiring, the `proguard` and `createDist` tasks and the `publishing` block. Loader scripts keep only `ext.loaderBlock`, `archivesBaseName`, `processResources`, manifest attributes and any extra dependencies.

- [ ] **Step 1: Record the reference jar list**

```bash
./gradlew clean build 2>&1 | tail -5
find . -path "*/versions/*/build/libs/*.jar" -not -path "./common/*" | sort > /tmp/jars-before.txt
cat /tmp/jars-before.txt
```

- [ ] **Step 2: Move the shared blocks into the conventions script**

Append to `gradle/loader-conventions.gradle`, after the `unimined.minecraft` call:

```groovy
configurations {
    common
    shadowCommon
    compileClasspath.extendsFrom common
    runtimeClasspath.extendsFrom common
}

dependencies {
    for (sourceSet in commonNode.sourceSets) {
        if (sourceSet == commonNode.sourceSets.test) continue
        if (sourceSet == commonNode.sourceSets.schematica_api) continue
        common sourceSet.output
        shadowCommon sourceSet.output
    }
}

shadowJar {
    configurations = [project.configurations.shadowCommon]
    archiveClassifier.set "dev-shadow"
}

remapJar {
    inputFile.set shadowJar.archiveFile
    dependsOn shadowJar
    archiveClassifier.set null
}

jar {
    archiveClassifier.set "dev"
}

components.java {
    withVariantsFromConfiguration(project.configurations.shadowRuntimeElements) {
        skip()
    }
}

task proguard(type: baritone.gradle.task.ProguardTask) {
    proguardVersion "7.4.2"
    compType loaderName
}

task createDist(type: baritone.gradle.task.CreateDistTask, dependsOn: proguard) {
    compType loaderName
}

build.finalizedBy(createDist)

publishing {
    publications {
        mavenLoader(MavenPublication) {
            artifactId = rootProject.archives_base_name + "-" + loaderName + "-" + nodeVersion
            from components.java
        }
    }
    repositories {
    }
}
```

Note two behaviour changes to verify, not assume:
- `compType` was hardcoded per script and is now `loaderName`. For fabric, forge and neoforge that is the same string. For `tweaker` the old script passed NO `compType` to either task. Check `ProguardTask` and `CreateDistTask` for how they treat it before assuming `"tweaker"` is safe; if it is not, keep tweaker's `proguard` and `createDist` in its own script and guard these two task registrations with `if (loaderName != 'tweaker')`.
- The publication was named `mavenFabric` in three scripts and `mavenCommon` in tweaker, with tweaker using a bare `archivesBaseName` artifactId. Publication names are local to a project, so one name is fine, but tweaker's artifactId changes. That is a correctness improvement, since two nodes would otherwise publish the same coordinate, but note it.

- [ ] **Step 3: Reduce each loader script to what differs**

Delete the moved blocks from all four loader scripts. `fabric/build.gradle` should end up close to:

```groovy
plugins {
    id "com.github.johnrengelman.shadow" version "8.0.0"
}

ext.loaderBlock = {
    fabric {
        loader ext.loaderVersion
    }
}

apply from: rootProject.file('gradle/loader-conventions.gradle')
if (!loaderEnabled) {
    return
}

archivesBaseName = archivesBaseName + "-fabric"

dependencies {
    include "dev.babbaj:nether-pathfinder:${rootProject.nether_pathfinder_version}"
}

processResources {
    inputs.property "version", project.version
    inputs.property "minecraft_version", nodeVersion

    filesMatching("fabric.mod.json") {
        expand "version": project.version, "minecraft_version": nodeVersion
    }
}
```

Forge, neoforge and tweaker keep their manifest attributes block and their own extra dependencies on top of this shape.

- [ ] **Step 4: Prove the refactor changed nothing**

```bash
./gradlew clean build 2>&1 | tail -5
find . -path "*/versions/*/build/libs/*.jar" -not -path "./common/*" | sort > /tmp/jars-after.txt
diff /tmp/jars-before.txt /tmp/jars-after.txt && echo "IDENTICAL JAR SET"
```

Expected: `IDENTICAL JAR SET`. Any difference means the refactor changed behaviour; investigate before committing.

- [ ] **Step 5: Commit**

```bash
git add gradle/loader-conventions.gradle fabric forge neoforge tweaker
git commit -m "build(loaders): hoist the shared loader script into one conventions file"
```

---

### Task 5: Assemble the Nylium universal jar

**Files:**
- Create: `universal/build.gradle`
- Modify: `settings.gradle` (one `include`)

**Interfaces:**
- Consumes: Task 1's mavenLocal publication; the `remapJar` task of every loader node Task 3 proved builds.
- Produces: the `:universal:nyliumUniversalJar` task and its output jar.

- [ ] **Step 1: Include the project and add mavenLocal to plugin resolution**

In `settings.gradle`, add `include('universal')` next to the loader loop, and confirm `mavenLocal()` is already first in the `pluginManagement.repositories` block. It is, so no change is needed there; verify rather than assume.

`:universal` is NOT registered with Stonecutter. There is exactly one universal jar.

- [ ] **Step 2: Write the universal build script**

Create `universal/build.gradle`. Declare a module only for the (loader, version) pairs Task 3 Step 9 actually produced. The example below assumes Fabric on both versions plus Forge on both; delete any module whose jar did not build and add any that did.

```groovy
plugins {
    id 'io.github.intisy.nylium' version '0.1.0-SNAPSHOT'
}

nylium {
    mod {
        id      = 'baritone'
        name    = 'Baritone'
        version = rootProject.mod_version
    }

    module('fabric-1.21.11') {
        jar        = project(':fabric:1.21.11').tasks.named('remapJar').flatMap { it.archiveFile }
        platforms  = ['FABRIC']
        minecraft  = '1.21.11'
        mixins     = ['mixins.baritone.json']
    }

    module('fabric-1.21.10') {
        jar        = project(':fabric:1.21.10').tasks.named('remapJar').flatMap { it.archiveFile }
        platforms  = ['FABRIC']
        minecraft  = '1.21.10'
        mixins     = ['mixins.baritone.json']
    }
}
```

No `entrypoint` is declared: Baritone's `fabric.mod.json` carries an empty entrypoints block and works purely through mixins, and Nylium's `ManifestRenderer` null-checks the field.

- [ ] **Step 3: Confirm the plugin resolves before writing more**

```bash
./gradlew :universal:tasks --all 2>&1 | grep -i nylium
```

Expected: a `nyliumUniversalJar` task is listed. If the plugin fails to resolve, re-check Task 1 Step 4's marker artifact rather than editing the version string.

- [ ] **Step 4: Build the universal jar**

```bash
./gradlew :universal:nyliumUniversalJar 2>&1 | tail -20
ls -la universal/build/libs/
```

Expected: exactly one jar.

- [ ] **Step 5: Commit**

```bash
git add settings.gradle universal
git commit -m "build(universal): assemble a nylium universal jar from the loader nodes"
```

---

### Task 6: Verify the universal jar carries what it claims

A jar that builds proves nothing about its contents. Nylium's own handoff records several green results that meant nothing.

**Files:** none. This task only measures.

**Interfaces:**
- Consumes: Task 5's jar.
- Produces: the measured module set and dedupe ratio, both of which Task 7 writes into the handoff.

- [ ] **Step 1: Read the module manifest out of the jar**

```bash
cd "F:/Documents/GitHub/intisy/minecraft/mods/baritone"
unzip -l universal/build/libs/*.jar | head -40
unzip -p universal/build/libs/*.jar META-INF/nylium/modules.properties 2>/dev/null \
  || unzip -l universal/build/libs/*.jar | grep -i nylium
```

Expected: one entry per declared module, with the platform and Minecraft version each declared. If the manifest path differs, find it from the listing rather than guessing; Nylium's `ManifestRenderer` is the authority.

- [ ] **Step 2: Confirm the object store is present, meaning dedupe ran**

```bash
unzip -l universal/build/libs/*.jar | grep -ciE "objects/|blob" || echo "NO OBJECT STORE"
```

Expected: a non-zero count. Dedupe is on by default for two or more modules. `NO OBJECT STORE` means it silently did not run.

- [ ] **Step 3: Measure deduped against undeduped**

Temporarily add `dedupe = false` inside the `nylium { }` block, rebuild to a copy, then restore.

```bash
cp universal/build/libs/*.jar /tmp/universal-deduped.jar
# add `dedupe = false` to universal/build.gradle inside the nylium block
./gradlew :universal:nyliumUniversalJar --rerun-tasks 2>&1 | tail -5
cp universal/build/libs/*.jar /tmp/universal-undeduped.jar
# remove `dedupe = false` again
./gradlew :universal:nyliumUniversalJar --rerun-tasks 2>&1 | tail -5
stat -c "%n %s" /tmp/universal-deduped.jar /tmp/universal-undeduped.jar
```

Record both byte counts and the percentage. Nylium measured 33.7 percent on Baritone's two `common` node jars; the figure here covers whole loader jars and will differ. Report what is measured, not what was expected.

- [ ] **Step 4: Confirm universal/build.gradle is back to dedupe-on**

```bash
grep -n "dedupe" universal/build.gradle || echo "no dedupe override, correct"
git diff --stat
```

Expected: no diff in `universal/build.gradle`. If `dedupe = false` was left behind, the shipped jar is the wrong one.

- [ ] **Step 5: No commit**

Nothing changed. Do not create an empty commit.

---

### Task 7: Update both handoffs

**Files:**
- Modify: `docs/superpowers/HANDOFF.md` (baritone)
- Modify: `F:\Documents\GitHub\intisy\minecraft\mods\Nylium\docs\superpowers\HANDOFF.md`

**Interfaces:**
- Consumes: the measurements from Task 3 Step 9 and Task 6.

- [ ] **Step 1: Update the baritone handoff**

Replace the "SP-3 blocker, and the spike that answered it" section with what actually landed: loaders are Stonecutter dimensions, root is a pure aggregator, `gradle/loader-conventions.gradle` owns the shared config. State the measured module set and the dedupe figure from Task 6. Keep the branch-deletion safety table untouched; it is still live and still says most branches are unsafe to delete.

Add any trap discovered during execution. Candidates seen while planning, to keep only if they actually bit:
- `ext.loaderBlock` must be set before `apply from:`, or the loader-specific unimined block is silently skipped and the jar has no loader metadata.
- `return` inside an applied script does not return from the applying script, which is why the conventions script sets `ext.loaderEnabled` and the caller must check it.

- [ ] **Step 2: Update the Nylium handoff**

In the "What comes next" section, change the SP-3 entry from blocked to whatever is now true, naming Baritone as the second real consumer. That matters for the open question in "Pending decisions that are the owner's": retiring `nylium-testmod`'s hand-rolled `universalJar` was held until a second consumer existed.

- [ ] **Step 3: Commit both**

```bash
cd "F:/Documents/GitHub/intisy/minecraft/mods/baritone"
git add docs/superpowers/HANDOFF.md
git commit -m "docs(handoff): record loaders as stonecutter nodes and the universal jar"

cd "F:/Documents/GitHub/intisy/minecraft/mods/Nylium"
git add docs/superpowers/HANDOFF.md
git commit -m "docs(handoff): record baritone as the second real consumer"
```

---

## Deviations found while executing Task 3

Recorded 2026-09-08. The plan above is left as written; these are what actually differed.

1. **`create()` takes the loader list, not five literals.** `settings.gradle` uses
   `create([project(':common')] + available_loaders.split(",").collect { project(":${it.trim()}") })`,
   the `Iterable` overload, so the loader list is not duplicated between the include loop and the
   `create` call.
2. **`ext.loaderBlock` takes the loader version as a parameter.** Referencing `ext.loaderVersion`
   from inside the closure is unsafe, because with `DELEGATE_FIRST` the delegate is unimined's
   config object rather than the project. The closure signature is `{ loaderVersion -> ... }` and
   the conventions script calls `loaderBlock(loaderVersion)`.
3. **`loaderBlock` and `loaderVersion` are captured into locals** before the `unimined.minecraft`
   closure, for the same delegate reason. Reading `ext.has('loaderBlock')` inside the closure
   resolves against unimined's config, not the project.
4. **parchmentmc had to be scoped, which the plan did not foresee.** `maven.parchmentmc.net` and
   `maven.parchmentmc.org` (same IP) were unreachable, and Gradle probes every declared repository
   for a cache miss, so an unrelated miss on the synthesized `net.minecraft:minecraft_fabric_1.21.10`
   coordinate timed out and failed resolution outright. unimined adds its own parchmentmc
   repository, so the fix is a `repositories.whenObjectAdded` hook applying
   `content { includeGroup "org.parchmentmc.data" }` to any parchmentmc repository as it is added.
   Both parchment mapping versions were already cached, so nothing needed downloading from that
   host. This is a latent fragility in the existing build, not something the conversion introduced;
   `common/build.gradle` declares the same unscoped repository and would hit it on a cold cache.
5. **`ProguardTask` needs a `java_version` project property.** It calls
   `getProject().findProperty("java_version")`, which used to resolve through root's `ext` and now
   resolves to null on a node. The conventions script sets `ext.java_version`.
6. **The `loaderEnabled` gate was wrong and is gone.** Task 3 Step 9's full build failed on
   `:neoforge:1.21.10:compileJava` with missing `net.neoforged` packages, even though 1.21.10 does
   not list neoforge and the gate fired correctly. A loader script's `plugins { shadow }` block
   necessarily precedes any gate, and shadow applies the java plugin, so a skipped node still
   compiled loader source against a classpath with no loader on it. The fix is structural: each
   loader is registered over only the versions that declare it, using the single-project
   `create(Object, Action)` overload, so `:neoforge:1.21.10` is never created. `ext.loaderEnabled`
   and the four `if (!loaderEnabled) return` lines are deleted. This also means the plan's
   `available_loaders` gate in the conventions script, Task 3 Step 3 item 3, does not exist.

## Deviations to report rather than absorb

Stop and report, do not work around, if any of these happen:

- `kotlinController = false` does not prevent `.gradle.kts` controllers (Task 3 Step 2).
- unimined still reports "minecraft config never applied for source set 'main'" on a loader node after immediate apply (Task 3 Step 7). This is the spec's named stall point.
- The Nylium plugin marker artifact is missing from mavenLocal (Task 1 Step 4).
- The jar set differs before and after Task 4's refactor (Task 4 Step 4).
- The universal jar contains no object store (Task 6 Step 2).

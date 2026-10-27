# Research D: developer clutter, the Noo-Noo knowledge base

**Summary.** This file is the clutter catalog for Noo-Noo in MinMacs 2.0, tracked in FRIKKern/minmacs#4. It has 52 rows, one per kind of clutter, with the same fields for each: path patterns, how to size it, whether it is safe to remove, what rebuilds it, how to find its owner and the tool's own cleanup command. The rows are repeated as JSON at the end of the file.

On this Mac, du counts about 178 GiB of developer clutter. The data volume holds 335 GiB. The du count is too high in two big places:
- On macOS, pnpm clones packages out of its store, so the 54 GiB that du reports for 447 `node_modules` folders shares physical blocks with the pnpm store. The store folder is 19 GiB by du, but it holds three store layouts, and the one projects here name, `v11`, is 5.48 GiB.
- The 8 leaked Chrome code-sign clones show as 12 GiB but share most of their blocks.

Real reclaimable space needs the extent-union sizer that Noo-Noo already has. The rest of this file explains each of these points.

Every measurement was taken read-only on 2026-10-27 with `du -sk`, `ls`, `stat`, `plutil -p`, `df -k`, `xcrun simctl … list` and `brew cleanup -n`. The intermediate output is in `/private/tmp/claude-501/-Users-frikk-jarl-Documents-GitHub/ed8e842b-dd11-47b1-8a32-0ea5188ceb22/scratchpad/d-clutter/`. All sizes are KiB from du, converted to GiB by dividing by 1,048,576.

**One side effect to report.** Running `yarn cache dir` started Corepack. Corepack printed "Corepack is about to download https://registry.yarnpkg.com/yarn/-/yarn-1.22.22.tgz" (unverified: the printed text was not kept) and wrote `~/.cache/node/corepack/v1/yarn/1.22.22`, dated 27 Oct 16:05 by `ls -la`. That was a network read and a cache write the task did not intend. Nothing else was written outside the scratchpad and this file. Noo-Noo should note the lesson: asking a package manager for its cache path can install things. The catalog therefore reads paths from files and env vars, never by running the tool.

## 1. What Noo-Noo 0.7 already knows

The Go code in the noo-noo clone at `scratchpad/family/noo-noo` (HEAD `1e6dc60`) holds most of the doctrine 2.0 should port.

- **Three sizing tiers.** `internal/sizer/sizer.go:9-26` names them:
  - `Blocks`: the sum of st_blocks×512, with hardlinks counted once. This matches du.
  - `UniqueAllocated`: the union of physical extents from `fcntl(F_LOG2PHYS_EXT)`, keyed by `(st_dev, devoffset)`. It counts each clone-shared extent once and skips sparse holes.
  - `FreedByDelete`: the change in statfs free bytes before and after an action.
- **Sizing cost.** `sizer.go:28-35` measured `UniqueAllocated` at about 34 µs per file, or 197k files in 6.7 s. It is therefore used only on demand, for a tree Noo-Noo is about to make a claim about.
- **The founding incident.** du put 65 Chrome `code_sign_clone` folders at 129 GB. Deleting 64 of them freed about 3 GB (`sizer.go:4-7`, `internal/leaks/leaks.go:4-9`).
- **Leak signatures as data.** `internal/leaks/leaks.go:166-276` defines four signatures:
  - `chrome-code-sign-clone`, stale when lsof shows no open files, with a launch-causality rule for hardlink aliases.
  - `private-tmp-agent-scratch`: a session is checked for life by its `--session-id` process and by a transcript written in the last 30 minutes. It is stale 1 hour after the session dies. Entries inside a live session go after 24 hours idle.
  - `darwin-t-agent-trial`, stale after 12 hours idle with nothing open.
  - `temp-family`: at least 5 siblings after the random suffix is stripped, 12 hours idle, nothing open, and never anything with the `com.apple.` prefix.
- **Safety walls.** `internal/core/safety.go:32-56` blocks `/System/ /Library/ /usr/ /bin/ /sbin/ /private/` for general deletes. A narrower gate for leak signatures allows `/private/var/folders` and `/private/tmp`, but keeps `/private/etc` blocked. Its path matching ignores case (`safety.go:46-48`).
- **Cache targets.** `internal/cli/caches_cmd.go:20-56` lists 14 paths under `~/Library/Caches` and `~/Library/Developer/CoreSimulator/Caches/dyld`, plus a glob for `*.ShipIt`. The Trash is sized but never cleaned (`caches_cmd.go:68-73`).
- **Build output.** `internal/modules/dev/dev.go:17-24` targets `node_modules .next .turbo .cache dist build`, and pruning nested matches avoids counting them twice.
- **Orphaned app data.** `internal/modules/orphanapps/orphanapps.go:53-77` flags a folder at 50 MB or more that has been idle 30 days. A never-flag list keeps toolchain caches out of that module.
- **Offload playbooks.** `internal/modules/offload/playbook.go:98-174` covers `pnpm-store`, `colima`, `claude-config`, `claude-jobs`, `localwp-blueprints` (never delete), `claude-vm-bundles` and generic Electron data.

## 2. Sizing on APFS: what this Mac shows

1. **pnpm clones on macOS. It does not hardlink.** The pnpm docs say `packageImportMethod` defaults to `auto`, which tries "cloning before hardlinking on macOS" (https://pnpm.io/settings/node-modules). On this Mac, `stat -f "%l"` on a file in `barkpark/node_modules/.pnpm/…/package.json` shows 1 link, so the file is a clone or a copy, not a hardlink. `barkpark/node_modules/.modules.yaml:3982` names the store as `~/Library/pnpm/store/v11`.
   - du dedupes hardlinks but cannot see clones. The per-folder du sum for `node_modules` is therefore an upper bound.
   - Removing a worktree's `node_modules` frees only the extents that neither the store nor another clone uses.
   - Guess: most of the 53.78 GiB is shared with the store. Only `UniqueAllocated` or a statfs delta can say how much.
   - `~/Library/pnpm/store` is 19.14 GiB by du, split into `v3` 2.33 GiB, `v10` 11.22 GiB and `v11` 5.48 GiB (`du -sk ~/Library/pnpm/store/*`). barkpark's `.modules.yaml` names only `v11`. Guess: `v3` and `v10` are left from older pnpm versions.
2. **bun clones too.** "Bun uses `clonefile` on macOS" (https://bun.com/docs/pm/global-cache). The same rule applies.
3. **The Chrome code-sign clones on this Mac.**
   - `/private/var/folders/kd/…/X/com.google.Chrome.code_sign_clone` holds 8 `code_sign_clone.??????` folders, and du puts them at 11.94 GiB.
   - Seven clones are about 1.4 GiB each by du, and one is 2.1 GiB. Guess: the unique bytes are close to one clone's size, since the incident in `sizer.go:4-7` freed about 3 GB from 129 GB.
4. **Sparse disk images.** Docker's FAQ says "many tools report the maximum file size, not the actual file size" and suggests `ls -klsh Docker.raw` (https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/). OrbStack's `data.img` shows an apparent size of 8 TB but "only takes as much space as you use" (https://docs.orbstack.dev/faq). Noo-Noo should size these with st_blocks or extents, never st_size (`orphanapps.go:8-9`).
5. **Mounted simulator runtimes.**
   - du on `/Library/Developer/CoreSimulator` reports 19.47 GiB. Of that, 15.63 GiB is `Volumes/iOS_23B80`, which `mount` shows as a read-only, sealed APFS mount of `/dev/disk5s1`.
   - `xcrun simctl runtime list` puts the same runtime at "Total Disk Images: 1 (7.8G)".
   - Size runtimes from `simctl runtime list -j` and never walk the mount. A walk of `/Library/Developer` also needs `du -x`, or it crosses into the mount.
6. **Hugging Face sizes.** Per-repo sizes "stay logical, so a shared file is counted for every repo that uses it. The cache-wide `size_on_disk` is physical" (https://huggingface.co/docs/huggingface_hub/guides/manage-cache).
7. **uv already measures clones.** `uv cache clean --preview-features cache-physical-space` "accounts for hardlinks and copy-on-write clones" (https://docs.astral.sh/uv/concepts/cache/).

## 3. The catalog

Safety classes used below:
- **cache**: regenerable data that a known tool owns. The Trash is fine.
- **tool**: use only the tool's own command. Moving the folder by hand can break the tool.
- **build**: project build output. It needs an owner check first: is the project finished, and does nothing hold it open.
- **data**: user data or state. Report it, never act on it.
- **leak**: a Noo-Noo leak signature with liveness gates.

### Apple

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| Xcode DerivedData | `~/Library/Developer/Xcode/DerivedData/<Name>-<hash>/`, plus `ModuleCache.noindex`, `CompilationCache.noindex`, `SymbolCache.noindex`, `SDKStatCaches.noindex` | 0.12 GiB in 18 project folders, 17 of them `Unsaved_Xcode_Document*` | build. A tutorial says everything inside is safe and the next build is slower (https://www.kodeco.com/19998365-understanding-and-managing-xcode-space). Apple's own page was not found: developer.apple.com/documentation/xcode/managing-storage-used-by-xcode returned 404 | One full rebuild per project | `info.plist` in each folder has `WorkspacePath` and `LastAccessedDate`; `plutil -p` showed `~/Desktop/test/test.xcodeproj` | None from Apple. Delete in Finder, or pass `xcodebuild -derivedDataPath` |
| Xcode archives | `~/Library/Developer/Xcode/Archives/<date>/*.xcarchive` | absent | data. Archives hold dSYMs for shipped builds. Guess: losing them loses crash symbolication | Cannot be rebuilt for a past release | `Info.plist` inside each `.xcarchive`. Guess: it names the app and version | Xcode Organizer |
| Device support | `~/Library/Developer/Xcode/{iOS,watchOS,tvOS,macOS,visionOS} DeviceSupport/<version> (<build>)` | absent | cache. Xcode rebuilds what it needs when a device of that OS version connects (kodeco, above) (unverified: the fetched kodeco text does not say this) | Several minutes the next time that device connects | Folder name = OS version and build | None. Delete old versions by hand |
| Simulator devices | `~/Library/Developer/CoreSimulator/Devices/<UDID>/` | 3.70 GiB; 12 entries under Devices | tool. "Specifying unavailable will delete devices that are not supported by the current Xcode SDK" (`xcrun simctl delete` help, run here) | Apps and data inside the simulator are lost | `device.plist` has `name`, `runtime` and `lastBootedAt`; one read showed iPhone 16e, iOS-26-1, last booted 2025-11-10 | `xcrun simctl delete unavailable`, `xcrun simctl erase <udid>` |
| Simulator runtimes | `simctl runtime list` disk images, mounted at `/Library/Developer/CoreSimulator/Volumes/<name>` | 7.8G per simctl; 15.63 GiB if du walks the mount | tool. `simctl runtime delete (<identifier>\|--notUsedSinceDays <days>) [--dry-run]` (`xcrun simctl runtime` help, run here) | A multi-GB download | `simctl runtime list -j`; each device's `runtime` key | `xcrun simctl runtime delete --notUsedSinceDays 90 --dry-run` |
| Simulator dyld cache | `/Library/Developer/CoreSimulator/Caches/dyld/` on this Mac; Noo-Noo 0.7 targets `~/Library/Developer/CoreSimulator/Caches/dyld` | 3.84 GiB under `/Library`; 0 under `~/Library` | cache. Rebuilt "on the next simulator boot" (`caches_cmd.go:36-38`). It is owned by root:wheel here (`ls -la`), so Noo-Noo's user target misses it and `safety.go:34` blocks `/Library/` | One slow simulator boot | The runtime build in the subfolder name. Guess | None |

### Android and JVM

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| Android SDK | `~/Library/Android/sdk/{system-images,platforms,build-tools,emulator}`, `~/.android/avd/*.avd` | absent | tool. Guess: remove items through the sdkmanager | A large download | AVD `config.ini`. Guess | `sdkmanager --uninstall <pkg>`, `avdmanager delete avd -n <name>`. Guess: not checked against a source |
| Gradle user home | `~/.gradle/caches`, `~/.gradle/wrapper/dists`, `~/.gradle/daemon` | absent | cache. "Gradle automatically cleans its caches." It removes downloaded resources after 30 days unused and created resources after 7 days (https://docs.gradle.org/current/userguide/directory_layout.html) | Downloads again | Global. A project's `gradle/wrapper/gradle-wrapper.properties` pins its dist | Automatic. `GRADLE_USER_HOME` moves it |
| Gradle project | `<project>/.gradle/`, `<project>/build/`, `<project>/app/build/` | none found | build. The docs call them "transient files … for incremental builds" (same URL). Project `.gradle/<version>` folders are cleaned after 7 days unused | One full build | The nearest `settings.gradle(.kts)` | `./gradlew clean` |
| CocoaPods | `~/Library/Caches/CocoaPods/`, `<project>/Pods/` | absent | cache. `pod cache clean [NAME] --all` (https://guides.cocoapods.org/terminal/commands.html) | `pod install` downloads again | `Podfile.lock` next to `Pods/` | `pod cache clean --all` |
| Maven | `~/.m2/repository/` | absent | cache. `dependency:purge-local-repository` removes a project's dependencies and re-resolves them by default (https://maven.apache.org/plugins/maven-dependency-plugin/purge-local-repository-mojo.html) | Downloads again | Global. Group and artifact are in the path | `mvn dependency:purge-local-repository` |

### JavaScript

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| npm cache | `~/.npm/_cacache`, `~/.npm/_npx/<hash>`, `~/.npm/_logs` | 0.67 GiB, of which `_cacache` is 0.55 and `_npx` 0.12 | cache. Clearing is "typically unnecessary" and needed only "for reclaiming disk space"; clean "requires `--force`" (https://docs.npmjs.com/cli/v10/commands/npm-cache) | Downloads again | Global. Each `_npx/<hash>/package.json` names the packages | `npm cache clean --force` |
| pnpm store | `~/Library/pnpm/store/v<N>/` on this Mac (`.modules.yaml:3982`) | 19.14 GiB for `store` in all: `v3` 2.33, `v10` 11.22, `v11` 5.48. `~/Library/pnpm` is 20.26 GiB in all | tool. `pnpm store prune` "is not harmful and has no side effects on your projects" (https://pnpm.io/cli/store) | Pruned packages download again on the next install | Each project's `node_modules/.modules.yaml` `storeDir` | `pnpm store prune` |
| pnpm metadata cache | `~/Library/Caches/pnpm/` | 1.00 GiB | cache. `store prune` "removes the package metadata cache (`metadata*` directories)" (pnpm.io/cli/store) | Re-fetched | Global | `pnpm store prune` |
| Yarn | Classic: `~/Library/Caches/Yarn/v6`. Berry: `~/.yarn/berry/cache` and `<project>/.yarn/cache` | 0 | cache. `yarn cache clean` "will remove all the files from the cache"; `--mirror` cleans the global cache instead of the local one, and `--all` cleans both (https://yarnpkg.com/cli/cache/clean) | Downloads again. A committed `.yarn/cache` is project data and must not be touched | `.yarnrc.yml` in the project | `yarn cache clean [--mirror\|--all]` |
| bun | `~/.bun/install/cache` | absent | cache, at the path from https://bun.com/docs/pm/global-cache. That page does not give a clean command | Downloads again | Global | `bun pm cache rm`. Guess: not on the fetched page |
| Playwright browsers | `~/Library/Caches/ms-playwright/<browser>-<rev>/`, plus `.links/<hash>`, a file holding an install path | 2.48 GiB: 4 chromium, 4 headless shell and 2 webkit revisions | cache. Playwright deletes a version when no client needs it any more, and `npx playwright uninstall --all` removes them (https://playwright.dev/docs/browsers) | A 170–370 MB download per browser revision here | `.links` files: 3 of the 6 point at missing paths (`client-app-boundary`, `client-app-chat`, an `_npx` folder); one points into a Claude scratchpad | `npx playwright uninstall [--all]` |
| Puppeteer browsers | `~/.cache/puppeteer/` | absent | cache, at that path "starting in v19.0.0" (https://pptr.dev/guides/configuration) | Downloads again | None recorded. Guess | `npx @puppeteer/browsers clear`. Guess: not on the fetched page |
| node_modules | `**/node_modules`, pruned at the first match (`dev.go:40-66`) | 53.78 GiB by per-folder du over 447 folders under `~/Documents/GitHub`; 18.25 GiB of it sits in worktree folders whose path contains `worktrees`. Clones make this an upper bound (section 2) | build | `pnpm install` from the store: seconds with a warm store | The `package.json` next to it. Then the repo or worktree: walk up to the `.git` folder or `.git` file. WorkForest tells merged from stale | Delete the folder; the package manager rebuilds it |
| Next.js `.next` | `**/.next` | 32.53 GiB in 55 folders; the largest is `client-web/apps/web/.next` at 5.01 GiB | build. Guess: `.next/cache` is reused between builds and the rest is the build output | A full `next build`: minutes | The `next.config.*` next to it | None. Delete the folder |
| Turborepo `.turbo` | `**/.turbo` | 0.04 GiB in 164 folders | build. Guess: a local task cache that turbo rebuilds | Tasks run again | `turbo.json` at the repo root | None. Delete the folder |
| dist, build | `**/dist`, `**/build`, and only when a build manifest sits next to them | dist 0.14 GiB in 40 folders; build 0.01 GiB in 2 | build, but risky: some repos commit `dist` or `build`, and LocoHost and WorkForest keep their app in `build/` | One build | Check `git ls-files <dir>` before acting. A tracked folder is never clutter. Guess: the rule is reasoned, not sourced | The project's own clean script |

### Python

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| pip | `~/Library/Caches/pip` (from `pip3 cache dir`) | 0.08 GiB | cache. `pip cache purge` will "Remove all items from the cache" (https://pip.pypa.io/en/stable/cli/pip_cache/) | Downloads again | Global | `pip cache purge` |
| uv | `~/.cache/uv`, the path `uv cache dir` printed | absent | tool. "It's never safe to modify the cache directly"; `uv cache prune` is "safe to run periodically" (https://docs.astral.sh/uv/concepts/cache/) | Downloads again | Global | `uv cache prune`, `uv cache clean` |
| poetry | `~/Library/Caches/pypoetry` (Guess: from Noo-Noo's never-flag list, `orphanapps.go:74`) | absent | cache. `poetry cache clear --all` (https://python-poetry.org/docs/cli/) | Downloads again | Global | `poetry cache clear PyPI --all` |
| conda | `~/miniconda3/pkgs`, `~/anaconda3/pkgs`, `~/.conda` | absent | tool. `conda clean --all` removes index cache, unused packages, tarballs, temp files and log files; `-f` "will break environments" that use symlinks (https://docs.conda.io/projects/conda/en/latest/commands/clean.html) | Downloads again | `conda info --envs` | `conda clean --all` |
| venv and caches | `**/.venv`, `**/__pycache__` | `__pycache__`: 50 folders, under 0.01 GiB; no `.venv` folders | build | `uv sync` or `pip install` | `pyproject.toml` next to it | Delete the folder |

### Rust, Go and Homebrew

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| cargo target | `**/target` next to a `Cargo.toml`, or `CARGO_TARGET_DIR` | none found | build. `cargo clean` with no options deletes "the entire target directory" (https://doc.rust-lang.org/cargo/commands/cargo-clean.html) | A full build: minutes | The workspace `Cargo.toml` | `cargo clean [--dry-run]` |
| cargo home | `~/.cargo/registry`, `~/.cargo/git` | absent | cache. Cargo deletes unused files itself, after 3 months for files from the network and 1 month for files it can regenerate (https://doc.rust-lang.org/cargo/reference/config.html) | Downloads again | Global | Automatic, set by `[cache] auto-clean-frequency` |
| Go build cache | `~/Library/Caches/go-build` (`go env GOCACHE`) | 2.91 GiB | cache. "The go command periodically deletes cached data that has not been used recently"; `go clean -cache` "deletes all cached data" (https://pkg.go.dev/cmd/go) | Slower next builds | Global | `go clean -cache` |
| Go module cache | `~/go/pkg/mod` (`go env GOMODCACHE`) | 1.46 GiB | tool. The cache "may be read-only" (pkg.go.dev/cmd/go). Here, `ls -ld` shows `dr-xr-xr-x` on `golang.org/x/crypto@v0.57.0`, so a plain `rm -rf` fails | Downloads again | Global. The module path is in the folder name | `go clean -modcache` |
| Homebrew | `~/Library/Caches/Homebrew` (`brew --cache`), old kegs in `/opt/homebrew/Cellar` | 0.30 GiB cache. Cellar is 2.00 GiB and Caskroom 0.46 GiB, but those are installed software. `brew cleanup -n` would free "approximately 507.5MB" | tool. `brew cleanup` removes downloads older than 120 days and old versions, and `--prune=all` removes all cache files. It runs on its own every 30 days after install or upgrade (https://docs.brew.sh/Manpage) | Downloads again | `brew list --versions` | `brew cleanup [--prune=all]` |

### Containers

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| Docker Desktop | `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw` | absent | tool. `docker system prune` removes stopped containers, unused networks, dangling images and build cache, and keeps volumes "to prevent important data from being deleted" (https://docs.docker.com/reference/cli/docker/system/prune/). Deleting files inside running containers does not free space (Docker macOS FAQ) | Images pull again. Volumes are data | Guess: the `com.docker.compose.project` label on containers and volumes | `docker system prune [-a] [--volumes]`, then `docker run --privileged --pid=host docker/desktop-reclaim-space` |
| Colima | `~/.colima` (`COLIMA_HOME`), `~/.colima/_lima` | absent | tool. Unused VM space is released when Colima starts (v0.5.0 and later); `colima delete --data` wipes the data disk (https://github.com/abiosoft/colima/blob/main/docs/FAQ.md) | Images pull again | Profile name | `docker system prune`, `colima ssh -- sudo fstrim -a` |
| OrbStack | `~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img` | absent | tool. The image is sparse and "automatically shrinks when you delete data" (https://docs.orbstack.dev/faq) | none | Machines and containers inside it | `docker system prune` inside it. `orb` commands were not checked |

### Editors

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| JetBrains | `~/Library/Caches/JetBrains/<product><version>`, `~/Library/Logs/JetBrains/<product><version>`, config under `~/Library/Application Support/JetBrains/<product><version>` | absent | cache for the caches and logs folders. A new major version deletes old caches and logs untouched for 180 days, and config folders are kept indefinitely (https://www.jetbrains.com/help/idea/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html) | Reindexing | The product and version in the folder name | Help, then Delete Leftover IDE Directories; File, then Invalidate Caches |
| VS Code | `~/Library/Application Support/Code/{Cache,CachedData,logs,User/workspaceStorage}`, `~/.vscode/extensions` | 4 KiB; `~/.vscode` 424 KiB | Guess: Cache, CachedData and logs are caches; workspaceStorage is per-workspace state | none | Guess: `workspaceStorage/<hash>/workspace.json` names the folder | None |
| Cursor | `~/Library/Application Support/Cursor/{User/globalStorage,User/workspaceStorage,Partitions,CachedData,Cache,logs}`, `~/.cursor`, `~/Library/Caches/cursor-compile-cache` | 10.96 GiB in all. `User/globalStorage/state.vscdb` alone is 6,754,578,432 bytes, dated 9 Oct. Partitions 1.54 GiB, logs 0.24 GiB, `~/.cursor` 0.94 GiB, compile cache 0.20 GiB | data for `state.vscdb`, which is Cursor's state database. cache for `logs`, `Cache`, `CachedData` and compile-cache. Guess: no Cursor docs were fetched | none | Guess: `workspaceStorage/<hash>/workspace.json` | None |

### Model files

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| Ollama | `~/.ollama/models` (`OLLAMA_MODELS`) (https://docs.ollama.com/faq) | absent | data in practice: a multi-GB download per model | A model download | The manifests under `models/manifests`. Guess | `ollama rm <model>`. Guess: the FAQ page does not cover it |
| Hugging Face hub | `~/.cache/huggingface/hub/{models,datasets,spaces}--<org>--<name>/{blobs,snapshots,refs}`, `~/.cache/huggingface/xet` | absent | tool. `hf cache prune` deletes unreferenced revisions and `.incomplete` files; `hf cache rm` deletes repos (https://huggingface.co/docs/huggingface_hub/guides/manage-cache) | A download | The repo id in the folder name | `hf cache ls`, `hf cache prune`, `hf cache rm` |

### Agents

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| Claude Code transcripts | `~/.claude/projects/<project>/<session>.jsonl` and `<session>/{subagents,tool-results}`, plus `file-history/`, `plans/`, `debug/`, `paste-cache/`, `shell-snapshots/` | `~/.claude` 2.05 GiB; `projects` 1.99 GiB in 712 `.jsonl` files across 9 projects, counting subagent transcripts; 91 of them are top-level session files | data. Claude Code deletes these after `cleanupPeriodDays`, default 30, and never touches `.credentials.json`, `agent-memory/`, `jobs/` or `daemon/` (https://code.claude.com/docs/en/claude-directory) | Lost: resume and rewind for past sessions | The project folder name is the cwd with non-alphanumerics replaced by `-` | `claude purge <path> --dry-run`; `cleanupPeriodDays` |
| Claude Code temp | `/private/tmp/claude-<uid>/<project>/<session>/scratchpad/` | 3.93 GiB in `/private/tmp/claude-501`. 3.41 GiB of it is session `c55990c5…`, which is live: pid 77597 runs `claude --session-id c55990c5-…`, and its transcript was written at 16:12 today | leak. Scratchpad files "last as long as the session's transcript", and `claude purge` does not touch the temp folder (claude-directory page) | Nothing regenerable is lost | The session UUID gives the transcript and the `--session-id` process (`leaks.go:122-129`) | Retention sweep; Noo-Noo `private-tmp-agent-scratch` |
| Claude Code CLI cache | `~/Library/Caches/claude-cli-nodejs/<project>/mcp-logs-<server>/` | 0.28 GiB. Its folders include `-private-tmp-tmp-project-…-worktrees-…` from worktrees that no longer exist | cache. Guess: these are logs | None | The project folder name | None. Guess |
| Claude Desktop VM | `~/Library/Application Support/Claude/vm_bundles` | 12.06 GiB of 12.92 GiB for the app folder | data. Noo-Noo moves it only when the Claude app is stopped (`playbook.go:144-148`) | Re-downloaded. Guess | Claude.app | None |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, `history.jsonl`, `log/`, `*.sqlite`, `packages/`, `plugins/` | `~/.codex` 2.40 GiB: sessions 1.05 GiB in 118 files, packages 0.53, plugins 0.32, `thread_history_1.sqlite` 0.19 | data. `history.max_bytes` caps history; `log_dir` defaults to `$CODEX_HOME/log` (https://learn.chatgpt.com/docs/config-file/config-reference). No transcript retention setting was found in the part read | Lost: resume | The rollout's session id. Guess: the cwd is inside the rollout | None found |
| Codex app caches | `~/Library/Caches/com.openai.codex`, `~/Library/Caches/Codex` | 0.67 GiB and 0.12 GiB | cache. Guess | none | Codex.app | None |
| cmux | `~/Library/Application Support/cmux`, `~/.cmux`, `~/Library/Caches/com.cmuxterm.app`, `~/Library/Logs/cmux` | 0.02 GiB, 24 KiB, 0.99 GiB and 0.02 GiB | cache for the Caches folder. Guess. App Support holds session state, so it is data | none | cmux.app | None |

### System

| Row | Paths | Measured here | Safe? | Rebuild cost | Owner | Official cleanup |
|---|---|---|---|---|---|---|
| `/private/tmp` | `/private/tmp/*` | 3.61 GiB by du; most of it is `claude-501`; 234 entries | leak. This Mac's `com.apple.tmp_cleaner.plist` runs `/usr/libexec/tmp_cleaner` daily at hour 0, but what it removes is not documented here. Noo-Noo says macOS "never sweeps /private/tmp" (`leaks.go:273-274`). The two do not agree, so this is an open question | none | The family name, and for agents a session UUID | Noo-Noo `temp-family` |
| `$TMPDIR` families | `/private/var/folders/*/*/T/*` | 0.49 GiB in 4,534 entries. The biggest families are `server-budget-*` ×745 (7 Oct to 27 Oct by folder mtime, 11.6 MiB), `collapse-fixpoint-*` ×606, `mv-test-*` ×404, `full-pipeline-test-*` ×202. None of these names appears in locohost, workforest or minmacs, and those repos' `test.sh` files clean up with `trap … EXIT` (locohost `test.sh:26-27`, workforest `test.sh:20-21`, minmacs `test.sh:35-38`) | leak. `com.apple.bsd.dirhelper.plist` sets `CLEAN_FILES_OLDER_THAN_DAYS=3` and runs daily at 03:35 (read with `plutil -p`). Families still exist from 7 Oct, so the sweep misses them. Guess: something keeps touching them, or dirhelper skips them | none | Family prefix, then a code search | Noo-Noo `temp-family` |
| `$TMPDIR/../C` | `/private/var/folders/*/*/C/` | 0.33 GiB | cache. Guess: per-app caches managed by the system | none | Bundle ids in the folder names | None |
| Chrome code-sign clones | `/private/var/folders/*/*/X/*.code_sign_clone/code_sign_clone.??????` | 11.94 GiB by du in 8 clones; unique bytes not measured | leak (`leaks.go:169-189`). Workaround: `--disable-features=MacAppCodeSignClone` | None | Chrome. lsof plus launch causality | Noo-Noo `chrome-code-sign-clone` |
| Old logs | `~/Library/Logs/*`, `*.log.old.*` | 0.30 GiB; OneDrive 0.16, `com.openai.codex` 0.06, `warp.log.old.3` 0.01 | cache. Guess: rotated logs are safe and current logs belong to their apps | none | Folder name | None |
| The Trash | `~/.Trash` | 8 KiB: two symlinks to `node_modules` | Report only. The user empties it (`caches_cmd.go:68-73`) | none | none | Finder, then Empty Trash |

## 4. Totals for this Mac

Sizes are from du, in GiB. Clones make several rows upper bounds.

| Group | GiB | What is in it |
|---|---|---|
| Project build output under `~/Documents/GitHub` | 86.50 | node_modules 53.78, .next 32.53, dist 0.14, .turbo 0.04, build 0.01. A single `du -skc` over all 772 folders gave 90,704,284 KiB, which is also 86.50 GiB |
| JavaScript global caches | 23.29 | pnpm store 19.14 (three layouts; `v11` alone is 5.48), pnpm metadata 1.00, Playwright 2.48, npm 0.67 |
| Agents | 22.50 | Claude Desktop vm_bundles 12.06, `/private/tmp/claude-501` 3.93, `~/.codex` 2.40, `~/.claude` 2.05, cmux cache 0.99, Codex caches 0.79, claude-cli-nodejs 0.28 |
| Apple | 15.46 | Simulator runtime 7.8 (from simctl), system dyld cache 3.84, simulator devices 3.70, DerivedData 0.12 |
| System temp and logs | 13.06 | Chrome clones 11.94, `$TMPDIR` 0.49, `C/` 0.33, logs 0.30 |
| Editors | 12.10 | Cursor 10.96, of which `state.vscdb` is 6.29; `~/.cursor` 0.94; compile cache 0.20 |
| Go | 4.37 | build cache 2.91, module cache 1.46 |
| Homebrew cache | 0.30 | `brew cleanup -n` would free 507.5 MB |
| Python | 0.08 | pip |
| **All** | **about 178** | The data volume uses 334.9 GiB (`df -k /System/Volumes/Data`), and the APFS container is 83.5 % used (`diskutil apfs list`) |

Not present on this Mac: Archives, DeviceSupport, Android, Gradle, CocoaPods, Maven, Yarn files, bun, Puppeteer, uv files, poetry, conda, cargo, Docker, Colima, OrbStack, JetBrains, Ollama and Hugging Face. Outside developer clutter, `~/Library/Caches/Google` is 2.13 GiB and `com.spotify.client` is 0.72 GiB.

**What Proactive mode could take with no question.** These are known cache kinds through each tool's own command. The six measured items below sum to 5.37 GiB. The Playwright and Chrome items have no unique size, so no total is given:
- go-build: 2.91 GiB
- pnpm metadata: 1.00 GiB
- npm: 0.67 GiB
- Homebrew: 0.47 GiB, by `brew cleanup`
- DerivedData: 0.12 GiB
- cursor-compile-cache: 0.20 GiB
- Playwright revisions with no live `.links` entry
- Chrome clones that pass the lsof gate

The big wins all need an owner check first: `.next` and `node_modules` in merged worktrees, and dead agent scratch.

## 5. How to tie clutter to its owner

1. **Project build output.** Walk up to the first `.git`. A `.git` file means a worktree, and WorkForest knows whether that worktree is merged. A `.git` folder means a main checkout. The manifest next to the output (`package.json`, `next.config.*`, `Cargo.toml`, `pyproject.toml`) names the tool. The pruned walk is in `dev.go:40-66`.
2. **Back-links that tools write for us.**
   - DerivedData `info.plist` has `WorkspacePath`.
   - Playwright `.links/<hash>` holds the path of an install.
   - pnpm `node_modules/.modules.yaml` has `storeDir`.
   - Simulator `device.plist` has `runtime` and `lastBootedAt`.
   - In every case the owner is gone when the path the file names is gone.
3. **Agent sessions.**
   - A session UUID in a folder name ties it to `~/.claude/projects/*/<uuid>.jsonl` and to a process with `--session-id <uuid>` (`leaks.go:122-129`).
   - Codex rollouts carry the session id in the file name.
   - `~/Library/Caches/claude-cli-nodejs/<cwd-with-dashes>/` carries the cwd, so an entry whose cwd no longer exists is an orphan.
4. **Temp families.** Strip the random suffix (`leaks.go:103-108`), then look up the prefix in the code of known scan roots. On this Mac the lookup failed for every big family, so Noo-Noo needs a fallback: report the family and do nothing.

## Recommendations

1. **Ship the catalog as data, one JSON row per kind, beside `registry/agents/`.** Follow the style of `registry/schema.json`, whose description says "Rows are data: adding a harness never needs a code change". Give `Clutter` a `registry/clutter/*.json` and a `schema.json`, and seed it from the block below. Plan section: 3, the shared core, Know: Clutter.
2. **Keep Noo-Noo's three sizing tiers and use them as it does.** Show `Blocks` everywhere. Run `UniqueAllocated` only on the rows an action is about to touch. Record the statfs delta in Undo. Show the du figure only next to the unique figure. This matters most for pnpm-cloned `node_modules` and Chrome clones. Plan sections: 3 (Sizer) and 6 (Clutter that knows its owner).
3. **Act through the tool's own command for every "tool" row.** These include:
   - `uv cache prune`, since uv says direct edits are "never safe"
   - `go clean -modcache`, since the folders are read-only
   - `pnpm store prune`
   - `xcrun simctl delete unavailable` and `simctl runtime delete --notUsedSinceDays`
   - `brew cleanup`, `docker system prune` and `hf cache prune`

   Run each command's `--dry-run` or `-n` form first to get the plan, and keep its output as the undo record. Moving these folders to the Trash is wrong. Plan sections: 1.5 (Nothing is lost) and 9, phase 3.
4. **Say plainly that the Trash frees nothing until it is emptied.** Moving a folder to `~/.Trash` on the same volume keeps its blocks allocated. This is reasoning, and phase 3 should measure it with `FreedByDelete`. So "Trash by default" and "free disk now" pull against each other. Proposal:
   - The Trash for build and leak rows, with a "Trash holds 12 GiB" line on Noo-Noo's header.
   - The tool's own command for cache and tool rows, since the tool can rebuild the data. The undo for those rows is "the tool downloads it again".

   Plan sections: 1.5, 5 (Noo-Noo in Proactive), and open question 3.
5. **Never find a cache path by running the tool.** `yarn cache dir` downloaded Yarn through Corepack on this Mac. Read env vars and config files instead: `GOCACHE`, `npm_config_cache`, `.modules.yaml`, `UV_CACHE_DIR`, `HF_HOME`. Fall back to the documented default. Plan section: 3 (Senses and Know). Senses must be read-only.
6. **Fix two gaps in Noo-Noo 0.7 when porting.**
   - On Xcode 26.1 the simulator dyld cache lives at `/Library/Developer/CoreSimulator/Caches/dyld`, which is 3.84 GiB and owned by root. The user-path target finds 0, so the row should be report-only.
   - `dist` and `build` must be skipped when `git ls-files` shows them tracked. LocoHost and WorkForest keep their app bundles in `build/`.

   Plan section: 9, phase 3: "nothing outside listed clutter kinds can be touched".
7. **Rank by owner state, then by unique size.** Order the rows: merged worktree, then stale worktree, then dead session, then everything else. On this Mac, `.next` and `node_modules` inside worktree folders total 34.24 GiB by du: 18.25 GiB of `node_modules` and 15.99 GiB of `.next`. That is the biggest single target, and WorkForest already knows which worktrees are merged. Wrap Up should include them. Plan section: 6 (Wrap Up a workstream; Clutter that knows its owner).
8. **Use back-links as free owner facts.** Playwright `.links` showed 3 dead installs here, the DerivedData `WorkspacePath` gave a project, and the `claude-cli-nodejs` folder names gave cwds. Each is one file read, with no scan needed. Plan section: 3 (Graph).
9. **Watch with FSEvents only the roots that change.** Those are `~/Library/Caches`, `~/.npm`, the pnpm store, `/private/tmp`, `$TMPDIR` and the scan roots. Re-size a root only when it has events. The per-root trend rows that Noo-Noo writes today (`internal/scan/caches.go:25-42`) feed "the pnpm store grew 9 GB this month". Plan sections: 3 (Event-driven) and 6 (Trends).
10. **Leave data rows to their owners and say so on the hover card.** These are Cursor `state.vscdb` at 6.29 GiB, the Claude Desktop vm_bundles at 12.06 GiB, Codex sessions, Claude transcripts and Xcode archives. Point to the owner's setting where one exists, such as `cleanupPeriodDays` or `history.max_bytes`. Plan section: 7 (hover card says why something stays).

## Open questions

1. **The union du total is settled.** One `du -skc` over all 772 folders gave 90,704,284 KiB, which matches the per-folder sum of 90,704,360 KiB to within 76 KiB. So almost no files are hardlinked across these folders, and du shows none of the sharing. Any sharing is through clones, which only `UniqueAllocated` can see.
2. **How much would removing worktree `node_modules` really free?** Phase 3 should run `UniqueAllocated` on one pnpm worktree's `node_modules` against the store.
3. **What does `/usr/libexec/tmp_cleaner` clean?** The launchd plist exists on this Mac and runs daily, while Noo-Noo's comment says `/private/tmp` is never swept. A read-only test on fixtures could settle it.
4. **Who makes the `$TMPDIR` families?** `server-budget`, `collapse-fixpoint`, `mv-test` and `full-pipeline-*` total about 2,000 folders. They do not appear in the three repos searched. They may come from a Go or Rust test harness elsewhere, or from an agent.
5. **Is `state.vscdb` growth a known Cursor problem with a supported fix?** No Cursor documentation was fetched.
6. **Which commands are unconfirmed?** The Apple Xcode storage page returned 404, so the DerivedData and DeviceSupport rows rest on a third-party tutorial. The cleanup commands for bun, Puppeteer, Ollama and Android are guesses from memory and need a source before they ship.
7. **Should cache rows really go to the Trash?** Recommendation 4 proposes the tool's own command for cache and tool rows, not the Trash. This changes PLAN.md open question 3 and needs a decision.

## Catalog as JSON

```json
[
  {"id":"xcode-derived-data","group":"apple","paths":["~/Library/Developer/Xcode/DerivedData/*"],"size":"blocks","class":"build","owner":"info.plist WorkspacePath","rebuild":"full rebuild","cleanup":null,"measured_gib":0.12,"sources":["https://www.kodeco.com/19998365-understanding-and-managing-xcode-space","plutil -p DerivedData/*/info.plist"]},
  {"id":"xcode-archives","group":"apple","paths":["~/Library/Developer/Xcode/Archives/*/*.xcarchive"],"size":"blocks","class":"data","owner":"xcarchive Info.plist (guess)","rebuild":"cannot","cleanup":"Xcode Organizer","measured_gib":0,"sources":["ls (absent)"]},
  {"id":"xcode-device-support","group":"apple","paths":["~/Library/Developer/Xcode/* DeviceSupport/*"],"size":"blocks","class":"cache","owner":"folder name = OS version","rebuild":"next device connect","cleanup":null,"measured_gib":0,"sources":["https://www.kodeco.com/19998365-understanding-and-managing-xcode-space"]},
  {"id":"simulator-devices","group":"apple","paths":["~/Library/Developer/CoreSimulator/Devices/*"],"size":"blocks","class":"tool","owner":"device.plist runtime, lastBootedAt","rebuild":"simulator data lost","cleanup":"xcrun simctl delete unavailable","measured_gib":3.70,"sources":["xcrun simctl delete (help)"]},
  {"id":"simulator-runtimes","group":"apple","paths":["/Library/Developer/CoreSimulator/Volumes/*"],"size":"simctl runtime list -j (never walk the mount)","class":"tool","owner":"device.plist runtime","rebuild":"multi-GB download","cleanup":"xcrun simctl runtime delete --notUsedSinceDays <d> --dry-run","measured_gib":7.8,"sources":["xcrun simctl runtime (help)","xcrun simctl runtime list","mount"]},
  {"id":"simulator-dyld-cache","group":"apple","paths":["/Library/Developer/CoreSimulator/Caches/dyld","~/Library/Developer/CoreSimulator/Caches/dyld"],"size":"blocks","class":"cache","report_only_when":"root-owned","owner":"runtime build (guess)","rebuild":"next simulator boot","cleanup":null,"measured_gib":3.84,"sources":["noo-noo internal/cli/caches_cmd.go:36-39","ls -la"]},
  {"id":"android-sdk","group":"jvm","paths":["~/Library/Android/sdk/*","~/.android/avd/*.avd"],"size":"blocks","class":"tool","owner":"AVD config.ini (guess)","rebuild":"download","cleanup":"sdkmanager --uninstall (guess)","measured_gib":0,"sources":["ls (absent)"]},
  {"id":"gradle-home","group":"jvm","paths":["~/.gradle/caches","~/.gradle/wrapper/dists"],"size":"blocks","class":"cache","owner":"global","rebuild":"download","cleanup":"automatic (30d downloaded, 7d created)","measured_gib":0,"sources":["https://docs.gradle.org/current/userguide/directory_layout.html"]},
  {"id":"gradle-project","group":"jvm","paths":["**/.gradle","**/build (with settings.gradle*)"],"size":"blocks","class":"build","owner":"settings.gradle(.kts)","rebuild":"full build","cleanup":"./gradlew clean","measured_gib":0,"sources":["https://docs.gradle.org/current/userguide/directory_layout.html"]},
  {"id":"cocoapods","group":"jvm","paths":["~/Library/Caches/CocoaPods","**/Pods"],"size":"blocks","class":"cache","owner":"Podfile.lock","rebuild":"pod install","cleanup":"pod cache clean --all","measured_gib":0,"sources":["https://guides.cocoapods.org/terminal/commands.html"]},
  {"id":"maven","group":"jvm","paths":["~/.m2/repository"],"size":"blocks","class":"cache","owner":"global","rebuild":"download","cleanup":"mvn dependency:purge-local-repository","measured_gib":0,"sources":["https://maven.apache.org/plugins/maven-dependency-plugin/purge-local-repository-mojo.html"]},
  {"id":"npm-cache","group":"js","paths":["~/.npm/_cacache","~/.npm/_npx/*","~/.npm/_logs"],"size":"blocks","class":"cache","owner":"global; _npx/<hash>/package.json","rebuild":"download","cleanup":"npm cache clean --force","measured_gib":0.67,"sources":["https://docs.npmjs.com/cli/v10/commands/npm-cache"]},
  {"id":"pnpm-store","group":"js","paths":["~/Library/pnpm/store/v*"],"size":"unique (clones)","class":"tool","owner":"node_modules/.modules.yaml storeDir","rebuild":"download on next install","cleanup":"pnpm store prune","measured_gib":19.14,"measured_note":"v3 2.33 + v10 11.22 + v11 5.48; projects name v11","sources":["https://pnpm.io/cli/store","barkpark/node_modules/.modules.yaml:3982"]},
  {"id":"pnpm-metadata","group":"js","paths":["~/Library/Caches/pnpm"],"size":"blocks","class":"cache","owner":"global","rebuild":"re-fetch","cleanup":"pnpm store prune","measured_gib":1.00,"sources":["https://pnpm.io/cli/store"]},
  {"id":"yarn-cache","group":"js","paths":["~/Library/Caches/Yarn/v*","~/.yarn/berry/cache"],"size":"blocks","class":"cache","never":["<project>/.yarn/cache when tracked by git"],"owner":".yarnrc.yml","rebuild":"download","cleanup":"yarn cache clean --mirror","measured_gib":0,"sources":["https://yarnpkg.com/cli/cache/clean"]},
  {"id":"bun-cache","group":"js","paths":["~/.bun/install/cache"],"size":"unique (clonefile)","class":"cache","owner":"global","rebuild":"download","cleanup":"bun pm cache rm (guess)","measured_gib":0,"sources":["https://bun.com/docs/pm/global-cache"]},
  {"id":"playwright-browsers","group":"js","paths":["~/Library/Caches/ms-playwright/*-*"],"size":"blocks","class":"cache","owner":"ms-playwright/.links/<hash> holds install path","rebuild":"170-370 MB download per revision","cleanup":"npx playwright uninstall --all","measured_gib":2.48,"sources":["https://playwright.dev/docs/browsers","cat ms-playwright/.links/*"]},
  {"id":"puppeteer-browsers","group":"js","paths":["~/.cache/puppeteer"],"size":"blocks","class":"cache","owner":null,"rebuild":"download","cleanup":"npx @puppeteer/browsers clear (guess)","measured_gib":0,"sources":["https://pptr.dev/guides/configuration"]},
  {"id":"node-modules","group":"js","paths":["**/node_modules (prune at first match)"],"size":"unique (pnpm clones on macOS)","class":"build","owner":"package.json, then .git file (worktree) or .git dir","rebuild":"pnpm install from store","cleanup":null,"measured_gib":53.78,"measured_note":"per-dir du sum, 447 dirs, upper bound","sources":["https://pnpm.io/settings/node-modules","stat -f %l (1 link)","noo-noo internal/modules/dev/dev.go:17-66"]},
  {"id":"next-build","group":"js","paths":["**/.next"],"size":"blocks","class":"build","owner":"next.config.*","rebuild":"next build","cleanup":null,"measured_gib":32.53,"sources":["du -sk"]},
  {"id":"turbo-cache","group":"js","paths":["**/.turbo"],"size":"blocks","class":"build","owner":"turbo.json","rebuild":"tasks re-run","cleanup":null,"measured_gib":0.04,"sources":["du -sk"]},
  {"id":"dist-build","group":"js","paths":["**/dist","**/build"],"size":"blocks","class":"build","never":["tracked by git (git ls-files)"],"owner":"sibling manifest","rebuild":"one build","cleanup":"project clean script","measured_gib":0.15,"sources":["du -sk","locohost/build, workforest/build hold app bundles"]},
  {"id":"pip-cache","group":"python","paths":["~/Library/Caches/pip"],"size":"blocks","class":"cache","owner":"global","rebuild":"download","cleanup":"pip cache purge","measured_gib":0.08,"sources":["https://pip.pypa.io/en/stable/cli/pip_cache/"]},
  {"id":"uv-cache","group":"python","paths":["~/.cache/uv"],"size":"uv cache clean --preview-features cache-physical-space","class":"tool","owner":"global","rebuild":"download","cleanup":"uv cache prune","measured_gib":0,"sources":["https://docs.astral.sh/uv/concepts/cache/"]},
  {"id":"poetry-cache","group":"python","paths":["~/Library/Caches/pypoetry"],"size":"blocks","class":"cache","owner":"global","rebuild":"download","cleanup":"poetry cache clear PyPI --all","measured_gib":0,"sources":["https://python-poetry.org/docs/cli/"]},
  {"id":"conda-pkgs","group":"python","paths":["~/miniconda3/pkgs","~/anaconda3/pkgs","~/.conda"],"size":"blocks","class":"tool","owner":"conda info --envs","rebuild":"download","cleanup":"conda clean --all","measured_gib":0,"sources":["https://docs.conda.io/projects/conda/en/latest/commands/clean.html"]},
  {"id":"python-venv","group":"python","paths":["**/.venv","**/__pycache__"],"size":"blocks","class":"build","owner":"pyproject.toml","rebuild":"uv sync","cleanup":null,"measured_gib":0.00,"sources":["du -sk"]},
  {"id":"cargo-target","group":"rust","paths":["**/target (with Cargo.toml)"],"size":"blocks","class":"build","owner":"Cargo.toml","rebuild":"full build","cleanup":"cargo clean","measured_gib":0,"sources":["https://doc.rust-lang.org/cargo/commands/cargo-clean.html"]},
  {"id":"cargo-home","group":"rust","paths":["~/.cargo/registry","~/.cargo/git"],"size":"blocks","class":"cache","owner":"global","rebuild":"download","cleanup":"automatic gc","measured_gib":0,"sources":["https://doc.rust-lang.org/cargo/reference/config.html"]},
  {"id":"go-build-cache","group":"go","paths":["~/Library/Caches/go-build"],"size":"blocks","class":"cache","owner":"global","rebuild":"slower builds","cleanup":"go clean -cache","measured_gib":2.91,"sources":["https://pkg.go.dev/cmd/go","go env GOCACHE"]},
  {"id":"go-mod-cache","group":"go","paths":["~/go/pkg/mod"],"size":"blocks","class":"tool","owner":"module path","rebuild":"download","cleanup":"go clean -modcache","measured_gib":1.46,"sources":["https://pkg.go.dev/cmd/go","ls -ld (dr-xr-xr-x)"]},
  {"id":"homebrew-cache","group":"brew","paths":["~/Library/Caches/Homebrew"],"size":"blocks","class":"tool","owner":"brew list --versions","rebuild":"download","cleanup":"brew cleanup","measured_gib":0.30,"sources":["https://docs.brew.sh/Manpage","brew cleanup -n (507.5MB)"]},
  {"id":"docker-desktop","group":"containers","paths":["~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"],"size":"st_blocks (sparse)","class":"tool","owner":"com.docker.compose.project label (guess)","rebuild":"image pulls; volumes are data","cleanup":"docker system prune","measured_gib":0,"sources":["https://docs.docker.com/reference/cli/docker/system/prune/","https://docs.docker.com/desktop/troubleshoot-and-support/faqs/macfaqs/"]},
  {"id":"colima","group":"containers","paths":["~/.colima"],"size":"st_blocks (sparse)","class":"tool","owner":"profile","rebuild":"image pulls","cleanup":"colima ssh -- sudo fstrim -a","measured_gib":0,"sources":["https://github.com/abiosoft/colima/blob/main/docs/FAQ.md"]},
  {"id":"orbstack","group":"containers","paths":["~/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img"],"size":"st_blocks (sparse, apparent 8 TB)","class":"tool","owner":"machines inside","rebuild":null,"cleanup":"docker system prune","measured_gib":0,"sources":["https://docs.orbstack.dev/faq"]},
  {"id":"jetbrains","group":"editors","paths":["~/Library/Caches/JetBrains/*","~/Library/Logs/JetBrains/*"],"size":"blocks","class":"cache","owner":"product+version in name","rebuild":"reindex","cleanup":"Help | Delete Leftover IDE Directories","measured_gib":0,"sources":["https://www.jetbrains.com/help/idea/directories-used-by-the-ide-to-store-settings-caches-plugins-and-logs.html"]},
  {"id":"vscode","group":"editors","paths":["~/Library/Application Support/Code/{Cache,CachedData,logs}"],"size":"blocks","class":"cache","owner":"workspaceStorage/*/workspace.json (guess)","rebuild":null,"cleanup":null,"measured_gib":0.00,"sources":["du -sk"]},
  {"id":"cursor","group":"editors","paths":["~/Library/Application Support/Cursor/{Cache,CachedData,logs}","~/Library/Caches/cursor-compile-cache"],"size":"blocks","class":"cache","never":["User/globalStorage/state.vscdb"],"owner":"Cursor.app","rebuild":null,"cleanup":null,"measured_gib":10.96,"measured_note":"state.vscdb alone 6.29 GiB","sources":["du -sk","ls -laS globalStorage"]},
  {"id":"ollama-models","group":"models","paths":["~/.ollama/models"],"size":"blocks","class":"data","owner":"models/manifests (guess)","rebuild":"model download","cleanup":"ollama rm (guess)","measured_gib":0,"sources":["https://docs.ollama.com/faq"]},
  {"id":"huggingface-hub","group":"models","paths":["~/.cache/huggingface/hub/*--*--*","~/.cache/huggingface/xet"],"size":"cache-wide size_on_disk (blobs shared)","class":"tool","owner":"repo id in name","rebuild":"download","cleanup":"hf cache prune","measured_gib":0,"sources":["https://huggingface.co/docs/huggingface_hub/guides/manage-cache"]},
  {"id":"claude-code-transcripts","group":"agents","paths":["~/.claude/projects/*/*.jsonl","~/.claude/{file-history,plans,debug,paste-cache,shell-snapshots}"],"size":"blocks","class":"data","never":["~/.claude/.credentials.json","~/.claude/agent-memory","~/.claude/jobs","~/.claude/daemon","~/.claude/projects/*/memory"],"owner":"project dir = cwd with non-alphanumerics as -","rebuild":"lost: resume","cleanup":"claude purge <path> --dry-run; cleanupPeriodDays","measured_gib":2.05,"sources":["https://code.claude.com/docs/en/claude-directory"]},
  {"id":"claude-code-scratch","group":"agents","paths":["/private/tmp/claude-*/*/*"],"size":"blocks","class":"leak","signature":"private-tmp-agent-scratch","owner":"session UUID -> transcript + --session-id process","rebuild":"none needed","cleanup":"retention sweep","measured_gib":3.93,"sources":["noo-noo internal/leaks/leaks.go:190-228","https://code.claude.com/docs/en/claude-directory","ps -axo args"]},
  {"id":"claude-cli-cache","group":"agents","paths":["~/Library/Caches/claude-cli-nodejs/*/mcp-logs-*"],"size":"blocks","class":"cache","owner":"folder name = cwd with dashes","rebuild":"none (logs, guess)","cleanup":null,"measured_gib":0.28,"sources":["ls, du -sk"]},
  {"id":"claude-desktop-vm","group":"agents","paths":["~/Library/Application Support/Claude/vm_bundles"],"size":"blocks","class":"data","owner":"Claude.app","rebuild":"re-download (guess)","cleanup":null,"measured_gib":12.06,"sources":["noo-noo internal/modules/offload/playbook.go:144-148","du -sk"]},
  {"id":"codex","group":"agents","paths":["~/.codex/sessions/*/*/*/rollout-*.jsonl","~/.codex/log","~/.codex/history.jsonl"],"size":"blocks","class":"data","owner":"session id in rollout name","rebuild":"lost: resume","cleanup":"history.max_bytes","measured_gib":2.40,"sources":["https://learn.chatgpt.com/docs/config-file/config-reference","find ~/.codex/sessions"]},
  {"id":"codex-app-cache","group":"agents","paths":["~/Library/Caches/com.openai.codex","~/Library/Caches/Codex"],"size":"blocks","class":"cache","owner":"Codex.app","rebuild":null,"cleanup":null,"measured_gib":0.79,"sources":["du -sk"]},
  {"id":"cmux","group":"agents","paths":["~/Library/Caches/com.cmuxterm.app","~/Library/Logs/cmux"],"size":"blocks","class":"cache","never":["~/Library/Application Support/cmux"],"owner":"cmux.app","rebuild":null,"cleanup":null,"measured_gib":1.01,"sources":["du -sk"]},
  {"id":"private-tmp","group":"system","paths":["/private/tmp/*"],"size":"blocks","class":"leak","signature":"temp-family","owner":"family prefix","rebuild":null,"cleanup":null,"measured_gib":3.61,"sources":["noo-noo internal/leaks/leaks.go:253-276","/System/Library/LaunchDaemons/com.apple.tmp_cleaner.plist"]},
  {"id":"tmpdir-families","group":"system","paths":["/private/var/folders/*/*/T/*"],"size":"blocks","class":"leak","signature":"temp-family","never_prefix":["com.apple."],"owner":"family prefix, then code search","rebuild":null,"cleanup":"dirhelper sweeps files older than 3 days","measured_gib":0.49,"sources":["/System/Library/LaunchDaemons/com.apple.bsd.dirhelper.plist","ls | uniq -c"]},
  {"id":"chrome-code-sign-clone","group":"system","paths":["/private/var/folders/*/*/X/*.code_sign_clone/code_sign_clone.??????"],"size":"unique (APFS clones)","class":"leak","signature":"chrome-code-sign-clone","owner":"Chrome; lsof + launch causality","rebuild":"none","cleanup":"relaunch Chrome cleanly; --disable-features=MacAppCodeSignClone","measured_gib":11.94,"measured_note":"du over 8 clones, upper bound","sources":["noo-noo internal/leaks/leaks.go:169-189","du -sk"]},
  {"id":"user-logs","group":"system","paths":["~/Library/Logs/*","**/*.log.old.*"],"size":"blocks","class":"cache","owner":"folder name","rebuild":null,"cleanup":null,"measured_gib":0.30,"sources":["du -sk"]},
  {"id":"trash","group":"system","paths":["~/.Trash"],"size":"blocks","class":"report-only","owner":null,"rebuild":null,"cleanup":"Finder > Empty Trash","measured_gib":0.00,"sources":["noo-noo internal/cli/caches_cmd.go:68-73"]}
]
```

## Verification

The verifier re-checked this file on 2026-10-27 with read-only commands and fresh fetches of the cited URLs. No file outside this one was written. Commands: `du -sk`, `du -skc` over the 772 paths in `scratchpad/d-clutter/artifacts.txt`, `ls -la`, `ls -ld`, `stat -f %l`, `plutil -p`, `df -k`, `diskutil apfs list`, `mount`, `ps -axo pid,args`, `xcrun simctl runtime list`, the `simctl delete` and `simctl runtime` help, `go env`, `uv cache dir`, `HOMEBREW_NO_AUTO_UPDATE=1 brew cleanup -n`, `git ls-files`, `grep` and `sed -n` on the noo-noo clone at `1e6dc60`.

**Counts.** 84 claims confirmed, 15 corrected, 2 marked unsupported.

**Confirmed, by group.**
- Noo-Noo code, 17 claims: the three sizer tiers and the 34 µs cost (`sizer.go:9-35`), the leak signature rules for all four classes, the session-id and transcript liveness rule (`leaks.go:122-126`), the suffix rule (`leaks.go:105-108`), the safety walls and the case-insensitive match (`safety.go:32-56`), the 14 cache targets and the Trash rule (`caches_cmd.go:20-73`), the dev targets and pruning (`dev.go:17-66`), orphanapps 50 MB, 30 days and the never-flag list with `pypoetry` at line 74, truth-sized Docker.raw (`orphanapps.go:8-9`), the seven playbook ids, the per-root `cache_size_history` rows (`scan/caches.go:25-42`) and the `registry/schema.json` quote.
- Measurements on this Mac, 41 claims: every du figure in the catalog and the totals table matched the re-run within 0.01 GiB, except the drift noted below. The union `du -skc` gave 90,704,208 KiB against 90,704,284 KiB before. The pnpm link count is 1, `.modules.yaml:3982` names `store/v11`, 8 Chrome clones total 11.94 GiB, the simulator mount is read-only and sealed on `/dev/disk5s1`, simctl reports 7.8G, the dyld cache is root:wheel, 12 entries sit under Devices, `device.plist` shows iPhone 16e last booted 2025-11-10, `info.plist` names `~/Desktop/test/test.xcodeproj`, Playwright has 4+4+2 revisions and 3 of 6 `.links` point at missing paths, the four `$TMPDIR` family counts match, `dirhelper` has `CLEAN_FILES_OLDER_THAN_DAYS=3` at 03:35, `tmp_cleaner` runs at hour 0, pid 77597 runs `--session-id c55990c5…` and its scratch is 3.41 GiB, `state.vscdb` is 6,754,578,432 bytes dated 9 Oct, `crypto@v0.57.0` is `dr-xr-xr-x`, `brew cleanup -n` says "approximately 507.5MB", the Corepack folder is dated 27 Oct 16:05, the test.sh traps exist, the family names do not appear in the three repos, and all 19 "absent" paths are absent.
- Web sources, 26 claims: pnpm settings and store, bun, Docker FAQ and prune, OrbStack, Hugging Face, uv, Gradle, npm, Playwright, Puppeteer, Homebrew, Go, cargo config and clean, pip, poetry, CocoaPods, Maven, conda, Claude Code directory page, Colima, JetBrains, Ollama path, Codex config keys, the kodeco DerivedData quote and the Apple 404.

**Corrected.**
1. The pnpm store is three layouts, not one. `store` is 19.14 GiB, but `v11`, the one projects name, is 5.48 GiB. The summary, section 2, the catalog row, the totals and the JSON now say so.
2. The founding incident deleted 64 of the 65 clones, per `sizer.go:4-7`.
3. to 7. Line citations in `leaks.go`: 178-276 is now 166-276, 180-203 is now 169-189, 205-245 is now 190-228, 248-275 is now 253-276, and 271-272 is now 273-274.
8. `playbook.go:157-162` is now 144-148, where `claude-vm-bundles` and its `StopGate` sit.
9. minmacs `test.sh:37-38` is now 35-38, where `cleanup()` starts.
10. DerivedData has 18 project folders, 17 of them `Unsaved_Xcode_Document*`, not 19 and 18.
11. The oldest `server-budget-*` folder is dated 7 Oct, not 14 Oct. Both mentions are fixed.
12. Seven Chrome clones are about 1.4 GiB each and one is 2.1 GiB, not "about 1.5 GiB".
13. Yarn `--mirror` cleans the global cache instead of the local one. It does not clean both. `--all` cleans both.
14. The Proactive list said "about 9 GiB". Its six measured items sum to 5.37 GiB, and the other two have no unique size.
15. The 712 `.jsonl` files include subagent transcripts. Only 91 are top-level session files today.

**Unsupported.**
1. The kodeco page, as fetched, does not say that Xcode rebuilds DeviceSupport when a device connects.
2. The exact Corepack message cannot be re-checked. The folder it wrote exists.

**Drift and one inconsistency, not counted as errors.**
- Several sizes grew between the two runs: go-build is now 3.23 GiB, `/private/tmp` is 4.51 GiB, `claude-501` is 4.12 GiB, `$TMPDIR` has 4,538 entries, `/private/tmp` has 238, the data volume uses 333.7 GiB and the APFS container is 83.3 % used.
- The original run put `/private/tmp` at 3.61 GiB and `/private/tmp/claude-501` at 3.93 GiB. A child cannot be larger than its parent, so the two figures come from different moments. The re-run has both in order.
- `artifacts.txt` lists 54 `__pycache__` and 10 `.vercel` folders. The catalog counts 50 `__pycache__` folders from `du-__pycache__.tsv`. Both are under 0.01 GiB.

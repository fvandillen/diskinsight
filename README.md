# DiskInsight

A native macOS disk usage analyser inspired by **WinDirStat**. See where your
space goes with a linked directory tree, file-type breakdown, and cushion
treemap, then move unwanted files to Trash. Built with SwiftUI and AppKit.

**macOS 14+ · Apple Silicon · No third-party dependencies · [MIT licensed](LICENSE)**

## Install with Homebrew

```bash
brew install --cask fvandillen/tap/diskinsight
open -a DiskInsight
```

This uses the public [DiskInsight Homebrew tap](https://github.com/fvandillen/homebrew-tap).
If you prefer to add the tap explicitly:

```bash
brew tap fvandillen/tap
brew install --cask diskinsight
```

Alternatively, download the ZIP from
[GitHub Releases](https://github.com/fvandillen/diskinsight/releases/latest),
unzip it, and drag **DiskInsight.app** into **Applications**. Intel Macs are not
currently supported by the distributed app.

**First launch:** releases are ad-hoc signed, not Apple-notarized. If macOS
blocks the app, attempt to open it, then use **System Settings → Privacy &
Security → Open Anyway** and confirm. On older macOS versions, right-clicking
the app and choosing **Open** may also work. Only approve a download you trust;
you do not need to disable Gatekeeper.

To upgrade or remove the app:

```bash
brew upgrade --cask diskinsight
brew uninstall --cask diskinsight
```

## Screenshots

![Three linked views: directory tree, file-type list, and cushion treemap](docs/screenshot.png)

*A real app capture scanning synthetic demo files; no private file listings.*

![The up-front Full Disk Access request](docs/permissions.png)

## Quick start

1. Launch DiskInsight and grant **Full Disk Access** for a complete scan, or
   choose **Continue with limited access**.
2. Click **Scan** to choose a folder, or use its menu for a common location.
3. Sort the tree by size or select a file type to highlight its treemap blocks.
4. Select a file to reveal it in Finder, or press **⌘⌫** to move it to Trash
   after confirmation. Review the selection before deleting.

Scanning reads filesystem metadata locally. It does not upload your file list.
Protected or unreadable folders can make totals incomplete; DiskInsight marks
those omissions rather than treating them as empty.

## What it does

* **Directory tree** — every folder and file with size on disk, percentage of its
  parent, item/file/folder counts and modification date. Sortable by any column.
* **File-type list** — space used per extension, colour-coded and ranked.
  Selecting a type highlights every matching block in the treemap.
* **Cushion treemap** — the WinDirStat visualisation: one rectangle per file,
  area proportional to size, colour by file type, Van Wijk cushion shading to
  reveal folder structure. Click a block to select it in the tree, double-click
  to zoom into it.
* **Delete** — move anything to the Trash (⌘⌫) with confirmation. The tree,
  totals, file-type list and treemap all update instantly, without rescanning.
* **Reveal / Open / Copy Path** from the toolbar or context menu.

The three views are linked: selecting in one highlights in the others.

## Build and install

```bash
./Scripts/build_app.sh             # -> build/DiskInsight.app
./Scripts/build_app.sh --install   # also copies to /Applications
```

Requirements: macOS 14+, Apple Silicon, Xcode command line tools
(`xcode-select --install`). The script builds a release
`arm64` binary, wraps it in a bundle with a generated icon, and ad-hoc signs it.

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and smoke tests, and
[the release guide](docs/releasing.md) for release packaging and Homebrew updates.

## Permissions, asked once

macOS guards Desktop, Documents, Downloads, iCloud Drive and other locations, and
raises a separate consent dialog the first time an app touches each one. A disk
analyser walks all of them, so the naive result is a barrage of popups mid-scan.

DiskInsight asks once instead. On first launch it shows a single screen requesting
**Full Disk Access**, opens System Settings on the right page, and polls in the
background so it continues by itself the moment you grant it — no second trip.

If you decline and pick *Continue with limited access*, DiskInsight does **not**
fall back to prompting. The scanner refuses to open guarded folders at all: they
appear greyed out with a lock and a banner explains the totals are incomplete.
This is designed to avoid repeated permission prompts. macOS permission behavior
can vary by OS version and location.

The guarded list was derived by watching `tccd`. In development testing, scanning
an entire home folder without Full Disk Access produced one TCC query —
`kTCCServiceSystemPolicyAllFiles`, which is DiskInsight checking its own access, and
is silent by design:

```
$ log stream --predicate 'process == "tccd"' &
$ DiskInsight --scan ~
  1612878 files, 308877 folders, 36 unreadable, 28 blocked, 10.0 s

kTCCServiceSystemPolicyAllFiles   1     # the access check itself
                                        # zero folder prompts
```

Only folders macOS actually guards are skipped. `~/Pictures`, `~/Movies` and
`~/Music` are deliberately *not* on the list — `tccd` shows they are not
folder-guarded, and on most Macs they hold a large share of the data you came to
find. Their media *library bundles* are skipped, since those are guarded.

Homebrew also installs a `diskinsight` command. Run `diskinsight --probe-paths`
to see which locations deny access on your machine. This diagnostic directly
opens the listed locations and may trigger macOS permission prompts.

## Performance

Development measurements on an Apple Silicon Mac, scanning the whole startup
volume (results depend on your hardware, filesystem, and permissions):

| Metric | Value |
| --- | --- |
| Items | 3,008,021 files / 656,970 folders |
| Total measured | 735 GB |
| Wall clock | ~21 s (cold), ~1 s for a small tree warm |
| Peak memory | ~620 MB |

Totals were verified against `du -sk` and `find` on a 158k-file tree: identical
file and folder counts, and sizes within 0.2% (`du` de-duplicates hard links,
DiskInsight counts each link, matching WinDirStat's behaviour).

## How the scan works

* Directories are drained from a shared work queue by one thread per core, using
  `opendir` + `fstatat` — a single hot subtree still parallelises.
* **Firmlinks** (`/Users` → the Data volume) are followed, but every directory is
  de-duplicated by `(device, inode)` so nothing is counted twice.
* **Hidden helper volumes** (`/System/Volumes/Data`, `VM`, `Preboot`, `Update`,
  and the mounted system snapshot) are skipped — they either duplicate content
  that is already visible or contain nothing actionable.
* **Network, autofs and other remote mounts** are skipped by consulting a
  `getfsstat` snapshot taken once per scan, so the hot loop never issues a
  `statfs` that could block on a stalled mount.
* **Cloud placeholders** (`SF_DATALESS`, e.g. evicted iCloud Drive folders) are
  never opened, so scanning cannot trigger a multi-gigabyte download. Evicted
  files correctly report 0 bytes on disk.
* Symbolic links are never followed.

Skipping these cost 88 minutes on the first prototype; the current scanner does
the same volume in 21 seconds.

### Size on disk vs logical size

Toggle in the action bar. *Size on disk* uses `st_blocks × 512` (allocated blocks,
and 0 for cloud-evicted files). *Logical size* uses `st_size`. Allocated size is
not a guarantee of reclaimable space: hard links, APFS clones, and snapshots can
share or retain data. Moving files to Trash does not free their space until you
empty Trash.

## Command line

The same binary runs headless, which is handy for scripting:

```bash
diskinsight --scan ~/Downloads --top=20
diskinsight --scan / --png=/tmp/map.png --verbose
```

Without Homebrew, use `/Applications/DiskInsight.app/Contents/MacOS/DiskInsight`
instead of `diskinsight`. Full Disk Access for headless use can also depend on
the terminal app launching the process.

| Flag | Meaning |
| --- | --- |
| `--scan <path>` | print the largest entries and file types, then exit |
| `--top=N` | how many rows to print (default 20) |
| `--png=<file>` | also write a 1600×900 treemap image |
| `--verbose` | live progress while scanning |
| `--cross-volumes` | follow mount points onto other volumes |
| `--list-blocked` | list folders skipped for permissions |
| `--probe-paths` | report which guarded locations deny access |

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘O | Scan a folder… |
| ⌘R | Rescan |
| ⌘⌫ | Move selection to Trash |
| ⇧⌘R | Show in Finder |
| ⇧⌘C | Copy path |
| ⌘[ / ⌘] | Treemap zoom out / whole tree |

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for source layout, local development,
smoke tests, and screenshot capture. Report bugs or suggest features in
[GitHub issues](https://github.com/fvandillen/diskinsight/issues).

Copyright © 2026 Florian van Dillen. Released under the [MIT License](LICENSE).
DiskInsight is an independent project, not affiliated with WinDirStat.

# Contributing to DiskInsight

Bug reports, documentation improvements, and focused pull requests are welcome.
Use [GitHub issues](https://github.com/fvandillen/diskinsight/issues) for bugs and
feature requests. Include your macOS version, processor, steps to reproduce, and
whether Full Disk Access is enabled. Do not post private paths or file listings;
reproduce problems with a small synthetic folder where possible.

## Local development

Requirements: macOS 14 or later, Apple Silicon, and Xcode command line tools
(`xcode-select --install`). There are no third-party package dependencies.

```bash
git clone https://github.com/fvandillen/diskinsight.git
cd diskinsight
swift build
swift test
./Scripts/build_app.sh
./Scripts/smoke_test.sh
open build/DiskInsight.app
```

`swift build` builds for the host architecture. The app packaging script targets
Apple Silicon; Intel release binaries are not currently distributed.

Keep changes focused, use existing SwiftUI/AppKit patterns, and document behavior
changes. Exercise both GUI and headless mode when changing the scanner. Never
test Trash operations against real user files.

Scanner access tests use disposable synthetic files. They cover expected
system-access denials, unexpected failures, warning copy, and bounded diagnostic
samples. Permission-denial fixtures are skipped when tests run as root.

## Source layout

| Directory | Responsibility |
| --- | --- |
| `Sources/DiskInsight/App` | Entry point, headless mode, UI snapshot harness |
| `Sources/DiskInsight/Model` | File tree, scan types, application state |
| `Sources/DiskInsight/Scan` | Parallel scanner, mount table, permissions |
| `Sources/DiskInsight/Treemap` | Squarified layout and cushion rendering |
| `Sources/DiskInsight/Views` | Permission gate, tree, file types, treemap |
| `Sources/DiskInsight/Util` | Palette, formatting, icon cache |
| `Scripts` | App build, packaging, smoke tests, icon generation |

## UI screenshots

Use the app's own snapshot harness (no Screen Recording permission required).
Use synthetic demo files, not your home folder or private projects.

```bash
build/DiskInsight.app/Contents/MacOS/DiskInsight \
  --ui-snapshot=/tmp/diskinsight.png --ui-path=/tmp/DiskInsight-Demo
build/DiskInsight.app/Contents/MacOS/DiskInsight \
  --ui-snapshot=/tmp/diskinsight-permissions.png --ui-gate
```

Additional development flags: `--ui-sort-name`, `--ui-select=<path>`,
`--ui-click=x,y` (treemap coordinates from 0 to 1), and `--ui-trash`.
**`--ui-trash` really moves the selected file to Trash.** Use disposable fixtures.

See [the release guide](docs/releasing.md) for packaging and Homebrew updates.
Contributions are licensed under the project's [MIT license](LICENSE).

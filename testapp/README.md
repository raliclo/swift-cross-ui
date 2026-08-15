# testapp

Standalone apps that reproduce specific upstream issues, plus the documents
that say which app tests what and what has been verified.

**This directory does not exist upstream.** Nothing here can be part of a pull
request, which is why every commit touching it is recorded as `local` in
`issue_commits.csv` and why commits that mix `Sources/` and `testapp/` changes
need the `testapp/` half dropped before submitting.

## Start here

| Question | File |
| --- | --- |
| Where do I run this issue, and does the answer count? | `UI-test-plan platform-en.md` |
| What are the steps for app PN? | `UI-test-plan overall-en.md` |
| What is the plan for the GtkBackend work? | `UI-test-plan linux-en.md` |
| What is the plan for the AppKit/Android/iOS work? | `UI-test-plan bug-en.md` |
| What is the state of every upstream issue? | `issues.csv` |
| Which commit fixes what, and can it be submitted? | `issue_commits.csv` |

`UI-test-plan platform-en.md` is the entry point: it maps all 40 covered issues onto
the six platforms and marks, per cell, whether a run there settles the issue,
is only a comparison, or tells you nothing.

## The apps

P0-P17, one Swift file each, built as standalone executables. P0-P6 came out of
the WinUIBackend work, P7-P10 and P15 target GtkBackend, P11 AppKitBackend, P12
AndroidBackend, P14 UIKitBackend, and P13, P16 and P17 cover core layout and
split-view behaviour. `UI-test-plan platform-en.md` has the full mapping.

```sh
zsh testapp/compile.zsh P7 P15 P17     # build a subset
zsh testapp/compile.zsh                # build everything
```

Output lands in `testapp/output/` -- `PN` on Linux and macOS, `PN.exe` on
Windows. Neither the output directory nor the `.compile-work` build tree is
tracked.

## Environment setup

| Script | For |
| --- | --- |
| `install_tool_wsl.sh` | WSL: GTK 4, the Swift tarball, and the libxml2/ICU shims Ubuntu 26.04 needs |
| `install_tools_ios.sh` | macOS: the iOS Simulator toolchain, called automatically by `compile.zsh -ios` |

## Other scripts

| Script | For |
| --- | --- |
| `screenshot.sh` | Captures the composited desktop, which is the only way to see D3D/DirectComposition content |
| `gpu-matrix.sh`, `P6-test.sh`, `test_P6.sh` | P6's throughput matrix and its unattended runs |
| `rebase.zsh` | Rebases, then checks that the hashes in `issue_commits.csv` still exist on the branch |

`rebase.zsh` exists because a rebase silently orphans recorded hashes: they
keep resolving from the reflog, so nothing looks wrong until the next clone.

## Records

`P6_findings/` holds the measured throughput numbers behind the NV12 work, and
`comments/` holds write-ups drafted for upstream issues.

Two documents are deliberately untracked and local to a checkout:
`UI-test-plan overall-zhTW.md`, the Traditional Chinese half of the test plan, and
`UI-test-results.md`. Edits to the test steps belong in both language files even
though only `UI-test-plan overall-en.md` is committed.

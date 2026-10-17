## Test suite for nova.
## Exercises module functionality using the standard unittest framework.

import std/[os, unittest, strutils]
import ../src/nova

# Repository Test Cases
let repoNameTestCases = @[
  # Clean SSH Protocols
  (input: "git@github.com:sharkdp/bat.git", expected: "sharkdp/bat"),
  (input: "git@gitlab.com:owner/my-project.git", expected: "owner/my-project"),
  
  # Standard HTTPS / HTTP URL Formats
  (input: "https://github.com/burntsushi/ripgrep", expected: "burntsushi/ripgrep"),
  (input: "https://github.com/sharkdp/bat", expected: "sharkdp/bat"),
  (input: "http://github.com/neovim/neovim", expected: "neovim/neovim"),
  (input: "https://github.com/fastfetch-cli/fastfetch", expected: "fastfetch-cli/fastfetch"),
  (input: "https://gitlab.com/inkscape/inkscape", expected: "inkscape/inkscape"),
  (input: "https://github.com/BigMacTaylor/leve-panel", expected: "BigMacTaylor/leve-panel"),

  # No protocol prefix
  (input: "://github.com/fastfetch-cli/fastfetch", expected: "fastfetch-cli/fastfetch"),
  (input: "://github.com/sharkdp/bat", expected: "sharkdp/bat"),
  (input: "://gitlab.com/inkscape/inkscape", expected: "inkscape/inkscape"),
  (input: "github.com/fastfetch-cli/fastfetch", expected: "fastfetch-cli/fastfetch"),
  (input: "gitlab.com/inkscape/inkscape", expected: "inkscape/inkscape"),

  # Short notation
  (input: "BigMacTaylor/leve-panel", expected: "BigMacTaylor/leve-panel"),
  (input: "twpayne/chezmoi", expected: "twpayne/chezmoi"),
  (input: "sharkdp/bat", expected: "sharkdp/bat"),

  # Malformed, deep subpaths, or redundant slashes
  (input: "///://github.com/nim-lang/Nim", expected: "nim-lang/Nim"),
  (input: "invalid-string-no-slashes", expected: ""),

  # Malicious / Unsupported URLs (Should yield an empty string)
  (input: "https://malicious-site.com", expected: ""),
  (input: "https://unsupported-site.com", expected: ""),
  (input: "://fake.com", expected: ""),
  (input: "://google.com", expected: ""),
]

let sourceTypeTestCases = @[
  # Personal Package Archives
  (input: "ppa:neovim-ppa/stable", expected: srcPpa),
  (input: "ppa:mozillateam/ppa", expected: srcPpa),
  (input: "PPA:deadsnakes/ppa", expected: srcPpa),
  
  # Local Filesystem Targets
  (input: "./packages/my-pkg.deb", expected: srcLocalFile),
  (input: "/usr/bin/localpkg.deb", expected: srcLocalFile),
  (input: "/opt/downloads/app.rpm", expected: srcLocalFile),
  (input: "file:///home/user/app.AppImage", expected: srcLocalFile),
  
  # Remote Source Types
  (input: "https://github.com", expected: srcGithubRepo),
  (input: "git@gitlab.com:owner/project.git", expected: srcGitlabRepo),
  (input: "twpayne/chezmoi", expected: srcGithubRepo), # Fallback short notation
  (input: "https://example.com", expected: srcGenericUrl),
]

# Package Test Cases
let assetTestCases = @[
  (asset: "5.0.0+rc1", name: "unknown", ver: "5.0.0"),
  (asset: "appimagelauncher_2.2.0-ghrelease+amd64.deb", name: "appimagelauncher", ver: "2.2.0"),
  (asset: "Audacity-4.0.1", name: "audacity", ver: "4.0.1"),
  (asset: "audacity-linux-4.0.1-x86_64.AppImage", name: "audacity", ver: "4.0.1"),
  (asset: "Audacity-v4.0.1+dfsg-1", name: "audacity", ver: "4.0.1"),
  (asset: "BambuStudio_ubu24-v02.08.04.57-20260922164607.AppImage", name: "bambustudio", ver: "2.8.4"),
  (asset: "Bambu_Studio_linux_fedora-v02.08.04.57.AppImage", name: "bambu-studio", ver: "2.8.4"),
  (asset: "bat-musl_0.26.1_arm64.deb", name: "bat-musl", ver: "0.26.1"),
  (asset: "bat-musl_0.26.1_musl-linux-amd64.deb", name: "bat-musl", ver: "0.26.1"),
  (asset: "bat-v0.24.0-x86_64-unknown-linux-musl.tar.gz", name: "bat", ver: "0.24.0"),
  (asset: "bat-v0.26.1-x86_64-unknown-linux-gnu.tar.gz", name: "bat", ver: "0.26.1"),
  (asset: "bat_0.24.0_amd64.deb", name: "bat", ver: "0.24.0"),
  (asset: "bitwarden-2024.8.0-amd64.snap", name: "bitwarden", ver: "2024.8.0"),
  (asset: "btop-x86_64-linux-musl.tbz", name: "btop", ver: ""),
  (asset: "btop-x86_64-unknown-linux-musl.tar.gz", name: "btop", ver: ""),
  (asset: "Cherry-Studio-0.8.5-x86_64.AppImage", name: "cherry-studio", ver: "0.8.5"),
  (asset: "cherry-studio_0.8.5_amd64.deb", name: "cherry-studio", ver: "0.8.5"),
  (asset: "cherry-studio_v0.8.5-beta.1_amd64.deb", name: "cherry-studio", ver: "0.8.5"),
  (asset: "deb-get_0.4.0_all.deb", name: "deb-get", ver: "0.4.0"),
  (asset: "eza_x86_64-unknown-linux-gnu.tar.gz", name: "eza", ver: ""),
  (asset: "eza_x86_64-unknown-linux-musl.tar.gz", name: "eza", ver: ""),
  (asset: "fastfetch-3.0.0-rc2-x86_64.rpm", name: "fastfetch", ver: "3.0.0"),
  (asset: "fastfetch-linux-amd64.deb", name: "fastfetch", ver: ""),
  (asset: "fastfetch-linux-amd64.tar.gz", name: "fastfetch", ver: ""),
  (asset: "fastfetch-musl-amd64.tar.gz", name: "fastfetch", ver: ""),
  (asset: "fd-musl_10.5.0_amd64.deb", name: "fd-musl", ver: "10.5.0"),
  (asset: "fd-v10.5.0-armhf.deb", name: "fd", ver: "10.5.0"),
  (asset: "fd-v10.5.0-x86_64-unknown-linux-gnu.tar.gz", name: "fd", ver: "10.5.0"),
  (asset: "fd-v10.5.0-x86_64-unknown-linux-musl.tar.gz", name: "fd", ver: "10.5.0"),
  (asset: "fooyin-0.13.1-x86_64.AppImage", name: "fooyin", ver: "0.13.1"),
  (asset: "fooyin-0.13.1.fc43.x86_64.rpm", name: "fooyin", ver: "0.13.1"),
  (asset: "fzf-0.54.3-linux_amd64.tar.gz", name: "fzf", ver: "0.54.3"),
  (asset: "gh_2.55.0_linux_amd64.deb", name: "gh", ver: "2.55.0"),
  (asset: "gnome-desktop-42.0", name: "gnome-desktop", ver: "42.0"),
  (asset: "helix-24.07-x86_64-linux.tar.xz", name: "helix", ver: "24.7"),
  (asset: "htop-3.3.0-1.el9.x86_64.rpm", name: "htop", ver: "3.3.0"),
  (asset: "jq-linux-riscv64", name: "jq", ver: ""),
  (asset: "lazygit_0.41.0_Linux_x86_64.tar.gz", name: "lazygit", ver: "0.41.0"),
  (asset: "leve-panel-1.1.0-1.x86_64.rpm", name: "leve-panel", ver: "1.1.0"),
  (asset: "lib-audacity-v2.1.0", name: "lib-audacity", ver: "2.1.0"),
  (asset: "lsd-musl_1.2.0_amd64.deb", name: "lsd-musl", ver: "1.2.0"),
  (asset: "lsd-musl_1.2.0_amd64_xz.deb", name: "lsd-musl", ver: "1.2.0"),
  (asset: "lsd-v1.2.0-x86_64-unknown-linux-gnu.tar.gz", name: "lsd", ver: "1.2.0"),
  (asset: "lsd_1.2.0_amd64_xz.deb", name: "lsd", ver: "1.2.0"),
  (asset: "micro-2.0.14-linux64-static.tar.gz", name: "micro", ver: "2.0.14"),
  (asset: "neofetch_7.1.0_all.deb", name: "neofetch", ver: "7.1.0"),
  (asset: "nvim-linux-x86_64.appimage", name: "neovim", ver: ""),
  (asset: "nvim-linux-x86_64.tar.gz", name: "neovim", ver: ""),
  (asset: "nvim.appimage", name: "neovim", ver: ""),
  (asset: "OBS-Studio-32.2.2-Ubuntu-26.04-x86_64.deb", name: "obs-studio", ver: "32.2.2"),
  (asset: "ripgrep-14.1.0-i386.deb", name: "ripgrep", ver: "14.1.0"),
  (asset: "ripgrep-14.1.0-x86_64-unknown-linux-musl.tar.gz", name: "ripgrep", ver: "14.1.0"),
  (asset: "ripgrep_14.1.0-1_amd64.deb", name: "ripgrep", ver: "14.1.0"),
  (asset: "tldr-linux-arm64", name: "tldr", ver: ""),
  (asset: "v1.2.3-beta", name: "unknown", ver: "1.2.3"),
  (asset: "VSCodium-1.135.06055-anylinux-x86_64.AppImage", name: "vscodium", ver: "1.135.6055"),
  (asset: "VSCodium-linux-x86_64-1.87.2.AppImage", name: "vscodium", ver: "1.87.2"),
  (asset: "vscodium_1.87.2_amd64.deb", name: "vscodium", ver: "1.87.2"),
  (asset: "yazi-x86_64-unknown-linux-gnu.deb", name: "yazi", ver: ""),
  (asset: "zoxide-0.10.0-src.zip", name: "zoxide", ver: "0.10.0"),
  (asset: "zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz", name: "zoxide", ver: "0.10.0"),
  (asset: "zoxide-0.9.4-aarch64-unknown-linux-musl.tar.gz", name: "zoxide", ver: "0.9.4"),
]

echo "\n  Nova - Unit Tests"

suite "Remote Source and Repository Tests":

  test "Extract Repository Name":
    for idx, tc in repoNameTestCases:
      let parsedRepo = getRepoName(tc.input)
      check parsedRepo == tc.expected
      checkpoint "[PASS] Idx (" & $idx & "): " & tc.input

  test "Identify Package Source Type":
    for idx, tc in sourceTypeTestCases:
      let parsedSource = getSourceType(tc.input)
      check parsedSource == tc.expected
      checkpoint "[PASS] Source Type Idx (" & $idx & "): " & tc.input

suite "Asset Validation Tests":

  test "Parse Package Name":
    for idx, tc in assetTestCases:
      let parsedName = getPackageName(tc.asset)
      check parsedName == tc.name
      checkpoint "[PASS] Idx (" & $idx & "): " & tc.asset

  test "Parse Package Version":
    for idx, tc in assetTestCases:
      let parsedVersion = normalizeVersion(tc.asset)
      check parsedVersion == tc.ver
      checkpoint "[PASS] Idx (" & $idx & "): " & tc.asset

suite "Version String Tests":

  test "Normalize Version":
    check normalizeVersion("v1.2.10") == "1.2.10"
    check normalizeVersion("bat-v0.24.0-x86_64") == "0.24.0"
    check normalizeVersion("fastfetch-linux-amd64.tar.gz") == ""
    check normalizeVersion("ripgrep_13.0.0_amd64.deb") == "13.0.0"
    check normalizeVersion("1.0") == "1.0" # Missing second dot sub-divider

  test "Compare Version Strings":
    # 1: v1 is newer, -1: v2 is newer, 0: identical
    check compareVersionStrings("1.2.10", "1.2.2") == 1
    check compareVersionStrings("1.10", "1.2.2") == 1
    check compareVersionStrings("10.0.1", "9.9.9") == 1
    check compareVersionStrings("1.2.2", "1.2.2") == 0
    check compareVersionStrings("1.0.0", "1.0") == 0
    check compareVersionStrings("2.1", "2.11") == -1
    check compareVersionStrings("", "2.11") == -1

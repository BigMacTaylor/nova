## Test suite for nova.
## Exercises module functionality using the standard unittest framework.

import std/[os, unittest, strutils]
import ../src/nova


let repoPath = getDataDir() / "repositories.json"
let pkgExtension = "deb"

# --- Test Data Arrays ---
let assetTestCases = @[
  (asset: "Audacity-4.0.1", name: "audacity", ver: "4.0.1"),
  (asset: "audacity-linux-4.0.1-x86_64.AppImage", name: "audacity", ver: "4.0.1"),
  (asset: "Audacity-v4.0.1+dfsg-1", name: "audacity", ver: "4.0.1"),
  (asset: "appimagelauncher_2.2.0-ghrelease+amd64.deb", name: "appimagelauncher", ver: "2.2.0"),
  (asset: "bat_0.24.0_amd64.deb", name: "bat", ver: "0.24.0"),
  (asset: "bat-v0.26.1-x86_64-unknown-linux-gnu.tar.gz", name: "bat", ver: "0.26.1"),
  (asset: "bat-v0.24.0-x86_64-unknown-linux-musl.tar.gz", name: "bat", ver: "0.24.0"),
  (asset: "bat-musl_0.26.1_arm64.deb", name: "bat-musl", ver: "0.26.1"),
  (asset: "bat-musl_0.26.1_musl-linux-amd64.deb", name: "bat-musl", ver: "0.26.1"),
  (asset: "bitwarden-2024.8.0-amd64.snap", name: "bitwarden", ver: "2024.8.0"),
  (asset: "btop-x86_64-linux-musl.tbz", name: "btop", ver: "none"),
  (asset: "btop-x86_64-unknown-linux-musl.tar.gz", name: "btop", ver: "none"),
  (asset: "cherry-studio_0.8.5_amd64.deb", name: "cherry-studio", ver: "0.8.5"),
  (asset: "Cherry-Studio-0.8.5-x86_64.AppImage", name: "cherry-studio", ver: "0.8.5"),
  (asset: "deb-get_0.4.0_all.deb", name: "deb-get", ver: "0.4.0"),
  (asset: "eza_x86_64-unknown-linux-gnu.tar.gz", name: "eza", ver: "none"),
  (asset: "eza_x86_64-unknown-linux-musl.tar.gz", name: "eza", ver: "none"),
  (asset: "fastfetch-linux-amd64.deb", name: "fastfetch", ver: "none"),
  (asset: "fastfetch-linux-amd64.tar.gz", name: "fastfetch", ver: "none"),
  (asset: "fastfetch-musl-amd64.tar.gz", name: "fastfetch", ver: "none"),
  (asset: "fd-musl_10.5.0_amd64.deb", name: "fd-musl", ver: "10.5.0"),
  (asset: "fd-v10.5.0-x86_64-unknown-linux-gnu.tar.gz", name: "fd", ver: "10.5.0"),
  (asset: "fd-v10.5.0-x86_64-unknown-linux-musl.tar.gz", name: "fd", ver: "10.5.0"),
  (asset: "fooyin-0.13.1-x86_64.AppImage", name: "fooyin", ver: "0.13.1"),
  (asset: "fooyin-0.13.1.fc43.x86_64.rpm", name: "fooyin", ver: "0.13.1"),
  (asset: "fzf-0.54.3-linux_amd64.tar.gz", name: "fzf", ver: "0.54.3"),
  (asset: "gh_2.55.0_linux_amd64.deb", name: "gh", ver: "2.55.0"),
  (asset: "gnome-desktop-42.0", name: "gnome-desktop", ver: "42.0"),
  (asset: "helix-24.07-x86_64-linux.tar.xz", name: "helix", ver: "24.07"),
  (asset: "htop-3.3.0-1.el9.x86_64.rpm", name: "htop", ver: "3.3.0"),
  (asset: "jq-linux-riscv64", name: "jq", ver: "none"),
  (asset: "lazygit_0.41.0_Linux_x86_64.tar.gz", name: "lazygit", ver: "0.41.0"),
  (asset: "lib-audacity-v2.1.0", name: "lib-audacity", ver: "2.1.0"),
  (asset: "lsd_1.2.0_amd64_xz.deb", name: "lsd", ver: "1.2.0"),
  (asset: "lsd-musl_1.2.0_amd64.deb", name: "lsd-musl", ver: "1.2.0"),
  (asset: "lsd-musl_1.2.0_amd64_xz.deb", name: "lsd-musl", ver: "1.2.0"),
  (asset: "lsd-v1.2.0-x86_64-unknown-linux-gnu.tar.gz", name: "lsd", ver: "1.2.0"),
  (asset: "micro-2.0.14-linux64-static.tar.gz", name: "micro", ver: "2.0.14"),
  (asset: "neofetch_7.1.0_all.deb", name: "neofetch", ver: "7.1.0"),
  (asset: "nvim.appimage", name: "neovim", ver: "none"),
  (asset: "nvim-linux-x86_64.appimage", name: "neovim", ver: "none"),
  (asset: "nvim-linux-x86_64.tar.gz", name: "neovim", ver: "none"),
  (asset: "OBS-Studio-32.2.2-Ubuntu-26.04-x86_64.deb", name: "obs-studio", ver: "32.2.2"),
  (asset: "ripgrep_14.1.0-1_amd64.deb", name: "ripgrep", ver: "14.1.0"),
  (asset: "ripgrep-14.1.0-x86_64-unknown-linux-musl.tar.gz", name: "ripgrep", ver: "14.1.0"),
  (asset: "tldr-linux-arm64", name: "tldr", ver: "none"),
  (asset: "vscodium_1.87.2_amd64.deb", name: "vscodium", ver: "1.87.2"),
  (asset: "VSCodium-linux-x86_64-1.87.2.AppImage", name: "vscodium", ver: "1.87.2"),
  (asset: "VSCodium-1.135.06055-anylinux-x86_64.AppImage", name: "vscodium", ver: "1.135.06055"),
  (asset: "v1.2.3-beta", name: "unknown", ver: "1.2.3"),
  (asset: "5.0.0+rc1", name: "unknown", ver: "5.0.0"),
  (asset: "yazi-x86_64-unknown-linux-gnu.deb", name: "yazi", ver: "none"),
  (asset: "zoxide-0.9.4-aarch64-unknown-linux-musl.tar.gz", name: "zoxide", ver: "0.9.4"),
  (asset: "zoxide-0.10.0-x86_64-unknown-linux-musl.tar.gz", name: "zoxide", ver: "0.10.0"),
]

# --- Automated Test Suite ---
suite "Asset Validation Tests":

  test "Parse Package Name":
    for idx, tc in assetTestCases:
      let parsedName = getPackageName(tc.asset, pkgExtension, repoPath)
      check parsedName == tc.name
      checkpoint "[PASS] Idx (" & $idx & "): " & tc.asset

  test "Parse Package Version":
    for idx, tc in assetTestCases:
      let parsedVersion = normalizeVersion(tc.asset)
      check parsedVersion == tc.ver
      checkpoint "[PASS] Idx (" & $idx & "): " & tc.asset

## Test suite for nova.
## Exercises module functionality using the standard unittest framework.

import std/[unittest, json]
import ../src/nova

# Test Repositories
let testJson = parseJson("""[
  {
    "tag_name": "v3.0.0-rc1",
    "prerelease": true,
    "assets": [{"name": "app_3.0.0_amd64.deb", "browser_download_url": "https://git/unstable"}]
  },
  {
    "tag_name": "v2.5.0",
    "prerelease": false,
    "assets": [{"name": "app_2.5.0_amd64.deb", "browser_download_url": "https://git/stable"}]
  }
]""")

let fastfetchJson = parseJson("""{
  "tag_name": "2.70.0",
  "prerelease": false,
  "assets": [
    {"name": "fastfetch-android-amd64.tar.gz", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-android-amd64.tar.gz"},
    {"name": "fastfetch-freebsd-amd64.pkg", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-freebsd-amd64.pkg"},
    {"name": "fastfetch-linux-aarch64.deb", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-aarch64.deb"},
    {"name": "fastfetch-linux-aarch64.tar.gz", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-aarch64.tar.gz"},
    {"name": "fastfetch-linux-amd64.deb", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.deb"},
    {"name": "fastfetch-linux-amd64.rpm", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.rpm"},
    {"name": "fastfetch-linux-amd64.tar.gz", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.tar.gz"},
    {"name": "fastfetch-linux-armv7l.rpm", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-armv7l.rpm"},
    {"name": "fastfetch-linux-armv7l.tar.gz", "browser_download_url": "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-armv7l.tar.gz"},
  ]
}""")

let yaziJson = parseJson("""[
  {
    "tag_name": "nightly",
    "prerelease": true,
    "assets": [
      {"name": "yazi-aarch64-unknown-linux-gnu.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-aarch64-unknown-linux-gnu.deb"},
      {"name": "yazi-aarch64-unknown-linux-gnu.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-aarch64-unknown-linux-gnu.zip"},
      {"name": "yazi-aarch64-unknown-linux-musl.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-aarch64-unknown-linux-musl.deb"},
      {"name": "yazi-aarch64-unknown-linux-musl.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-aarch64-unknown-linux-musl.zip"},
      {"name": "yazi-x86_64-unknown-linux-gnu.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-x86_64-unknown-linux-gnu.deb"},
      {"name": "yazi-x86_64-unknown-linux-gnu.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-x86_64-unknown-linux-gnu.zip"},
      {"name": "yazi-x86_64-unknown-linux-musl.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-x86_64-unknown-linux-musl.deb"},
      {"name": "yazi-x86_64-unknown-linux-musl.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-x86_64-unknown-linux-musl.zip"},
    ]
  },
  {
    "tag_name": "v26.9.1",
    "prerelease": false,
    "assets": [
      {"name": "yazi-aarch64-unknown-linux-gnu.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-gnu.deb"},
      {"name": "yazi-aarch64-unknown-linux-gnu.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-gnu.zip"},
      {"name": "yazi-aarch64-unknown-linux-musl.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-musl.deb"},
      {"name": "yazi-aarch64-unknown-linux-musl.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-musl.zip"},
      {"name": "yazi-x86_64-unknown-linux-gnu.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.deb"},
      {"name": "yazi-x86_64-unknown-linux-gnu.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.zip"},
      {"name": "yazi-x86_64-unknown-linux-musl.deb", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.deb"},
      {"name": "yazi-x86_64-unknown-linux-musl.zip", "browser_download_url": "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.zip"},
    ]
  }
]""")

echo "\n  Nova - Test Suite for repo_man"

suite "Architecture Parsing Tests":
  test "Exact asset matching":
    # Amd64 checks
    check(matchesArch("program-linux-x86_64.deb", "amd64") == true)
    check(matchesArch("program-linux-amd64.tar.gz", "amd64") == true)

    # Arm64 checks
    check(matchesArch("program-linux-aarch64.deb", "arm64") == true)
    check(matchesArch("program-linux-arm64.tar.gz", "arm64") == true)
    
    # Arm32 checks
    check(matchesArch("program-linux-armv7l.tar.gz", "arm64") == false)
    check(matchesArch("program-linux-armv7l.rpm", "armv7l") == true)

  test "Universal asset matching":
    # True generic scripts or resource tarballs
    check(isUniversal("theme-pack-all.zip") == true)
    check(isUniversal("compiler-universal.tar.gz") == true)
    
    # Target payloads that must be caught by architecture filters instead
    check(isUniversal("fastfetch-linux-amd64.deb") == false)
    check(isUniversal("fastfetch-linux-armv7l.tar.gz") == false)

suite "Repo Parsing Tests":
  test "Get Native Package Format":
    # Run a test targeting apt on x86_64 architecture
    var asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "apt", "amd64", false, false)
    check(asset.name == "fastfetch-cli/fastfetch")
    check(asset.prerelease == false)
    check(asset.preferMusl == false)
    check(asset.pkgName == "fastfetch")
    check(asset.pkgType == Deb)
    check(asset.version == "2.70.0")
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.deb")

    # Run a test targeting dnf on x86_64 architecture
    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "dnf", "amd64", false, false)
    check(asset.name == "fastfetch-cli/fastfetch")
    check(asset.prerelease == false)
    check(asset.preferMusl == false)
    check(asset.pkgName == "fastfetch")
    check(asset.pkgType == Rpm)
    check(asset.version == "2.70.0")
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.rpm")

    # Run a test targeting pacman on x86_64 architecture
    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "pacman", "amd64", false, false)
    check(asset.name == "fastfetch-cli/fastfetch")
    check(asset.prerelease == false)
    check(asset.preferMusl == false)
    check(asset.pkgName == "fastfetch")
    check(asset.pkgType == Binary)
    check(asset.version == "2.70.0")
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.tar.gz")

    # Run a test targeting apt on x86_64 architecture
    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "amd64", false, false)
    check(asset.name == "sxyazi/yazi")
    check(asset.prerelease == false)
    check(asset.preferMusl == false)
    check(asset.pkgName == "yazi")
    check(asset.pkgType == Deb)
    check(asset.version == "26.9.1")
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.deb")

  test "Get Native Architecture":
    # Run test specifying explicit CPU parameter, such as "arm64"
    var asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "pacman", "amd64", false, false)
    check(asset.pkgType == Binary)
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.tar.gz")

    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "pacman", "arm64", false, false)
    check(asset.pkgType == Binary)
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-aarch64.tar.gz")

    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "pacman", "arm", false, false)
    check(asset.pkgType == Binary)
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-armv7l.tar.gz")

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "arm64", false, false)
    check(asset.pkgType == Deb)
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-aarch64-unknown-linux-gnu.deb")

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "arm64", true, false)
    check(asset.pkgType == Deb)
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-aarch64-unknown-linux-gnu.deb")

  test "Pre-Release Filtering":
    # Enable parsing prereleases
    var asset = getBestAsset(testJson, "mac-taylor/app", "apt", "amd64", true, false)
    check(asset.prerelease == true)
    check(asset.version == "3.0.0")
    check(asset.downloadUrl == "https://git/unstable")

    asset = getBestAsset(testJson, "mac-taylor/app", "apt", "amd64", false, false)
    check(asset.prerelease == false)
    check(asset.version == "2.5.0")
    check(asset.downloadUrl == "https://git/stable")

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "amd64", true, false)
    check(asset.prerelease == true)
    check(asset.version == "")
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/nightly/yazi-x86_64-unknown-linux-gnu.deb")

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "amd64", false, false)
    check(asset.prerelease == false)
    check(asset.version == "26.9.1")
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.deb")

    # Fallback if prerelease not found
    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "apt", "amd64", true, false)
    check(asset.prerelease == true)
    check(asset.version == "2.70.0")
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.deb")

  test "Prefer Musl Selection":
    # Enforce preferMusl parameter
    var asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "amd64", false, true)
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.deb")
    check(asset.preferMusl == true)

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "dnf", "amd64", false, true)
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-musl.zip")
    check(asset.preferMusl == true)

    asset = getBestAsset(yaziJson, "sxyazi/yazi", "apt", "amd64", false, false)
    check(asset.downloadUrl == "https://github.com/sxyazi/yazi/releases/download/v26.9.1/yazi-x86_64-unknown-linux-gnu.deb")
    check(asset.preferMusl == false)

    # Fallback if musl not found
    asset = getBestAsset(fastfetchJson, "fastfetch-cli/fastfetch", "dnf", "amd64", false, true)
    check(asset.downloadUrl == "https://github.com/fastfetch-cli/fastfetch/releases/download/2.70.0/fastfetch-linux-amd64.rpm")
    check(asset.preferMusl == true)

  test "Empty Payload Fallback":
    let emptyJson = parseJson("""[
      {"tag_name": "v1.0.0", "assets": []}
    ]""")
    
    let asset = getBestAsset(emptyJson, "mac-taylor/empty", "apt", "amd64", false, false)
    
    # Return empty fields if no asset found
    check(asset.name == "")
    check(asset.pkgName == "")
    check(asset.version == "")
    check(asset.downloadUrl == "")

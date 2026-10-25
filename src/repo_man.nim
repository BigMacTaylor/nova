# ========================================================================================
#
#                                   Nova
#                               Repo Manager
#
# ========================================================================================

proc getBestAsset*(releasesJson: JsonNode, repoPath, pkgMan: string): Repo =
  ## Filters and scores assets across one or more releases, returning a completed Repo structure.
  # Fallback return empty
  result = (name: repoPath, pkgName: "", pkgType: Binary, version: "", downloadUrl: "")

  var bestRelease: JsonNode = nil
  var bestAsset: JsonNode = nil
  var bestScore = -1
  var finalPkgType = Binary

  let isAmd64 = hostCPU == "amd64"
  let isArm64 = hostCPU == "arm64"
  let pkgExtension = case pkgMan
    of "apt", "nala": "deb"
    of "dnf", "yum", "zypper": "rpm"
    of "pacman": "pkg.tar.zst"
    else: ""

  # Normalize JSON structure to always be an array sequence
  let releases =
    if releasesJson.kind == JArray: releasesJson 
    else: (let a = newJArray(); a.add(releasesJson); a)

  # Search through releases (optionally prereleases)
  for release in releases:
    let tagName = release["tag_name"].getStr().toLowerAscii()
    debug "Found release: ", tagName, " for repo: ", repoPath
    let isPrerelease = release.getOrDefault("prerelease").getBool(false)
    let assets = release.getOrDefault("assets")

    if assets.kind != JArray or assets.len == 0:
      debug "No compiled assets found"
      continue

    # Calculate release tier score base
    # Asset Release Weight (Base 0, 100, or 200)
    var releaseScore = 200 # Default to Stable

    # Filter pre-releases if not included
    if not includePrerelease:
      if isPrerelease: 
        continue
      const preReleaseKeywords = ["alpha", "beta", "dev", "nightly", "preview", "rc"]
      var isUnstable = false
      for kw in preReleaseKeywords:
        if kw in tagName:
          isUnstable = true
          break
      if isUnstable: 
        continue

    # If this release tier can't beat the current best score, skip it
    if releaseScore + 35 < bestScore:
      continue

    # Search through assets
    for asset in assets:
      let assetName = asset["name"].getStr().toLowerAscii()
      debug "Found asset: ", assetName

      # Block non-Linux formats and tags
      const blockedTags = [
        ".exe", ".msi", ".dmg", ".pkg",
        "windows", "win32", "win64",
        "macos", "darwin", "apple", "osx",
        "freebsd", "openbsd", "netbsd", "bsd",
        "android", "haiku", "dragonfly",
        "solaris", "sunos", "illumos", "omnios",
      ]
      var skipAsset = false
      for tag in blockedTags:
        if tag in assetName:
          skipAsset = true
          break

      if skipAsset:
        continue

      # Architecture & Package Format detection
      # Prefered Format Weight (0 to 30)
      var formatScore = -1
      var detectedType: PkgType

      let matchesArch =
        (isAmd64 and ("amd64" in assetName or "x86_64" in assetName)) or
        (isArm64 and ("arm64" in assetName or "aarch64" in assetName)) or
        ("all" in assetName or "noarch" in assetName) or
        (not isAmd64 and not isArm64 and hostCPU in assetName)

      let isUniversal =
        "universal" in assetName or 
        "multi" in assetName or
        not (assetName.contains("x86_64") or 
          assetName.contains("amd64") or 
          assetName.contains("arm64") or 
          assetName.contains("aarch64") or 
          assetName.contains("386") or 
          assetName.contains("arm") or
          assetName.contains("mips"))

      # Native packages (.deb, .rpm, .pkg.tar.zst)
      if pkgExtension.len > 0 and assetName.endsWith("." & pkgExtension):
        detectedType = case pkgExtension
          of "deb": Deb
          of "rpm": Rpm
          else: Pacman
        if matchesArch:
          debug "Found matching package asset: ", assetName
          formatScore = 30  # Highest priority format
        elif isUniversal:
          debug "Found universal package asset: ", assetName
          formatScore = 28  # Slightly lower score so exact matches win if present
        else:
          continue

      # Appimages
      elif assetName.endsWith(".appimage"):
        detectedType = AppImage
        if matchesArch:
          debug "Found matching AppImage asset: ", assetName
          formatScore = 20  # Mid priority format
        elif isUniversal:
          debug "Found universal AppImage asset: ", assetName
          formatScore = 18  # Slightly lower score so exact matches win if present
        else:
          continue

      # Binaries
      elif assetName.endsWith(".tar.gz") or assetName.endsWith(".tar.xz") or assetName.endsWith(".zip") or not assetName.contains("."):
        detectedType = Binary
        if matchesArch:
          debug "Found matching binary archive: ", assetName
          formatScore = 10  # Low priority binary archive
        elif isUniversal:
          debug "Found universal binary archive: ", assetName
          formatScore = 8
        else:
          continue

      # Skip documentation, shasums, or source code
      else:
        continue

      # Prefered Lib Weight (0 or 5)
      let isMusl = "musl" in assetName
      let libScore = if isMusl == preferMusl: 5 else: 0

      # Calculate Total Asset Score
      let totalScore = releaseScore + formatScore + libScore

      if totalScore > bestScore:
        bestScore = totalScore
        bestRelease = release
        bestAsset = asset
        finalPkgType = detectedType

        # Found stable, native, preferred-lib package
        if bestScore == 235: break

    # Found stable, native/appimage
    if bestScore > 210:
      break
    else:
      debug "Package score: ", bestScore, ". Skipping..."

  # Process and return best matching asset
  if bestAsset != nil and bestRelease != nil:
    debug "Selected payload: ", bestAsset["name"].getStr()
    debug "Asset Score: ", $bestScore
    debug "Asset Tag Name: ", bestRelease["tag_name"].getStr()
    debug "Asset URL: ", bestAsset["browser_download_url"].getStr()

    return (
      name: repoPath,
      pkgName: getPackageName(bestAsset["name"].getStr()),
      pkgType: finalPkgType,
      version: normalizeVersion(bestRelease["tag_name"].getStr()),
      downloadUrl: bestAsset["browser_download_url"].getStr()
    )
  return result

proc getReleasesJson(repoPath: string): Future[JsonNode] {.async.} =
  ## Handles API network routing.
  let ctx = if disableSSL: newContext(verifyMode = CVerifyNone) else: newContext()
  let client = newAsyncHttpClient(sslContext = ctx)
  client.headers = newHttpHeaders({"User-Agent": "Nova-Package-Manager"})
  client.timeout = 30000

  let url =
    if includePrerelease:
     "https://api.github.com/repos/" & repoPath & "/releases"
    else:
     "https://api.github.com/repos/" & repoPath & "/releases/latest"

  try:
    let response = await client.getContent(url)
    result = parseJson(response)
  except HttpRequestError as e:
    if not includePrerelease and "404" in e.msg:
      debug "No latest release found, searching for releases..."
      let fallbackUrl = "https://api.github.com/repos/" & repoPath & "/releases"
      try:
        let response = await client.getContent(fallbackUrl)
        result = parseJson(response)
      except HttpRequestError as e:
        errorMsg("Failed to fetch data: ", e.msg)
    else:
      raise e
  finally:
    client.close()

proc getRepoData(pkgMan, repoPath: string): Future[Repo] {.async.} =
  ## Fetches and scores assets in repo to discover an installable package.
  infoMsg("Fetching latest release for \'" & repoPath & "\'...")

  # Fallback return empty
  result = (name: repoPath, pkgName: "", pkgType: Binary, version: "", downloadUrl: "")
  
  var releasesJson: JsonNode
  try:
    releasesJson = await getReleasesJson(repoPath)
  except JsonParsingError:
    errorMsg("Failed to parse response. You might be rate-limited by GitHub API.")
    return result
  except CatchableError as e:
    errorMsg("Network error trying to get latest release for \'" & repoPath & "\': " & e.msg)
    return result

  # Get best matching asset from releases
  let matchedRepo = getBestAsset(releasesJson, repoPath, pkgMan)
  if matchedRepo.downloadUrl.len > 0:
    successMsg("Found installable package \'", matchedRepo.pkgName, "\' version: ", matchedRepo.version)
    return matchedRepo

  errorMsg("Could not find installable package for: ", repoPath)
  return result

# ----------------------------------------------------------------------------------------
#                                    Upgrade
# ----------------------------------------------------------------------------------------

proc upgradeGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found. Skipping git packages.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    return

  infoMsg("Checking installed packages against manifest...")

  for entry in repoList:
    let pkgName = entry.getOrDefault("pkg_name").getStr("")
    let manifestVer = entry.getOrDefault("version").getStr("")
    let downloadUrl = entry.getOrDefault("download_url").getStr("")
    let pkgType =
      try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
      except ValueError: Binary

    if pkgName.len == 0 or downloadUrl.len == 0:
      debug "Skipping incomplete or malformed entry in manifest."
      continue

    # Get currently installed version
    let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)
    if installedVer.len == 0:
      debug "Package '" & pkgName & "' not found on host system. Skipping..."
      continue

    # Check if it's out of date
    if compareVersionStrings(manifestVer, installedVer) == 1:
      infoMsg(
        "Upgrade detected for '" & pkgName & "': Local (" & installedVer &
          ") -> Tracked (" & manifestVer & ")")

      # Install Package
      waitFor installGitPkg(pkgMan, entry)

    else:
      debug(pkgName & " [" & installedVer & "] is already current.")

  successMsg("All git packages are up to date.")

# ----------------------------------------------------------------------------------------
#                                    Refresh
# ----------------------------------------------------------------------------------------

proc refreshGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found. Nothing to update.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("Repository manifest is empty. Nothing to update.")
    return

  infoMsg("Checking Git repos for updates...")

  var futures: seq[Future[Repo]] = @[]
  var mappedRepos: seq[JsonNode] = @[]

  for entry in repoList:
    if entry.hasKey("repo"):
      let repoPath = entry["repo"].getStr()
      futures.add(getRepoData(pkgMan, repoPath))
      mappedRepos.add(entry)

  try:
    discard await all(futures)
  except CatchableError as e:
    debug("Some repository updates encountered network issues: " & e.msg)

  var updatedCount = 0
  for i, future in futures:
    let entry = mappedRepos[i]

    # Check if asynchronous operation succeeded before reading
    if not future.finished or future.failed:
      let repoName = entry.getOrDefault("repo").getStr("unknown")
      warnMsg("Skipping update check for \'" & repoName & "\' due to network failure.")
      continue

    let repoData = future.read()
    let oldVersion = entry.getOrDefault("version").getStr("")

    if repoData.version.len > 0 and oldVersion != repoData.version:
      infoMsg(
        "New version found for " & repoData.name & ": " &
        (if oldVersion.len > 0: oldVersion else: "None") & " -> " &
        repoData.version
      )
      entry["version"] = newJString(repoData.version)
      entry["download_url"] = newJString(repoData.downloadUrl)
      inc(updatedCount)

  if updatedCount > 0:
    try:
      writeFile(repoFile, repoList.pretty())
      successMsg("Successfully updated manifest.")
    except IOError:
      errorMsg("Could not save changes to manifest.")
  else:
    successMsg("All packages are already up to date!")

# ----------------------------------------------------------------------------------------
#                                    Remove
# ----------------------------------------------------------------------------------------

proc removeGitRepo(repoInput: string) =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found. Nothing to remove.")
    return

  let targetRepo = getRepoName(repoInput)
  let repoList = loadOrCreateRepoList(repoFile)
  let updatedList = newJArray()
  var removed = false

  for entry in repoList:
    if entry.hasKey("repo") and
        entry["repo"].getStr().toLowerAscii() == targetRepo.toLowerAscii():
      removed = true
    else:
      updatedList.add(entry)

  if removed:
    try:
      writeFile(repoFile, updatedList.pretty())
      successMsg("Removed \'" & targetRepo & "\' from manifest.")
    except IOError:
      errorMsg("Could not save changes to manifest.")
  else:
    errorMsg("Repository \'" & targetRepo & "\' not found.")

# ----------------------------------------------------------------------------------------
#                                    Add
# ----------------------------------------------------------------------------------------

proc addGitRepo(pkgMan, repoInput: string) {.async.} =
  let repoPath = getRepoName(repoInput)
  if repoPath.len == 0 or not repoPath.contains("/"):
    errorMsg("Invalid repository format. Use 'owner/repo' or a full GitHub URL.")
    return

  let repoList = loadOrCreateRepoList(repoFile)

  for entry in repoList:
    let entryRepo = entry.getOrDefault("repo").getStr("").toLowerAscii()
    if entryRepo.len > 0 and entryRepo == repoPath.toLowerAscii():
      infoMsg "Repository \'" & repoPath & "\' is already in manifest."
      return

  let repoData = await getRepoData(pkgMan, repoPath)
  if repoData.version == "":
    errorMsg("Could not add repo \'" & repoPath & "\'")
    quit(1)

  let newEntry = %*{
    "repo": repoData.name,
    "pkg_name": repoData.pkgName,
    "pkg_type": repoData.pkgType,
    "version": repoData.version,
    "download_url": repoData.downloadUrl,
  }
  repoList.add(newEntry)

  try:
    writeFile(repoFile, repoList.pretty())
    successMsg("Added \'" & repoPath & "\' to manifest")
  except IOError:
    errorMsg("Could not save changes to manifest.")

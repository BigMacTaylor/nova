# ========================================================================================
#
#                                   Nova
#                               Repo Manager
#
# ========================================================================================

proc downloadLatestRelease(downloadUrl: string): Future[string] {.async.} =
  ## Downloads a file from the provided direct URL into a temporary cache folder.
  ## Returns the absolute path of the downloaded file, or "" if the download fails.

  # Parse filename from the end of the download URL
  let fileInfo = downloadUrl.splitFile()
  let assetName = fileInfo.name & fileInfo.ext

  if assetName.len == 0 or fileInfo.ext.len == 0:
    errorMsg("Could not deduce a valid package filename from URL: " & downloadUrl)
    return ""

  infoMsg("Downloading package \'" & assetName & "\'...")
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"User-Agent": "Nova-Package-Manager"})
  client.timeout = 30000

  try:
    let uid = getuid()
    let cacheDir = getTempDir() / "nova-cache-" & $uid
    createDir(cacheDir)
    let destFile = cacheDir / assetName

    await client.downloadFile(downloadUrl, destFile)
    debug "Downloaded package to: " & destFile
    return destFile
  except CatchableError as e:
    errorMsg("Failed to download package binary: " & e.msg)
    return ""
  finally:
    client.close()

proc getLatestRelease(repoPath: string, pkgExtension: string): Future[Repo] {.async.} =
  infoMsg("Fetching latest release from \'" & repoPath & "\'...")
  let isAmd64 = hostCPU == "amd64"
  let isArm64 = hostCPU == "arm64"
  let url = "https://api.github.com/repos/" & repoPath & "/releases"
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"User-Agent": "Nova-Package-Manager"})
  client.timeout = 30000

  # Fallback return empty
  result = (name: repoPath, pkgName: "", pkgType: pkgBinary, version: "", downloadUrl: "")

  try:
    debug "Scanning \'" & repoPath & "\' for releases..."
    let response = await client.getContent(url)
    let jsonNode = parseJson(response)

    if jsonNode.len == 0:
      warnMsg("No releases found for this repository.")
      return result

    var bestRelease: JsonNode = nil
    var bestAsset: JsonNode = nil
    var bestScore = -1 
    var finalPkgType: PkgType = pkgBinary


    # Search through releases (optionally prereleases)
    for release in jsonNode:
      let tagName = release["tag_name"].getStr().toLowerAscii()
      infoMsg("Found release: ", tagName)
      let isPrerelease = release.getOrDefault("prerelease").getBool(false)
      let assets = release["assets"]

      if assets.len == 0:
        debug "No compiled assets found"
        continue

      # Asset Release Weight (Base 0, 100, or 200)
      var releaseScore = 200 # Default to Stable

      if not includePrerelease:
        if "nightly" in tagName or "dev" in tagName:
          releaseScore = 0
        elif isPrerelease or "beta" in tagName or "alpha" in tagName or "rc" in tagName or "preview" in tagName:
          releaseScore = 100
      else:
        # If --include-prerelease is enabled, collapse all tiers to evaluate chronologically
        releaseScore = 200

      # If this release tier can't beat the current best score, skip it
      if releaseScore + 30 + 5 < bestScore:
        continue

      # Search through assets
      for asset in assets:
        let assetName = asset["name"].getStr().toLowerAscii()
        debug "Found asset: ", assetName

        # Asset Format Weight (0 to 30)
        var formatScore = -1
        var detectedType: PkgType

        if pkgExtension.len > 0 and assetName.endsWith("." & pkgExtension):
          let matchesArch =
            (isAmd64 and ("amd64" in assetName or "x86_64" in assetName)) or
            (isArm64 and ("arm64" in assetName or "aarch64" in assetName)) or
            ("all" in assetName or "noarch" in assetName) or
            (not isAmd64 and not isArm64 and hostCPU in assetName)

          if matchesArch:
            debug "Found matching assat: ", assetName
            detectedType = if pkgExtension == "deb": pkgDeb else: pkgRpm
            formatScore = 30  # Highest priority format
          else:
            continue

        elif assetName.endsWith(".appimage"):
          detectedType = pkgAppImage
          formatScore = 20  # Mid priority format
          # TODO add appimage support
          continue

        elif assetName.endsWith(".tar.gz") or assetName.endsWith(".tar.xz") or assetName.endsWith(".zip") or not assetName.contains("."):
          debug "Asset is not a valid package: ", assetName
          detectedType = pkgBinary
          formatScore = 10  # Low priority binary archive
          # TODO add binary support
          continue
        else:
          continue # Skip documentation, shasums, or source code

        # Prefered Lib Weight (0 or 5)
        var libScore = 0
        let isMusl = "musl" in assetName.toLowerAscii()

        if preferMusl == isMusl:
          libScore = 5

        # Calculate Total Asset Score
        let currentAssetScore = releaseScore + formatScore + libScore

        if currentAssetScore > bestScore:
          bestScore = currentAssetScore
          bestRelease = release
          bestAsset = asset
          finalPkgType = detectedType

          # Found stable, native, preferred-lib package, quit parsing assets
          if bestScore == 235: 
            break
      # Found stable, native/appimage, quit parsing releases
      if bestScore > 210:
        break
      else:
        warnMsg("Could not find package for your architecture.")

    # Process and return the best matching asset
    if bestAsset != nil and bestRelease != nil:
      let finalAssetName = bestAsset["name"].getStr()
      debug "Selected payload: ", finalAssetName
      debug "Asset Score: ", $bestScore

      let downloadUrl = bestAsset["browser_download_url"].getStr()
      let tagName = bestRelease["tag_name"].getStr()

      successMsg("Found installable package \'", finalAssetName, "\'")
      let packageName = getPackageName(finalAssetName, pkgExtension, repoPath)

      return (
        name: repoPath,
        pkgName: packageName,
        pkgType: finalPkgType,
        version: normalizeVersion(tagName),
        downloadUrl: downloadUrl,
      )

    errorMsg("Failed to find matching package for your architecture.")
    return result

  except HttpRequestError as e:
    errorMsg("Failed to fetch data: ", e.msg)
  except JsonParsingError:
    errorMsg("Failed to parse response. You might be rate-limited by GitHub API.")
  except CatchableError as e:
    errorMsg("Network error trying to get latest release for \'" & repoPath & "\': " & e.msg)
  finally:
    client.close()

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

  let ext =
    case pkgMan
    of "apt", "nala": "deb"
    of "dnf", "yum", "zypper": "rpm"
    else: ""

  let repoData = await getLatestRelease(repoPath, ext)
  if repoData.version == "":
    errorMsg("Could not add repo \'" & repoPath & "\'")
    quit(1)

  let newEntry = %*{
    "repo": repoData.name,
    "pkg_name": repoData.pkgName,
    "version": repoData.version,
    "download_url": repoData.downloadUrl,
  }
  repoList.add(newEntry)

  try:
    writeFile(repoFile, repoList.pretty())
    successMsg("Added \'" & repoPath & "\' to manifest")
  except IOError:
    errorMsg("Could not save changes to manifest.")

proc refreshGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found. Nothing to update.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("Repository manifest is empty. Nothing to update.")
    return

  infoMsg("Checking Git repos for updates...")
  let ext =
    case pkgMan
    of "apt", "nala": "deb"
    of "dnf", "yum", "zypper": "rpm"
    else: ""

  var futures: seq[Future[Repo]] = @[]
  var mappedRepos: seq[JsonNode] = @[]

  for entry in repoList:
    if entry.hasKey("repo"):
      let repoPath = entry["repo"].getStr()
      futures.add(getLatestRelease(repoPath, ext))
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
        (if oldVersion.len > 0: oldVersion else: "None") & " ➡️ " &
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

proc upgradeGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found. Skipping git packages.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    return

  infoMsg("Checking installed packages against manifest...")

  for entry in repoList:
    let repoPath = entry.getOrDefault("repo").getStr("")
    let pkgName = entry.getOrDefault("pkg_name").getStr("")
    let manifestVer = entry.getOrDefault("version").getStr("")
    let downloadUrl = entry.getOrDefault("download_url").getStr("")

    if pkgName.len == 0 or downloadUrl.len == 0:
      debug "Skipping incomplete or malformed entry in manifest."
      continue

    # Get currently installed version
    let installedVer = getInstalledOSVersion(pkgMan, pkgName)

    # Check if it's missing or out of date
    let isMissing = installedVer == ""
    let isOutdated = (normalizeVersion(manifestVer) > normalizeVersion(installedVer)) and (manifestVer.len > 0)

    if isMissing or isOutdated:
      if isMissing:
        infoMsg(
          "Package '" & pkgName & "' is not present on the host system. Skipping..."
        )
        continue
      else:
        infoMsg(
          "Upgrade detected for '" & pkgName & "': Local (" & installedVer &
            ") ➡️ Tracked (" & manifestVer & ")"
        )

      # Fetch the latest asset release from downloadUrl
      let downloadedPayload = await downloadLatestRelease(downloadUrl)

      if downloadedPayload.len > 0 and fileExists(downloadedPayload):
        let installCmd = getNativeCommand(pkgMan, actInstall, downloadedPayload)
        infoMsg("Executing native installer: " & installCmd)
        let exitCode = execCmd(installCmd)

        if downloadedPayload.contains(getTempDir()):
          discard tryRemoveFile(downloadedPayload)

        if exitCode == 0:
          successMsg("Successfully installed package " & pkgName)
        else:
          errorMsg("Native package manager failed during execution for " & pkgName)
      else:
        errorMsg("Failed to download package " & pkgName)
    else:
      debug(pkgName & " [" & installedVer & "] is already current.")

  successMsg("All git packages are up to date.")

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

proc listGitUpdates(pkgMan: string) =
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("The repository manifest is empty.")
    return

  let headPkg = "Package Name"
  let headInstalled = "Installed"
  let headLatest = "Latest"

  var updatesCount = 0
  var headerPrinted = false

  for entry in repoList:
    if not (entry.hasKey("repo") and entry.hasKey("pkg_name") and entry.hasKey("version")):
      continue

    let pkgName = entry["pkg_name"].getStr()
    let manifestVer = entry["version"].getStr()

    # Get currently installed version
    let installedVer = getInstalledOSVersion(pkgMan, pkgName)

    # Check if it's missing or out of date
    let isMissing = installedVer == ""
    let isOutdated = (normalizeVersion(manifestVer) > normalizeVersion(installedVer)) and (manifestVer.len > 0)

    if isMissing or isOutdated:
      # Defer formatting header until we are certain an update row is active
      if not headerPrinted:
        styledWriteLine(
          stdout, fgWhite, styleBright, "\nAvailable Updates for Git Applications:",
          resetStyle,
        )
        echo "  " & headPkg.alignLeft(32) & " " & headInstalled.alignLeft(20) & " " &
          headLatest
        echo "  " & "-".repeat(68)
        headerPrinted = true

      if isMissing:
        stdout.write "  " & pkgName.alignLeft(32)
        styledWrite(stdout, fgYellow, "Not Installed".alignLeft(22))
      else:
        stdout.write "  " & pkgName.alignLeft(35)
        styledWrite(stdout, styleBright, fgGreen, installedVer.alignLeft(19))

      styledWriteLine(stdout, styleBright, fgBlue, " " & manifestVer)
      inc(updatesCount)

  if updatesCount == 0:
    successMsg("All git packages are up to date.")
  else:
    echo "\nRun 'nova upgrade' to apply these updates.\n"

proc listGitReposNew() =
  if not fileExists(repoFile):
    infoMsg("No repositories saved yet. \'" & repoFile & "\' does not exist.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("The repository list is empty.")
    return

  styledEcho(fgWhite, styleBright, "\nGit Repositories:", resetStyle)

  # Format Table Header for clarity
  let headRepo = "Repository"
  let headPkg = "Package"
  let headVer = "Version"
  echo "  " & headRepo.alignLeft(30) & " " & headPkg.alignLeft(20) & " [" & headVer & "]"
  echo "  " & "-".repeat(70)

  for entry in repoList:
    if entry.hasKey("repo") and entry.hasKey("version"):
      let repoStr = entry["repo"].getStr()
      let versionStr = entry["version"].getStr()

      # Pull down the true native package name, fallback gracefully if not yet populated
      let pkgStr =
        if entry.hasKey("pkg_name"):
          entry["pkg_name"].getStr()
        else:
          "unknown"

      # Output aligned text components smoothly
      echo "  • " & repoStr.alignLeft(28) & " " & pkgStr.alignLeft(20) & " [" &
        versionStr & "]"

proc listGitRepos() =
  let termWidth = getTermWidth()
  echo ""
  styledEcho(fgWhite, styleBright, "Git Repositories:", resetStyle)

  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("No repositories saved yet.")
    return

  for entry in repoList:
    if entry.hasKey("repo") and entry.hasKey("version"):
      let repoStr = entry["repo"].getStr()
      echo "  ", repoStr
  echo ""

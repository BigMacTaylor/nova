# ========================================================================================
#
#                                   Nova
#                               Repo Manager
#
# ========================================================================================

proc getInstalledOSVersion(pkgMan, pkgName: string): string =
  ## Returns the version string natively installed on the host machine.
  ## Returns "" if the package is missing or not installed.
  let nativeCmd = getNativeCommand(pkgMan, actStatus, pkgName)
  let (output, exitCode) = execCmdEx(nativeCmd)
  let cleanOut = output.strip()
  
  if exitCode == 0 and cleanOut.len > 0:
    let components = cleanOut.split('|')
    case pkgMan
    of "apt":
      # Your apt query format maps to: ${Status}|${Version}|${Installed-Size}
      if components.len >= 2 and "installed" in components[0].toLowerAscii():
        return components[1].strip()
    of "dnf":
      # Your dnf query format maps to: installed|%{VERSION}|%{SIZE}
      if components.len >= 2 and components[0].strip() == "installed":
        return components[1].strip()
    else: discard
  return ""

proc loadOrCreateRepoList(fileName: string): JsonNode =
  if fileExists(fileName):
    try:
      return parseFile(fileName)
    except JsonParsingError:
      warnMsg "Could not parse JSON file. Starting fresh."
      return newJArray()
  else:
    try:
      let dir = splitFile(fileName).dir
      if dir != "":
        createDir(dir)
      
      # Create the file with a valid empty JSON array
      writeFile(fileName, "[]")
      return newJArray()
    except IOError as e:
      errorMsg "Could not create file or directory due to system permissions: " & e.msg
      return newJArray()

proc getRepoType(target: string): RepoType =
  let clean = target.toLowerAscii().strip()

  if clean.startsWith("ppa:"):
    return repoPpa
  elif clean.contains("github.com"):
    return repoGithubRelease
  elif clean.contains("gitlab.com"):
    return repoGitlabRelease
  elif clean.split('/').len == 2:
    return repoGithubRelease
  else:
    return repoGenericUrl

proc getRepoName(target: string): string =
  var clean = target.strip()

  let prefixes = [
    "https://github.com", "http://github.com", "git@github.com:", "://github.com",
    "https://gitlab.com", "http://gitlab.com", "git@gitlab.com:", "://gitlab.com"
  ]

  for prefix in prefixes:
    if clean.toLowerAscii().startsWith(prefix):
      clean = clean.substr(prefix.len)
      break

  # 2. Remove leading slashes if they linger
  clean = clean.strip(leading = true, trailing = false, chars = {'/'})

  # 3. Clean up trailing ".git" securely using Nim's endswith/substr
  if clean.toLowerAscii().endsWith(".git"): 
    clean = clean.substr(0, clean.len - 5) # -5 because substr end-index is inclusive

  # 4. Isolate the base 'owner/repo' component from deep paths
  let parts = clean.split('/')
  if parts.len >= 2:
    return parts[0] & "/" & parts[1]
    
  return clean






proc getLatestRelease(repoPath: string, pkgExtension: string): Future[Repo] {.async.} =
  debug "Fetching compiled binaries for " & repoPath & "..."
  let isAmd64 = hostCPU == "amd64"
  let isArm64 = hostCPU == "arm64"
  let url = "https://api.github.com/repos/" & repoPath & "/releases"
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({ "User-Agent": "Nim-Release-Scanner" })

  # Fallback return initialized with empty metrics
  result = (name: repoPath, pkgName: "", version: "", downloadUrl: "")

  try:
    echo "Scanning releases for " & repoPath & "..."
    let response = await client.getContent(url)
    let jsonNode = parseJson(response)
    
    if jsonNode.len == 0:
      warnMsg("No releases found for this repository.")
      return result

    for release in jsonNode:
      let tagName = release["tag_name"].getStr()
      let assets = release["assets"]

      if assets.len == 0:
        warnMsg("No compiled assets found")
      else:
        for asset in assets:
          let assetName = asset["name"].getStr()
          let downloadUrl = asset["browser_download_url"].getStr()
          debug "found name: ", assetName
          
          if assetName.endsWith("." & pkgExtension):
            let matchesArch =
              (isAmd64 and ("amd64" in assetName or "x86_64" in assetName)) or
              (isArm64 and ("arm64" in assetName or "aarch64" in assetName)) or
              ("all" in assetName or "noarch" in assetName) or
              (not isAmd64 and not isArm64 and hostCPU in assetName)

            if matchesArch:
              successMsg("Found installable package asset: ", assetName)
              
              # SAFE PARSING: Extract package name before the first '_' (DEB) or '-' (RPM)
              # e.g., "ripgrep_14.1.0_amd64.deb" -> "ripgrep"
              # e.g., "bat-v0.24.0-x86_64.rpm" -> "bat"
              let separator = if pkgExtension == "deb": '_' else: '-'
              let nameParts = assetName.split(separator)
              let extractedPkgName = if nameParts.len > 0: nameParts[0] else: repoPath.split('/')[1]

              return (
                name: repoPath, 
                pkgName: extractedPkgName, 
                version: tagName, 
                downloadUrl: downloadUrl
              )

        warnMsg("Failed to find matching package for your architecture")

    return result

  except HttpRequestError as e:
    errorMsg("Failed to fetch data: ", e.msg)
  except JsonParsingError:
    errorMsg("Failed to parse response. You might be rate-limited by GitHub API.")
  except CatchableError as e:
    errorMsg("Failed to process release data: " & e.msg)
  finally:
    client.close()





proc downloadLatestRelease(downloadUrl: string): Future[string] {.async.} =
  ## Downloads a file from the provided direct URL into a temporary cache folder.
  ## Returns the absolute path of the downloaded file, or "" if the download fails.
  
  # 1. Parse the true filename from the trailing end of the download URL
  let fileInfo = downloadUrl.splitFile()
  let assetName = fileInfo.name & fileInfo.ext
  
  if assetName.len == 0 or fileInfo.ext.len == 0:
    errorMsg("Could not deduce a valid package filename from URL: " & downloadUrl)
    return ""

  infoMsg("Downloading asset payload: " & assetName)
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({ "User-Agent": "Nim-Release-Scanner" })

  try:
    let cacheDir = getTempDir() / "nova-cache"
    createDir(cacheDir)

    let destFile = cacheDir / assetName

    await client.downloadFile(downloadUrl, destFile)
    debug "Downloaded package to destination: " & destFile
    return destFile

  except CatchableError as e:
    errorMsg("Failed to download package binary: " & e.msg)
    return ""

  finally:
    client.close()









proc addGitRepo(pkgMan, repoInput: string) {.async.} =
  let repoPath = getRepoName(repoInput)
  if repoPath.len == 0 or not repoPath.contains("/"):
    errorMsg "Invalid repository format. Use 'owner/repo' or a full GitHub URL."
    return

  let currentList = loadOrCreateRepoList(repoFile)

  for item in currentList:
    if item.hasKey("repo") and item["repo"].getStr().toLowerAscii() == repoPath.toLowerAscii():
      warnMsg "Repository \'" & repoPath & "\' is already in git repos."
      return

  infoMsg "Fetching latest release version for " & repoPath & "..."
  let ext = case pkgMan
    of "apt": "deb"
    of "dnf", "yum", "zypper": "rpm"
    else: ""
  let repoData = await getLatestRelease(repoPath, ext)
  if repoData.version == "":
    errorMsg "Could not add repo \'" & repoPath & "\'"
    return

  # Map the native package name directly into the JSON configuration structure
  let newEntry = %*{
    "repo": repoData.name, 
    "pkg_name": repoData.pkgName, 
    "version": repoData.version,
    "download_url": repoData.downloadUrl,
  }
  currentList.add(newEntry)

  try:
    writeFile(repoFile, currentList.pretty())
    successMsg "Added \'" & repoPath & "\' to git repos"
  except IOError:
    errorMsg "Could not write to file " & repoFile





proc refreshGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    errorMsg "" & repoFile & " not found. Nothing to update."
    return

  let currentList = loadOrCreateRepoList(repoFile)
  if currentList.len == 0:
    infoMsg "The repository list is empty."
    return

  infoMsg("Checking tracked Git repositories for updates...")
  let ext = case pkgMan
    of "apt": "deb"
    of "dnf", "yum", "zypper": "rpm"
    else: ""

  var futures: seq[Future[Repo]] = @[]
  var mappedRepos: seq[JsonNode] = @[]

  for item in currentList:
    if item.hasKey("repo"):
      let repoPath = item["repo"].getStr()
      futures.add(getLatestRelease(repoPath, ext))
      mappedRepos.add(item)

  discard await all(futures)

  var updatedCount = 0
  for i, future in futures:
    let item = mappedRepos[i]
    #let repoPath = item["repo"].getStr()
    #let oldVersion = item["version"].getStr()
    #let newVersion = future.read()
    let repoData = future.read()
    let oldVersion = item["version"].getStr()

    if repoData.version.len > 0 and oldVersion != repoData.version:
      infoMsg("New version found for " & repoData.name & ": " & oldVersion & " ➡️ " & repoData.version)
      item["version"] = newJString(repoData.version)
      item["download_url"] = newJString(repoData.downloadUrl)
      inc(updatedCount)

  if updatedCount > 0:
    try:
      writeFile(repoFile, currentList.pretty())
      infoMsg "Successfully updated " & $updatedCount & " repository/ies in " & repoFile
      successMsg "Successfully updated " & $updatedCount & " repository/ies in " & repoFile
    except IOError:
      errorMsg "Could not save updates to " & repoFile
  else:
    infoMsg "Everything is already up to date!"





proc upgradeGitRepos(pkgMan: string) {.async.} =
  if not fileExists(repoFile):
    infoMsg("No local tracking manifest found at " & repoFile & ". Skipping external applications.")
    return

  let currentList = loadOrCreateRepoList(repoFile)
  if currentList.len == 0:
    return

  infoMsg("Evaluating local packages against tracked manifests...")
  let ext = case pkgMan
    of "apt": "deb"
    of "dnf", "yum", "zypper": "rpm"
    else: ""

  for item in currentList:
    if not (item.hasKey("repo") and item.hasKey("pkg_name") and item.hasKey("version")):
      continue

    let repoPath = item["repo"].getStr()
    let pkgName = item["pkg_name"].getStr()
    let manifestVersion = item["version"].getStr()

    # 1. Ask the Linux OS what is installed right now
    let installedVersion = getInstalledOSVersion(pkgMan, pkgName)

    # 2. Check if it's missing or out of date
    let isMissing = installedVersion == ""
    let isStale = installedVersion != manifestVersion and manifestVersion.len > 0

    if isMissing or isStale:
      if isMissing:
        infoMsg("Package '" & pkgName & "' is not present on the host system. Installing...")
      else:
        infoMsg("Upgrade detected for '" & pkgName & "': Local (" & installedVersion & ") ➡️ Tracked (" & manifestVersion & ")")

      # Fetch the latest asset release details to retrieve a fresh downloadUrl
      let repoData = await getLatestRelease(repoPath, ext)
      
      if repoData.downloadUrl.len > 0:
        let downloadedPayload = await downloadLatestRelease(repoData.downloadUrl)
        
        if downloadedPayload.len > 0 and fileExists(downloadedPayload):
          var installTarget = downloadedPayload
          if pkgMan == "apt" and not installTarget.startsWith("./") and not installTarget.startsWith("/"):
            installTarget = "./" & installTarget

          let installCmd = getNativeCommand(pkgMan, actInstall, installTarget)
          infoMsg("Executing native installer: " & installCmd)
          let exitCode = execCmd(installCmd)
          
          if installTarget.contains(getTempDir()):
            discard tryRemoveFile(installTarget)

          if exitCode == 0:
            successMsg("Successfully processed installation package for " & pkgName)
          else:
            errorMsg("Native package manager failed during execution for " & pkgName)
        else:
          errorMsg("Failed to download package payload for " & pkgName)
    else:
      debug(pkgName & " [" & installedVersion & "] is already completely current.")

  successMsg("All tracked applications evaluated completely.")















proc removeGitRepo(repoInput: string) =
  if not fileExists(repoFile):
    errorMsg "\'" & repoFile & "\' not found. Nothing to remove."
    return

  let targetRepo = getRepoName(repoInput)
  let currentList = loadOrCreateRepoList(repoFile)
  let updatedList = newJArray()
  var removed = false

  for item in currentList:
    if item.hasKey("repo") and item["repo"].getStr().toLowerAscii() == targetRepo.toLowerAscii():
      removed = true
    else:
      updatedList.add(item)

  if removed:
    try:
      writeFile(repoFile, updatedList.pretty())
      successMsg "Removed \'" & targetRepo & "\' from git repos."
    except IOError:
      errorMsg "Could not save file changes."
  else:
    errorMsg "Repository \'" & targetRepo & "\' not found."


proc listGitUpdates(pkgMan: string) =
  ## Compares locally cached manifest records against live native package manager states.
  if not fileExists(repoFile):
    infoMsg "No tracked repositories configuration found (" & repoFile & " is missing)."
    return

  let currentList = loadOrCreateRepoList(repoFile)
  if currentList.len == 0:
    infoMsg "The tracking repository list is empty."
    return

  styledWriteLine(stdout, fgWhite, styleBright, "\nAvailable Updates for Git Applications:", resetStyle)
  
  let headPkg = "Package Name"
  let headInstalled = "Installed (OS)"
  let headLatest = "Latest (Manifest)"
  
  var updatesCount = 0
  var headerPrinted = false

  for item in currentList:
    if not (item.hasKey("repo") and item.hasKey("pkg_name") and item.hasKey("version")):
      continue

    let pkgName = item["pkg_name"].getStr()
    let manifestVersion = item["version"].getStr()

    # 1. Query the live operating system state natively
    let installedVersion = getInstalledOSVersion(pkgMan, pkgName)

    # 2. Compare if the application is missing completely, or trailing behind the cached index
    let isMissing = installedVersion == ""
    let isOutdated = installedVersion != manifestVersion and manifestVersion.len > 0

    if isMissing or isOutdated:
      # Defer formatting header until we are certain an update row is active
      if not headerPrinted:
        echo "  " & headPkg.alignLeft(25) & " " & headInstalled.alignLeft(20) & " " & headLatest
        echo "  " & "-".repeat(68)
        headerPrinted = true

      let displayInstalled = if isMissing: "Not Installed" else: installedVersion
      
      stdout.write "  • " & pkgName.alignLeft(23) & " "
      styledWrite(stdout, fgYellow, displayInstalled.alignLeft(20))
      stdout.write " ➡️  "
      styledWriteLine(stdout, fgGreen, styleBright, manifestVersion)
      
      inc(updatesCount)

  if updatesCount == 0:
    successMsg "All standalone Git packages are up to date."
  else:
    echo "\n  Run 'nova upgrade' to apply these updates.\n"




proc listGitReposNew() =
  if not fileExists(repoFile):
    infoMsg "No repositories saved yet (" & repoFile & " does not exist)."
    return

  let currentList = loadOrCreateRepoList(repoFile)
  if currentList.len == 0:
    infoMsg "The repository list is empty."
    return

  styledWriteLine(stdout, fgWhite, styleBright, "Tracked Git Repositories:", resetStyle)
  
  # Format Table Header for clarity
  let headRepo = "Repository"
  let headPkg = "Package"
  let headVer = "Version"
  echo "  " & headRepo.alignLeft(30) & " " & headPkg.alignLeft(20) & " [" & headVer & "]"
  echo "  " & "-".repeat(70)

  for item in currentList:
    if item.hasKey("repo") and item.hasKey("version"):
      let repoStr = item["repo"].getStr()
      let versionStr = item["version"].getStr()
      
      # Pull down the true native package name, fallback gracefully if not yet populated
      let pkgStr = if item.hasKey("pkg_name"): item["pkg_name"].getStr() else: "unknown"
      
      # Output aligned text components smoothly
      echo "  • " & repoStr.alignLeft(28) & " " & pkgStr.alignLeft(20) & " [" & versionStr & "]"






proc listGitRepos() =
  if not fileExists(repoFile):
    infoMsg "No repositories saved yet (" & repoFile & " does not exist)."
    return

  let currentList = loadOrCreateRepoList(repoFile)
  if currentList.len == 0:
    infoMsg "The repository list is empty."
    return

  echo "\nAdded Git Repositories:"
  for item in currentList:
    if item.hasKey("repo") and item.hasKey("version"):
      let repoStr = item["repo"].getStr()
      echo "  ", repoStr

# ========================================================================================
#
#                                   Nova
#                                 Packages
#
# ========================================================================================

proc downloadPkg(downloadUrl: string): Future[string] {.async.} =
  # Parse filename from the end of the download URL
  let assetName = downloadUrl.extractFilename()

  if assetName.len == 0:
    errorMsg("Could not deduce a valid package filename from URL: ", downloadUrl)
    return ""

  infoMsg("Downloading package \'", assetName, "\'...")

  let ctx = 
    if disableSslFlag:
      newContext(verifyMode = CVerifyNone)
    else:
      newContext()
  let client = newAsyncHttpClient(sslContext = ctx)
  client.headers = newHttpHeaders({"User-Agent": "Nova-Package-Manager"})
  client.timeout = 30000

  try:
    let uid = getuid()
    let cacheDir = getTempDir() / "nova-cache-" & $uid

    if symlinkExists(cacheDir) or fileExists(cacheDir):
      removeFile(cacheDir)

    if not dirExists(cacheDir):
      createDir(cacheDir)

    let destFile = cacheDir / assetName

    await client.downloadFile(downloadUrl, destFile)
    debug "Downloaded package to: ", destFile
    return destFile

  except CatchableError as e:
    errorMsg("Failed to download package binary: ", e.msg)
    return ""
  finally:
    client.close()

proc findInManifest(repoList: JsonNode, targetStr: string): int =
  ## Iterates through the manifest and returns the index of the matching package.
  ## Returns -1 if no matching package or repository name is found.
  let targetLower = targetStr.toLowerAscii()
  let targetRepo = getRepoName(targetLower)
  var i = 0

  for entry in repoList:
    let entryName = entry.getOrDefault("pkg_name").getStr("").toLowerAscii()
    let entryRepo = entry.getOrDefault("repo").getStr("").toLowerAscii()

    if entryName == targetLower or entryRepo == targetRepo:
      return i

    inc(i)

  return -1

# ----------------------------------------------------------------------------------------
#                                    Binary
# ----------------------------------------------------------------------------------------

proc extractArchive(archivePath, destDir: string): bool =
  ## Safely extracts tar.gz, tar.xz, or zip archives using host system utilities.
  ## Falls back to 'tar -xf' for zip files if 'unzip' is not installed.
  debug "extractArchive: ", archivePath
  let lowerPath = archivePath.toLowerAscii()
  var cmd = ""
  
  if lowerPath.endsWith(".tar.gz") or lowerPath.endsWith(".tgz"):
    cmd = "tar -xzf " & quoteShell(archivePath) & " -C " & quoteShell(destDir)
  elif lowerPath.endsWith(".tar.xz") or lowerPath.endsWith(".txz"):
    cmd = "tar -xJf " & quoteShell(archivePath) & " -C " & quoteShell(destDir)
  elif lowerPath.endsWith(".zip"):
    if findExe("unzip") != "":
      cmd = "unzip -q " & quoteShell(archivePath) & " -d " & quoteShell(destDir)
    else:
      cmd = "tar -xf " & quoteShell(archivePath) & " -C " & quoteShell(destDir)
  else:
    return false

  return execCmd(cmd) == 0

proc installBinary(pkgName, downloadPath: string) =
  ## Extracts an archive or installs a raw binary to ~/.local/bin
  infoMsg("Installing standalone binary...")
  let uid = getuid()
  let localBinDir = os.getHomeDir() / ".local/bin"
  let extractWorkspace = getTempDir() / "nova-binary-extract-" & $uid

  if not dirExists(localBinDir):
    createDir(localBinDir)

  let lowerPath = downloadPath.toLowerAscii()
  let isArchive =
    lowerPath.endsWith(".tar.gz") or lowerPath.endsWith(".tgz") or 
    lowerPath.endsWith(".tar.xz") or lowerPath.endsWith(".txz") or 
    lowerPath.endsWith(".zip")

  var binaryPath = ""

  if not isArchive:
    # Treat the download path as a raw uncompressed binary.
    binaryPath = downloadPath
  else:
    # Extract the downloaded package to a temp dir.
    if dirExists(extractWorkspace):
      try: removeDir(extractWorkspace) except CatchableError: discard
    createDir(extractWorkspace)

    try:
      if not extractArchive(downloadPath, extractWorkspace):
        errorMsg("Failed to extract binary archive.")
        quit(1)

      # Scan the workspace for files with execution permissions
      for path in walkDirRec(extractWorkspace, yieldFilter = {pcFile}):
        let filePerms = getFilePermissions(path)
        let isExecutable = fpUserExec in filePerms or fpGroupExec in filePerms
        let filename = splitFile(path).name.toLowerAscii()

        # Filter out documentation or shell scripts
        if isExecutable and not filename.endsWith(".md") and not filename.endsWith(".txt") and not filename.endsWith(".sh"):
          # Match target package explicitly, or settle for the first executable found
          if pkgName.toLowerAscii() in filename:
            binaryPath = path
            break
          if binaryPath.len == 0:
            binaryPath = path

    except CatchableError as e:
      errorMsg("Encountered error during binary extraction: ", e.msg)
      quit(1)

  # Install binary to .local/bin
  try:
    if binaryPath.len > 0 and fileExists(binaryPath):
      let finalDest = localBinDir / pkgName
      copyFile(binaryPath, finalDest)
      
      # Set binary execution permissions (0o755)
      setFilePermissions(finalDest, {fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead, fpOthersExec})

      successMsg("Successfully installed binary to ", finalDest)
      infoMsg("Ensure \'", localBinDir, "\' is exported to your system $PATH ")
    else:
      errorMsg("Could not find valid binary at ", binaryPath)
      quit(1)

  except CatchableError as e:
    errorMsg("Encountered error during binary installation: ", e.msg)
    quit(1)
  finally:
    if dirExists(extractWorkspace):
      try: removeDir(extractWorkspace) except CatchableError: discard

# ----------------------------------------------------------------------------------------
#                                    AppImage
# ----------------------------------------------------------------------------------------

proc removeDesktopFile(pkgName: string) =
  let uid = getuid()

  let userIconDir = os.getHomeDir() / ".local/share/icons/hicolor/256x256/apps"
  let appsDir = os.getHomeDir() / ".local/share/applications"

  let iconName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-icon-" & $uid) & ".png"
  let destIconPath = userIconDir / iconName

  let desktopName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-" & $uid) & ".desktop"
  let destDesktopPath = appsDir / desktopName

  # Safely attempt to remove the .desktop file
  if fileExists(destDesktopPath):
    try:
      removeFile(destDesktopPath)
      debug "Removed desktop shortcut: ", destDesktopPath
    except OSError:
      warnMsg("Could not remove desktop file: ", destDesktopPath)

  # Safely attempt to remove the extracted .png icon
  if fileExists(destIconPath):
    try:
      removeFile(destIconPath)
      debug "Removed application icon: ", destIconPath
    except OSError:
      warnMsg("Could not remove icon file: ", destIconPath)

proc initDesktopFile(pkgName: string, appPath: string) =
  ## Scan an AppImage package, and extract .desktop file if present
  ## Fall back to creating one
  debug "init desktop file started"
  let uid = getuid()
  let userIconDir = os.getHomeDir() / ".local/share/icons/hicolor/256x256/apps"
  let appsDir = os.getHomeDir() / ".local/share/applications"

  let iconName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-icon-" & $uid) & ".png"
  let destIconPath = userIconDir / iconName
  let desktopName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-" & $uid) & ".desktop"
  let destDesktopPath = appsDir / desktopName

  for directory in [userIconDir, appsDir]:
    if not dirExists(directory):
      try: createDir(directory)
      except CatchableError: discard

  if not fileExists(appPath): 
    errorMsg("Cannot extract assets, source path does not exist: ", appPath)
    return

  let cacheWorkspace = getTempDir() / "nova-asset-extract-" & $uid
  if dirExists(cacheWorkspace):
    try: removeDir(cacheWorkspace)
    except CatchableError: discard
  createDir(cacheWorkspace)

  try:
    # AppImages extract strictly to a folder named "squashfs-root" in the current directory
    let extractCmd = "cd " & cacheWorkspace & " && " & appPath & " --appimage-extract >/dev/null 2>&1"
    let extractCode = execCmd(extractCmd)
    let rootPath = cacheWorkspace / "squashfs-root"

    if extractCode == 0 and dirExists(rootPath):
      # XDG AppImages store their primary desktop icon right in the top layer of the squashfs root
      # Search for the best available PNG file inside the extracted target workspace
      var extractedDesktopPath = ""
      var bestIconPath = ""
      var fallbackIconPath = ""

      for path in walkDirRec(rootPath, yieldFilter = {pcFile, pcLinkToFile}):
        let lowerPath = path.toLowerAscii()
        if lowerPath.endsWith(".desktop"):
          extractedDesktopPath = path
        elif lowerPath.endsWith(".png"):
          if lowerPath.endsWith(".diricon") or "icon" in lowerPath:
            fallbackIconPath = path
          if pkgName.toLowerAscii() in lowerPath:
            bestIconPath = path

      # Resolve symbolic links to absolute hard targets before deletion 
      let rawSelectedIcon = if bestIconPath.len > 0: bestIconPath else: fallbackIconPath
      let verifiedRealIcon =
        # expandFilename automatically follows symlinks and resolves their true location
        try: os.expandFilename(rawSelectedIcon)
        except CatchableError: rawSelectedIcon

      if verifiedRealIcon.len > 0 and fileExists(verifiedRealIcon):
        try: copyFile(verifiedRealIcon, destIconPath)
        except CatchableError: discard

      # Process Desktop Configuration
      if extractedDesktopPath.len > 0 and fileExists(extractedDesktopPath):
        var updatedLines: seq[string] = @[]
        for line in lines(extractedDesktopPath):
          let stripped = line.strip()
          if stripped.startsWith("Exec="):
            updatedLines.add("Exec=" & appPath)
          elif stripped.startsWith("TryExec="):
            updatedLines.add("TryExec=" & appPath)
          elif stripped.startsWith("Icon="):
            updatedLines.add("Icon=" & pkgName.toLowerAscii())
          else:
            updatedLines.add(line)

        writeFile(destDesktopPath, updatedLines.join("\n"))
        debug "Successfully extracted .desktop file: ", destDesktopPath
      else:
        # Capitalize first letter cleanly for display format name fields
        let displayName =
          if pkgName.len > 0:
            pkgName[0].toUpperAscii() & pkgName[1..^1]
          else:
            "AppImage Application"

        # Format a clean XDG compliant .desktop file
        var desktopContent =
          "[Desktop Entry]\n" &
          "Type=Application\n" &
          "Name=" & displayName & "\n" &
          "Exec=" & appPath & "\n" &
          "TryExec=" & appPath & "\n" &
          "Terminal=false\n" &
          "Categories=Utility;Development;\n" &
          "Comment=Installed via Nova Package Manager\n" &
          "StartupNotify=true\n"

        # Append Icon key if found
        if fileExists(destIconPath):
          desktopContent.add("Icon=" & pkgName.toLowerAscii() & "\n")

        writeFile(destDesktopPath, desktopContent)
        debug "Successfully created .desktop file: ", destDesktopPath

      if fileExists(destDesktopPath):
        let perms = getFilePermissions(destDesktopPath)
        setFilePermissions(destDesktopPath, perms + {fpUserRead, fpUserWrite, fpUserExec})
        successMsg("Successfully added .desktop file.")
      else:
        errorMsg("Failed to add .desktop file.")

  except CatchableError as e:
    errorMsg("Failed to extract AppImage assets: ", e.msg)
  finally:
    if dirExists(cacheWorkspace):
      try: removeDir(cacheWorkspace)
      except CatchableError: discard

# ----------------------------------------------------------------------------------------
#                                    Install Git Package
# ----------------------------------------------------------------------------------------

proc installGitPkg(pkgMan: string, pkgEntry: JsonNode) {.async.} =
  let pkgName = pkgEntry.getOrDefault("pkg_name").getStr("")
  let downloadUrl = pkgEntry.getOrDefault("download_url").getStr("")
  let pkgType =
    try: parseEnum[PkgType](pkgEntry.getOrDefault("pkg_type").getStr("Binary"))
    # Fallback option if the string in the entry doesn't match any enum
    except ValueError: Binary

  if downloadUrl.len == 0:
    errorMsg("No target download URL configured for package: ", pkgName)
    quit(1)

  # Download package from the download Url
  let downloadPath = await downloadPkg(downloadUrl)
  if downloadPath.len == 0 or not fileExists(downloadPath):
    errorMsg("Failed to download package ", pkgName)
    quit(1)

  # Defer cache cleanup up front to handle early returns
  defer:
    discard tryRemoveFile(downloadPath)
    let uid = getuid()
    let userCacheDir = getTempDir() / "nova-cache-" & $uid
    if dirExists(userCacheDir):
      try:
        removeDir(userCacheDir)
      except CatchableError:
        discard

  # Install Packages by Type
  case pkgType
  of Deb, Rpm, Pacman:
    infoMsg("Installing native package...")
    let exitCode = runNativeCommand(pkgMan, actInstall, downloadPath)
    if exitCode == 0:
      successMsg("Successfully installed package \'", pkgName, "\'")
    else:
      errorMsg("Failed to install package \'", pkgName, "\'")
      quit(1)

  of AppImage:
    infoMsg("Installing AppImage binary...")
    # TODO install to /opt
    let localBinDir = os.getHomeDir() / ".local" / "bin"
    if not dirExists(localBinDir):
      createDir(localBinDir)

    #let binaryName = if pkgName.len > 0: pkgName else: splitFile(downloadPath).name
    let pkgPath = localBinDir / pkgName

    try:
      # Copy asset from temporary dir to local bin path
      copyFile(downloadPath, pkgPath)
      
      # Add execution permissions (0o755)
      let perms = getFilePermissions(pkgPath)
      setFilePermissions(pkgPath, perms + {fpUserExec, fpGroupExec, fpOthersExec})

      successMsg("Successfully installed AppImage to ", pkgPath)
      infoMsg("Ensure '", localBinDir, "' is exported to your system $PATH ")

      initDesktopFile(pkgName, pkgPath)

    except CatchableError as e:
      errorMsg("Failed to install AppImage asset: ", e.msg)
      quit(1)

  of Flatpak, Snap:
    warnMsg("Global framework containers (Flatpak/Snap) are not yet natively supported.")

  of Binary:
    installBinary(pkgName, downloadPath)

  of Source:
    warnMsg("Build pipelines are not yet natively supported.")

# ----------------------------------------------------------------------------------------
#                                    Install Package
# ----------------------------------------------------------------------------------------

proc installPkg(pkgMan: string, targets: seq[string]) =
  ## Installs from URLs or packages in manifest, sends remaining to native package manager.
  debug "installPkg: Processing targets " & $targets
  
  var nativeTargets: seq[string] = @[]
  let repoList = if fileExists(repoFile): loadOrCreateRepoList(repoFile) else: newJArray()

  for target in targets:
    let foundIndex = if repoList.len > 0: repoList.findInManifest(target) else: -1

    # Check if target is already in the manifest
    if foundIndex != -1:
      debug "Found package '" & target & "' in manifest."
      let entry = repoList[foundIndex]
      let pkgName = entry.getOrDefault("pkg_name").getStr("")
      let manifestVer = entry.getOrDefault("version").getStr("")
      let downloadUrl = entry.getOrDefault("download_url").getStr("")
      let pkgType =
        try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
        except ValueError: Binary

      if pkgName.len == 0 or downloadUrl.len == 0:
        debug "Skipping incomplete or malformed entry in manifest registry."
        continue

      # Get currently installed version
      let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)

      # Check if it's missing or out of date
      let isMissing = installedVer.len == 0
      let isStale = (manifestVer.len > 0) and (compareVersionStrings(manifestVer, installedVer) == 1)

      if isMissing or isStale:
        if isMissing:
          debug "Package '" & pkgName & "' is not present on the host system. Installing..."
        else:
          infoMsg("Upgrade detected for '" & pkgName & "': Local (" & installedVer & ") -> Tracked (" & manifestVer & ")")

        waitFor installGitPkg(pkgMan, entry)
      else:
        styledWrite(stdout, fgGreen, styleBright, pkgName, resetStyle)
        styledWrite(stdout, " is already the newest version ")
        styledWriteLine(stdout, fgBlue, styleBright, installedVer, resetStyle)

    # If target's not in manifest and it's a Git repo, add repo then install pkg
    elif getSourceType(target) in {srcGithubRepo, srcGitlabRepo}:
      infoMsg("Interpreted input target '" & target & "' as source reference URL.")
      waitFor addGitRepo(pkgMan, target)

      # Reload manifest to capture the new addition
      let repoName = getRepoName(target).toLowerAscii()
      let updatedList = loadOrCreateRepoList(repoFile)

      for entry in updatedList:
        if entry.hasKey("repo") and entry["repo"].getStr().toLowerAscii() == repoName:
          waitFor installGitPkg(pkgMan, entry)
          break

    # Unmanaged native packages get sent to native package manager
    else:
      debug "Package '" & target & "' not found in manifest or URLs. Sending to native package manager..."
      nativeTargets.add(target)

  # Batch remaining native targets into one native package manager execution
  if nativeTargets.len > 0:
    let nativeTargetStr = nativeTargets.join(" ")
    infoMsg("Passing native system installations down to system package matrix: " & nativeTargetStr)
    let exitCode = runNativeCommand(pkgMan, actInstall, nativeTargetStr)
    quit(exitCode)
  else:
    quit(0)

# ----------------------------------------------------------------------------------------
#                                    Upgrade Package
# ----------------------------------------------------------------------------------------

proc upgradePkg(pkgMan: string, targets: seq[string]) =
  ## Checks Nova's manifest first; if missing, it lets the execution pass to the system.
  debug "upgradePkg: Processing targets " & $targets

  var nativeTargets: seq[string] = @[]
  let repoList = if fileExists(repoFile): loadOrCreateRepoList(repoFile) else: newJArray()

  for target in targets:
    let foundIndex = if repoList.len > 0: repoList.findInManifest(target) else: -1

    if foundIndex == -1:
      debug "Package '" & target & "' not managed by Nova. Staging for native manager..."
      nativeTargets.add(target)
      continue

    # Process Nova targeted package upgrade
    infoMsg("Target package '" & target & "' managed by Nova. Initiating manifest upgrade...")
    let entry = repoList[foundIndex]
    let pkgName = entry.getOrDefault("pkg_name").getStr("")
    #let oldVersion = entry.getOrDefault("version").getStr("")
    let repoPath = entry.getOrDefault("repo").getStr("")
    let prerelease = entry.getOrDefault("prerelease").getBool(false)
    let preferMusl = entry.getOrDefault("prefer_musl").getBool(false)
    let pkgType =
      try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
      except ValueError: Binary

    # Get currently installed version
    let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)

    let repoData = waitFor getRepoData(pkgMan, repoPath, prerelease, preferMusl)
    
    if repoData.version.len == 0:
      warnMsg("Could not fetch remote update info for: ", repoPath)
      continue

    # Check if it's missing or out of date
    if installedVer.len == 0 or compareVersionStrings(repoData.version, installedVer) == 1:
      if installedVer.len == 0:
        infoMsg("Package '" & pkgName & "' is missing from the system. Re-installing newest version (" & repoData.version & ")...")
      else:
        infoMsg("Upgrade discovered for '" & pkgName & "': Local (" & installedVer & ") -> Remote (" & repoData.version & ")")

      # Commit changes to manifest
      entry["version"] = newJString(repoData.version)
      entry["download_url"] = newJString(repoData.downloadUrl)
      
      try:
        writeFile(repoFile, repoList.pretty())
      except IOError:
        errorMsg("Failed to write changes to manifest.")
        quit(1)

      # Install Package
      waitFor installGitPkg(pkgMan, entry)
      successMsg("Successfully upgraded Git package '", pkgName, "'!")
    else:
      successMsg("Package '", pkgName, "' is already up to date at version ", installedVer)

  # If there are system packages left over, pass them to the native command routine instead of quitting
  if nativeTargets.len > 0:
    let nativeTargetStr = nativeTargets.join(" ")
    infoMsg("Passing native system upgrades to backend: " & nativeTargetStr)
    let exitCode = runNativeCommand(pkgMan, actUpgrade, nativeTargetStr)
    quit(exitCode)
  else:
    quit(0)

# ----------------------------------------------------------------------------------------
#                                    Remove Package
# ----------------------------------------------------------------------------------------

proc removePkg(pkgMan: string, targets: seq[string]) =
  ## Removes standalone binaries/AppImages and batches remaining system packages.
  debug "removePkg: Processing targets " & $targets
  
  var nativeTargets: seq[string] = @[]
  let repoList = if fileExists(repoFile): loadOrCreateRepoList(repoFile) else: newJArray()

  for target in targets:
    # Check if target is already in the manifest
    let foundIndex = if repoList.len > 0: repoList.findInManifest(target) else: -1

    if foundIndex == -1:
      debug "Package '" & target & "' not found in manifest. Staging for native manager removal..."
      nativeTargets.add(target)
      continue

    debug "Found package \'" & target & "\' in manifest."
    let entry = repoList[foundIndex]
    let pkgName = entry.getOrDefault("pkg_name").getStr("")
    let pkgType =
      try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
      except ValueError: Binary

    # Get currently installed version
    let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)
    if installedVer.len == 0:
      debug "Package '" & pkgName & "' is tracked in manifest but not detected as installed. Skipping local deletion."
      continue

    # Remove Packages by Type
    case pkgType
    of Deb, Rpm, Pacman:
      debug "Tracked package '" & pkgName & "' is a native system asset. Offloading to atomic system execution list..."
      nativeTargets.add(pkgName)

    of AppImage:
      infoMsg("Uninstalling AppImage binary \'" & pkgName & "\'...")
      let localBinDir = os.getHomeDir() / ".local" / "bin"
      let pkgPath = localBinDir / pkgName

      if fileExists(pkgPath):
        try:
          removeFile(pkgPath)
          debug "Successfully removed AppImage binary: ", pkgPath
        except OSError:
          errorMsg("Failed to delete AppImage binary: ", pkgPath)
          quit(1)
      else:
        warnMsg("AppImage binary did not exist at: ", pkgPath)

      removeDesktopFile(pkgName)
      successMsg("Successfully removed \'", pkgName, "\' from the system.")

    of Binary:
      infoMsg("Uninstalling standalone native binary...")
      let localBinDir = os.getHomeDir() / ".local" / "bin"
      let pkgPath = localBinDir / pkgName

      if fileExists(pkgPath):
        try:
          removeFile(pkgPath)
          successMsg("Successfully uninstalled binary \'", pkgName, "\'")
        except OSError:
          errorMsg("Failed to delete binary at: ", pkgPath)
          quit(1)
      else:
        warnMsg("Binary target did not exist at: ", pkgPath)

    of Flatpak, Snap:
      warnMsg("Global framework containers (Flatpak/Snap) are not yet natively supported for targeted uninstallation routines.")
    of Source:
      warnMsg("Source compilation build uninstallation trees are not yet natively supported.")

  # Batch remaining native targets into one native package manager execution
  if nativeTargets.len > 0:
    let nativeTargetStr = nativeTargets.join(" ")
    infoMsg("Passing native system removals down to system package matrix: " & nativeTargetStr)
    let exitCode = runNativeCommand(pkgMan, actRemove, nativeTargetStr)
    quit(exitCode)
  else:
    quit(0)

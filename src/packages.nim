# ========================================================================================
#
#                                   Nova
#                                 Packages
#
# ========================================================================================

proc initDesktopFile(pkgName: string, appPath: string) =
  ## Scan an AppImage package, and extract .desktop file if present
  ## Fall back to creating one
  debug "init desktop file started"
  let uid = getuid()
  let userIconDir = os.getHomeDir() / ".local" / "share" / "icons" / "hicolor" / "256x256" / "apps"
  let appsDir = os.getHomeDir() / ".local" / "share" / "applications"

  let finalIconName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-icon-" & $uid) & ".png"
  let destIconPath = userIconDir / finalIconName
  let finalDesktopName = (if pkgName.len > 0: pkgName.toLowerAscii() else: "appimage-" & $uid) & ".desktop"
  let destDesktopPath = appsDir / finalDesktopName

  for directory in [userIconDir, appsDir]:
    if not dirExists(directory):
      try: createDir(directory)
      except CatchableError: discard

  if not fileExists(appPath): 
    errorMsg("Cannot extract assets, source path does not exist: ", appPath)
    return

  let cacheWorkspace = getTempDir() / "nova-asset-extract-" & $uid
  let currentDir = getCurrentDir()

  if dirExists(cacheWorkspace):
    try: removeDir(cacheWorkspace)
    except CatchableError: discard
  try: createDir(cacheWorkspace)
  except CatchableError: return

  var extractedDesktopPath = ""
  var bestIconPath = ""
  var fallbackIconPath = ""

  try:
    # AppImages extract strictly to a folder named "squashfs-root" in the current directory
    setCurrentDir(cacheWorkspace)
    let extractCode = execCmd(appPath & " --appimage-extract >/dev/null 2>&1")
    let rootPath = cacheWorkspace / "squashfs-root"

    if extractCode == 0 and dirExists(rootPath):
      # XDG AppImages store their primary desktop icon right in the top layer of the squashfs root
      # Search for the best available PNG file inside the extracted target workspace
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
      var verifiedRealIcon = ""

      if rawSelectedIcon.len > 0:
        try:
          # expandFilename automatically follows symlinks and resolves their true physical location
          verifiedRealIcon = os.expandFilename(rawSelectedIcon)
          debug "Resolved icon target path cleanly: " & verifiedRealIcon
        except CatchableError:
          # Fallback safely if it's already a standard file
          verifiedRealIcon = rawSelectedIcon

      # Mirror the true extracted graphic artifact out to your profile cache
      if verifiedRealIcon.len > 0 and fileExists(verifiedRealIcon):
        try:
          copyFile(verifiedRealIcon, destIconPath)
          debug "Successfully copied resolved icon file: " & destIconPath
        except CatchableError as e:
          debug "Icon cloning error bypassed: " & e.msg

      # Process Desktop Configuration
      if extractedDesktopPath.len > 0 and fileExists(extractedDesktopPath):
        var updatedLines: seq[string] = @[]
        for line in lines(extractedDesktopPath):
          let strippedLine = line.strip()
          if strippedLine.startsWith("Exec="):
            updatedLines.add("Exec=\"" & appPath & "\"")
          elif strippedLine.startsWith("Icon="):
            updatedLines.add("Icon=" & pkgName.toLowerAscii())
          else:
            updatedLines.add(line)

        writeFile(destDesktopPath, updatedLines.join("\n"))
        debug "Successfully extracted .desktop file: " & destDesktopPath
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
          "Exec=\"" & appPath & "\"\n" &
          "Terminal=false\n" &
          "Categories=Utility;Development;\n" &
          "Comment=Installed via Nova Package Manager\n" &
          "StartupNotify=true\n"

        # Append Icon key if found
        if fileExists(destIconPath):
          desktopContent.add("Icon=" & pkgName.toLowerAscii() & "\n")

        writeFile(destDesktopPath, desktopContent)
        debug "Successfully created .desktop file: " & destDesktopPath

      if fileExists(destDesktopPath):
        let perms = getFilePermissions(destDesktopPath)
        setFilePermissions(destDesktopPath, perms + {fpUserRead, fpUserWrite, fpUserExec})
        successMsg("Successfully added .desktop file.")

  except CatchableError as e:
    warnMsg("Asset lifecycle coordinator encountered an internal fallback: " & e.msg)
  finally:
    setCurrentDir(currentDir)
    if dirExists(cacheWorkspace):
      try: removeDir(cacheWorkspace)
      except CatchableError: discard

proc downloadPkg(downloadUrl: string): Future[string] {.async.} =
  # Parse filename from the end of the download URL
  let fileInfo = downloadUrl.splitFile()
  let assetName = fileInfo.name & fileInfo.ext

  if assetName.len == 0 or fileInfo.ext.len == 0:
    errorMsg("Could not deduce a valid package filename from URL: " & downloadUrl)
    return ""

  infoMsg("Downloading package \'" & assetName & "\'...")
  let client = newAsyncHttpClient()
  client.headers = newHttpHeaders({"User-Agent": "Nova-Package-Manager"})
  client.timeout = 35000

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

proc installPkg(pkgMan: string, pkgEntry: JsonNode) {.async.} =
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
  of Deb, Rpm:
    infoMsg("Installing native package...")

    let exitCode = runNativeCommand(pkgMan, actInstall, downloadPath)

    if exitCode == 0:
      successMsg("Successfully installed package \'" & pkgName & "\'")
      quit(0)
    else:
      errorMsg("Failed to install package \'" & pkgName & "\'")
      quit(1)

  of AppImage:
    infoMsg("Installing AppImage binary...")
    # TODO install to /opt
    let localBinDir = os.getHomeDir() / ".local" / "bin"
    if not dirExists(localBinDir):
      createDir(localBinDir)

    #let binaryName = if pkgName.len > 0: pkgName else: splitFile(downloadPath).name
    let destPath = localBinDir / pkgName

    try:
      # Copy asset from temporary dir to local bin path
      copyFile(downloadPath, destPath)
      
      # Add execution permissions (0o755)
      let perms = getFilePermissions(destPath)
      setFilePermissions(destPath, perms + {fpUserExec, fpGroupExec, fpOthersExec})

      successMsg("Successfully installed AppImage to " & destPath)
      infoMsg("Ensure '" & localBinDir & "' is exported to your system $PATH ")

      initDesktopFile(pkgName, destPath)
      quit(0)

    except CatchableError as e:
      errorMsg("Failed to install AppImage asset: " & e.msg)
      quit(1)

  of Flatpak, Snap:
    warnMsg("Global framework containers (Flatpak/Snap) are not yet natively supported.")

  of Binary, Source:
    warnMsg("Raw binary tarballs and structural build pipelines are not yet natively supported.")


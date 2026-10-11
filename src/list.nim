# ========================================================================================
#
#                                   Nova
#                                  List-*
#
# ========================================================================================

proc listGitUpdates(pkgMan: string) =
  echo ""
  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("The repository manifest is empty.")
    return

  # Format Table Headers
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
    let pkgType =
      try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
      except ValueError: Binary

    # Get currently installed version
    let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)

    # Check if it's missing or out of date
    let isMissing = installedVer == ""
    let isOutdated = (manifestVer.len > 0) and (manifestVer > installedVer)

    if isMissing or isOutdated:
      # Defer formatting header until we are certain an update row is active
      if not headerPrinted:
        styledWriteLine(
          stdout, fgWhite, styleBright, "Available Updates for Git Applications:",
          resetStyle,
        )
        echo "  " & headPkg.alignLeft(30), headInstalled.alignLeft(20), headLatest
        echo "  " & "-".repeat(70)
        headerPrinted = true

      if isMissing:
        stdout.write "  • " & pkgName.alignLeft(28)
        styledWrite(stdout, fgYellow, "Not Installed".alignLeft(20))
      else:
        stdout.write "  • " & pkgName.alignLeft(28)
        styledWrite(stdout, styleBright, fgGreen, installedVer.alignLeft(20))

      styledWriteLine(stdout, styleBright, fgBlue, manifestVer)
      inc(updatesCount)

  if updatesCount == 0:
    successMsg("All git packages are up to date.")
  else:
    echo "\nRun 'nova upgrade' to apply these updates.\n"

proc listGitRepos(pkgMan: string) =
  echo ""

  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  styledEcho(fgWhite, styleBright, "Git Repositories:", resetStyle)

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("  No repositories saved yet.")
    return

  # Format Table Headers
  let headRepo = "Repository"
  let headPkg = "Package"
  let headStat = "Status"

  echo "  " & headRepo.alignLeft(30), headPkg.alignLeft(20), headStat
  echo "  " & "-".repeat(70)

  for entry in repoList:
    if entry.hasKey("repo") and entry.hasKey("version"):
      let pkgName = entry.getOrDefault("pkg_name").getStr("unknown")
      let repoStr = entry["repo"].getStr()
      let pkgType =
        try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
        except ValueError: Binary

      # Get currently installed version
      let pkgVer = getInstalledVersion(pkgMan, pkgName, pkgType)

      # Output aligned text
      #echo "  • " & repoStr.alignLeft(28), pkgName.alignLeft(20), "[" & $pkgType & "]"
      stdout.write "  • " & repoStr.alignLeft(28)
      #styledWrite(stdout, styleBright, fgGreen, pkgName.alignLeft(20))
      stdout.write(pkgName.alignLeft(20))
      #styledWriteLine(stdout, fgYellow, "[" & $pkgType & "]")

      # Check if it's installed or not
      if (pkgVer == "none") or (pkgVer == ""):
        styledWriteLine(stdout, fgYellow, "[Not Installed]")
      else:
        styledWriteLine(stdout, fgYellow, "[Installed]")

  echo ""

proc listGitReposBak() =
  echo ""

  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  styledEcho(fgWhite, styleBright, "Git Repositories:", resetStyle)

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("  No repositories saved yet.")
    return

  for entry in repoList:
    if entry.hasKey("repo") and entry.hasKey("version"):
      let repoStr = entry["repo"].getStr()
      echo "  ", repoStr
  echo ""

proc listGitPkgs(pkgMan: string) =
  echo ""

  if not fileExists(repoFile):
    warnMsg("Repository manifest not found.")
    return

  styledEcho(fgWhite, styleBright, "Git Packages:", resetStyle)

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("  No packages installed yet.")
    return

  # Format Table Headers
  let headPkg = "Package"
  let headVer = "Version"
  let headType = "Type"

  echo "  " & headPkg.alignLeft(30), headVer.alignLeft(20), headType
  echo "  " & "-".repeat(70)

  for entry in repoList:
    if entry.hasKey("repo") and entry.hasKey("version"):
      let pkgName = entry.getOrDefault("pkg_name").getStr("unknown")
      let pkgType =
        try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
        except ValueError: Binary

      #if pkgType == Deb or pkgType == Rpm:
      #  break

      # Get currently installed version
      let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)

      # Check if it's installed or not
      if installedVer == "none":
        debug "Package '" & pkgName & "' is not present on the host system."
        continue

      # Output aligned text
      #echo "  • " & pkgName.alignLeft(28), installedVer.alignLeft(20), "[" & $pkgType & "]"
      stdout.write "  • " & pkgName.alignLeft(28)
      #styledWrite(stdout, styleBright, fgGreen, pkgName.alignLeft(28))
      styledWrite(stdout, styleBright, fgBlue, installedVer.alignLeft(20))
      styledWriteLine(stdout, fgYellow, "[" & $pkgType & "]")

  echo ""

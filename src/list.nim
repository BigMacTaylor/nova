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
    if installedVer.len == 0:
      debug "Package '" & pkgName & "' not found on host system. Skipping..."
      continue

    # Check if it's out of date
    if compareVersionStrings(manifestVer, installedVer) == 1:
      # Defer printing header until an update row is active
      if not headerPrinted:
        printTableHeaders(
          "Available Updates for Git Applications:",
          "Package",
          "Current",
          "Latest",
        )
        headerPrinted = true

      # Output formatted text
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

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("No git repositories saved yet.")
    return

  printTableHeaders(
    "Git Repositories:",
    "Repository",
    "Package",
    "Status",
  )

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
      if pkgVer == "":
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

  let repoList = loadOrCreateRepoList(repoFile)
  if repoList.len == 0:
    infoMsg("No git packages installed yet.")
    return

  printTableHeaders(
    "Git Packages:",
    "Package",
    "Version",
    "Type",
  )

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
      if installedVer == "":
        debug "Package '" & pkgName & "' is not present on the host system."
        continue

      # Output formatted text
      #echo "  • " & pkgName.alignLeft(28), installedVer.alignLeft(20), "[" & $pkgType & "]"
      stdout.write "  • " & pkgName.alignLeft(28)
      #styledWrite(stdout, styleBright, fgGreen, pkgName.alignLeft(28))
      styledWrite(stdout, styleBright, fgBlue, installedVer.alignLeft(20))
      styledWriteLine(stdout, fgYellow, "[" & $pkgType & "]")

  echo ""

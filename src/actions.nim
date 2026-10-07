# ========================================================================================
#
#                                   Nova
#                                 Actions
#
# ========================================================================================

proc handleInfoFallback(target: string) =
  var found = false
  if hasCommand("flatpak"):
    if execCmd("flatpak info " & target & " 2>/dev/null") == 0:
      found = true
  if not found and hasCommand("snap"):
    if execCmd("snap info " & target & " 2>/dev/null") == 0:
      found = true
  if not found:
    errorMsg(
      "Could not find package info for '" & target & "' natively or via Flatpak/Snap."
    )
    quit(1)

proc handleInstallAction(pkgMan: string, targetStr: string) =
  let currentList = loadOrCreateRepoList(repoFile)
  var foundInManifest = false

  # Check if target is already in the manifest
  for entry in currentList:
    if (entry.hasKey("pkg_name") and entry["pkg_name"].getStr().toLowerAscii() == targetStr.toLowerAscii()) or 
       (entry.hasKey("repo") and entry["repo"].getStr().toLowerAscii() == targetStr.toLowerAscii()):
      debug "Found package \'", targetStr, "\' in manifest."
      foundInManifest = true
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
      let isStale = (normalizeVersion(installedVer) != normalizeVersion(manifestVer)) and (manifestVer.len > 0)

      if isMissing or isStale:
        if isMissing:
          debug "Package '" & pkgName & "' is not present on the host system. Installing..."
        else:
          infoMsg(
            "Upgrade detected for '" & pkgName & "': Local (" & installedVer &
              ") ➡️ Tracked (" & manifestVer & ")"
          )

        # Install Package
        waitFor installPkg(pkgMan, entry)
        break

      else:
        styledWrite(stdout, fgGreen, styleBright, pkgName, resetStyle)
        styledWrite(stdout, " is already the newest version ")
        styledWriteLine(stdout, fgBlue, styleBright, installedVer, resetStyle)

        styledEcho(fgWhite, styleBright, "Nothing for Nova to do.", resetStyle)
        quit(0)

  # If target's not in manifest and it's a Git repo, add it then install
  if not foundInManifest and getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
    infoMsg("Interpreted target as Git repository.")
    waitFor addGitRepo(pkgMan, targetStr)

    # Reload to capture the new addition
    let repoName = getRepoName(targetStr).toLowerAscii()
    let updatedList = loadOrCreateRepoList(repoFile)

    for entry in updatedList:
      if entry.hasKey("repo") and entry["repo"].getStr().toLowerAscii() == repoName:
        # Install Package
        waitFor installPkg(pkgMan, entry)
        break

# Actions to run before native commands
proc runPreExecutionHooks(pkgMan: string, action: Action, targetStr: string) =
  debug "running pre exec actions"
  case action
  of actInstall:
    handleInstallAction(pkgMan, targetStr)

  of actAddRepo:
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      waitFor pkgMan.addGitRepo(targetStr)
      quit(0)

  of actRemoveRepo:
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      removeGitRepo(targetStr)
      quit(0)

  of actListRepos:
    styledEcho(fgWhite, styleBright, " System Repositories:", resetStyle)

  of actStatus:
    let nativeCmd = getNativeCommand(pkgMan, action, targetStr)
    let (output, _) = execCmdEx(nativeCmd)
    parseAndPrintStatus(pkgMan, targetStr, output)
    quit(0)

  of actInfo:
    let nativeCmd = getNativeCommand(pkgMan, action, targetStr)
    let (output, exitCode) = execCmdEx(nativeCmd)
    if exitCode == 0:
      echo output.strip()
      quit(0)
    else:
      warnMsg("Native lookup missed. Cascading down...")
      handleInfoFallback(targetStr)
      quit(0)

  else:
    # Allow other standard actions to flow through cleanly
    discard

# Actions to run after native commands
proc runPostExecutionHooks(pkgMan: string, action: Action, targetStr: string) =
  debug "running post exec actions"
  case action
  of actRefresh:     waitFor refreshGitRepos(pkgMan)
  of actUpgrade:     waitFor upgradeGitRepos(pkgMan)
  of actListRepos:   listGitRepos()
  of actListUpdates: listGitUpdates(pkgMan)
  else: discard

# ========================================================================================
#
#                                   Nova
#                                 Actions
#
# ========================================================================================

proc handleInfoFallback(target: string) =
  for cmd in ["flatpak", "snap"]:
    if hasCommand(cmd) and execCmd(cmd & " info " & target & " 2>/dev/null") == 0:
      return
  errorMsg("Could not find package info for \'", target, "\' natively or via Flatpak/Snap.")
  quit(1)

proc parseAction(arg: string): Action =
  case arg.toLowerAscii()
  of "search": actSearch
  of "install": actInstall
  of "reinstall": actReinstall
  of "remove", "rm": actRemove
  of "autoremove": actAutoremove
  of "refresh", "update": actRefresh
  of "upgrade": actUpgrade
  of "repo-add", "add-repo", "add": actAddRepo
  of "repo-remove", "remove-repo": actRemoveRepo
  of "list": actListVersions
  of "list-repos": actListRepos
  of "list-installed": actListInstalled
  of "list-updates", "list-upgrades": actListUpdates
  of "status", "stat": actStatus
  of "show", "info": actInfo
  of "history": actHistory
  else: actUnknown

# Actions to run before native commands
proc runPreExecutionHooks(pkgMan: string, action: Action, targetStr: string) =
  debug "running pre exec actions"
  case action
  of actInstall:
    installPkg(pkgMan, targetStr)

  of actAddRepo:
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      waitFor pkgMan.addGitRepo(targetStr)
      quit(0)

  of actRemoveRepo:
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      removeGitRepo(targetStr)
      quit(0)

  of actListRepos, actListInstalled, actListUpdates:
    styledEcho(fgWhite, styleBright, " System Repositories:", resetStyle)

  of actListVersions:
    listPkgVersions(pkgMan, targetStr)
    quit(0)

  of actStatus:
    showPkgStatus(pkgMan, targetStr)
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
  of actRefresh:       waitFor refreshGitRepos(pkgMan)
  of actUpgrade:       waitFor upgradeGitRepos(pkgMan)
  of actListRepos:     listGitRepos(pkgMan)
  of actListInstalled: listGitPkgs(pkgMan)
  of actListUpdates:   listGitUpdates(pkgMan)
  else: discard

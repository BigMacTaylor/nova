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
proc runPreExecutionHooks(pkgMan: string, action: Action, targetStr: string, targets: seq[string]) =
  debug "running pre exec actions"
  case action
  of actInstall:
    if targets.len > 0:
      installPkg(pkgMan, targets)
    else:
      errorMsg("The 'install' command requires at least one package argument.")
      quit(1)

  of actRemove:
    if targets.len > 0:
      removePkg(pkgMan, targets)
    else:
      errorMsg("The 'remove' command requires at least one package argument.")
      quit(1)

  of actAddRepo:
    if targets.len > 0:
      for target in targets:
        if getSourceType(target) in {srcGithubRepo, srcGitlabRepo}:
          waitFor addGitRepo(pkgMan, target)
      quit(0)
    else:
      errorMsg("The 'add' command requires at least one repository target.")
      quit(1)

  of actRemoveRepo:
    if targets.len > 0:
      for target in targets:
        if getSourceType(target) in {srcGithubRepo, srcGitlabRepo}:
          removeGitRepo(target)
      quit(0)
    else:
      errorMsg("The 'remove-repo' command requires at least one repository target.")
      quit(1)

  of actUpgrade:
    if targets.len > 0:
      upgradePkg(pkgMan, targets)

  of actListRepos:
    styledEcho(fgWhite, styleBright, " System Repositories:", resetStyle)

  of actListInstalled:
    styledEcho(fgWhite, styleBright, " Installed System Packages:", resetStyle)

  of actListUpdates:
    styledEcho(fgWhite, styleBright, " Available System Updates:", resetStyle)

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
      debug "Native lookup missed. Cascading down..."
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

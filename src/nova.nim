# ========================================================================================
#
#                                   Nova
#                               by Mac Taylor
#
# ========================================================================================

const version = "0.0.6"

import std/[json, os, posix, osproc, strutils, asyncdispatch]
import std/[httpclient, terminal, unicode, parseopt]

type Action = enum
  actSearch
  actAddRepo
  actInstall
  actReinstall
  actRemove
  actRemoveRepo
  actAutoremove
  actRefresh
  actUpgrade
  actListRepos
  actListInstalled
  actListUpdates
  actInfo
  actStatus
  actHistory
  actUnknown

type SourceType = enum
  srcLocalFile
  srcPpa
  srcGithubRepo
  srcGitlabRepo
  srcGenericUrl

type PkgType = enum
  Deb
  Rpm
  AppImage
  Flatpak
  Snap
  Binary
  Source

type Repo = tuple
  name: string # GitHub Repository Name (e.g., "sharkdp/bat")
  pkgName: string # Native Package Name (e.g., "bat")
  pkgType: PkgType # Deb, Binary, AppImage etc.
  version: string # Release Tag (e.g., "v0.24.0")
  downloadUrl: string # Download URL

func getDataDir(): string =
  # Get XDG_DATA_HOME or default "~/.local/share"
  let dir = getEnv("XDG_DATA_HOME", os.getHomeDir() / ".local/share")
  return dir / "nova"

let repoFile = getDataDir() / "repositories.json"
var preferMusl = false
var includePrerelease = false

include /[ui, commands, parsers, repo_man, pkg_man, status]

template printHelp() =
  const msg = """Nova:
  A wrapper for native package managers, that
  can install packages directly from git repositories.

Usage:
  nova [Options] Command [Args]...

Options:
  -h, --help      Show this help message
  -v, --version   Show version number and exit
  --prefer-musl   Prefer musl over glibc (testing)
  --include-prerelease  Allow beta, rc, and nightly versions over stable releases (testing)

Commands:
  search          Search for a package
  install         Install package <name> or repo <owner/repo>
  reinstall       Reinstall one or more packages
  remove          Remove one or more packages
  autoremove      Automatically clean up unused dependencies
  refresh         Refresh the package cache and repos
  update          Update 'same as refresh'
  upgrade         Upgrade all packages
  add-repo        Add system or git repo <owner/repo> 
  remove-repo     Remove repo from repo list
  list-repos      List all tracked repos
  list-installed  List installed packages
  list-updates    List available updates
  status          Display install status, version, and size
  show            Show detailed information about a package
  info            Display information 'same as show'
  history         Show installation history

Examples:
  nova add burntsushi/ripgrep
  nova install ripgrep

  nova add-repo https://github.com/BigMacTaylor/griddle
  nova install griddle
"""

  echo formatHelpString(msg)

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

# ----------------------------------------------------------------------------------------
#                                    Main
# ----------------------------------------------------------------------------------------

proc main() =
  var p = initOptParser(
    commandLineParams(), 
    shortNoVal = {'h', 'v'}, 
    longNoVal = @["help", "version", "prefer-musl", "include-prerelease"]
  )

  var firstAction = ""
  var action: Action = actUnknown
  var targets: seq[string] = @[]

  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      case p.key.toLowerAscii()
      of "h", "help":
        printHelp()
        quit(0)
      of "v", "version":
        echo "nova version: " & version
        quit(0)
      of "prefer-musl":
        preferMusl = true
      of "include-prerelease":
        includePrerelease = true
      else:
        echo "Error: Unknown option \'", p.key, "\'"
        echo "Use -h for help \n"
        quit(1)
    of cmdArgument:
      if firstAction.len == 0:
        firstAction = p.key
        action = parseAction(firstAction)
      else:
        targets.add(p.key)

  if firstAction.len == 0:
    printHelp()
    quit(0)

  if action == actUnknown:
    errorMsg("Unknown action \'", firstAction, "\'")
    printHelp()
    quit(1)

  var targetStr = targets.join(" ")
  if action in {
    actAddRepo, actSearch, actInstall, actReinstall, actRemove, actRemoveRepo, actInfo,
    actStatus,
  } and targetStr.len == 0:
    errorMsg("The '", firstAction, "' command requires at least one argument.")
    quit(1)

  let pkgMan = getPackageManager()
  if pkgMan == "unknown":
    errorMsg("Could not detect system package manager.")
    quit(1)

  # Actions to run before native commands
  case action
  of actInstall:
    debug "actInstall"
    let currentList = loadOrCreateRepoList(repoFile)
    var foundInManifest = false

    # Check if the app argument is already in the manifest
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

          # Fetch the latest asset release from downloadUrl
          let downloadedPayload = waitFor downloadLatestRelease(downloadUrl)

          if downloadedPayload.len == 0 or not fileExists(downloadedPayload):
            errorMsg("Failed to download package for your architecture")
            quit(1)

          targetStr = downloadedPayload
          break

        else:
          styledWrite(stdout, fgGreen, styleBright, pkgName, resetStyle)
          styledWrite(stdout, " is already the newest version ")
          styledWriteLine(stdout, fgBlue, styleBright, installedVer, resetStyle)

          styledEcho(fgWhite, styleBright, "Nothing for Nova to do.", resetStyle)
          quit(0)

    # If it's not in manifest but is a Git repo, add it then fetch it
    if not foundInManifest and getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      if pkgMan notin ["apt", "nala", "dnf"]:
        errorMsg(
          "Direct Git package installation is currently only supported for APT and DNF."
        )
        quit(1)

      infoMsg("Interpreted target as Git repository.")
      waitFor addGitRepo(pkgMan, targetStr)

      let repoName = getRepoName(targetStr).toLowerAscii()
      let updatedList = loadOrCreateRepoList(repoFile) # Reload to capture the new addition

      for entry in updatedList:
        if entry.hasKey("repo") and entry["repo"].getStr().toLowerAscii() == repoName:
          let downloadUrl = entry["download_url"].getStr()
          let downloadedPayload = waitFor downloadLatestRelease(downloadUrl)

          if downloadedPayload.len == 0 or not fileExists(downloadedPayload):
            errorMsg("Failed to download package for your architecture")
            quit(1)

          targetStr = downloadedPayload
          break

  of actAddRepo:
    debug "actAddRepo"
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      waitFor pkgMan.addGitRepo(targetStr)
      quit(0)

  of actRemoveRepo:
    debug "actRemoveRepo"
    if getSourceType(targetStr) in {srcGithubRepo, srcGitlabRepo}:
      removeGitRepo(targetStr)
      quit(0)

  of actListRepos:
    debug "actListRepos"
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
      warnMsg("Native entry missed. Cascading lookup down to global namespaces...")
      handleInfoFallback(targetStr)
      quit(0)
  else:
    discard # Allow all other standard native manager actions to flow through cleanly

  # Execute standard native commands
  let exitCode = runNativeCommand(pkgMan, action, targetStr)

  # Actions to run after native commands
  case action
  of actRefresh:
    waitFor refreshGitRepos(pkgMan)
  of actUpgrade:
    waitFor upgradeGitRepos(pkgMan)
  of actListRepos:
    listGitRepos()
  of actListUpdates:
    listGitUpdates(pkgMan)
  else:
    discard

  # Clean up file system caches
  if targetStr.contains(getTempDir()):
    discard tryRemoveFile(targetStr)
    try: removeDir(getTempDir() / "nova-cache-" & $getuid())
    except CatchableError: discard
        
  quit(exitCode)

if isMainModule:
  main()

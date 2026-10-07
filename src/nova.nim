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

include /[ui, commands, parsers, packages, repo_man, pkg_man, status, actions]

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

  # Run actions before native commands
  runPreExecutionHooks(pkgMan, action, targetStr)

  # Execute standard native commands
  let exitCode = runNativeCommand(pkgMan, action, targetStr)

  # Run actions after native commands
  runPostExecutionHooks(pkgMan, action, targetStr)

  # Clean up file system caches
  if targetStr.contains(getTempDir()):
    discard tryRemoveFile(targetStr)
    try: removeDir(getTempDir() / "nova-cache-" & $getuid())
    except CatchableError: discard
        
  quit(exitCode)

if isMainModule:
  main()

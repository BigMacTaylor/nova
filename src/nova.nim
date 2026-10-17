# ========================================================================================
#
#                                   Nova
#                               by Mac Taylor
#
# ========================================================================================

const version = "0.0.7"

import std/[json, os, posix, osproc, strutils, asyncdispatch]
import std/[sequtils, httpclient, terminal, unicode, parseopt]

type Action* = enum
  actSearch
  actAddRepo
  actInstall
  actReinstall
  actRemove
  actRemoveRepo
  actAutoremove
  actRefresh
  actUpgrade
  actListVersions
  actListRepos
  actListInstalled
  actListUpdates
  actInfo
  actStatus
  actHistory
  actUnknown

type SourceType* = enum
  srcLocalFile
  srcPpa
  srcGithubRepo
  srcGitlabRepo
  srcGenericUrl

type PkgType* = enum
  Deb
  Rpm
  Pacman
  AppImage
  Flatpak
  Snap
  Binary
  Source

type Repo* = tuple
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

proc installGitPkg(pkgMan: string, pkgEntry: JsonNode) {.async.}
include /[ui, help, commands, parsers, repo_man, packages]
include /[list, pkg_man, status, versions, actions]

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
      of "help-all":
        printDetailedHelp()
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
    actStatus, actListVersions,
  } and targetStr.len == 0:
    errorMsg("The '", firstAction, "' command requires at least one argument.")
    quit(1)

  if action in {actStatus, actListVersions} and targets.len > 1:
    errorMsg("The '", firstAction, "' command only accepts one argument.")
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

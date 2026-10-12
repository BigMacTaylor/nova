# ========================================================================================
#
#                                   Nova
#                                 Versions
#
# ========================================================================================

proc printPkgVersions(pkgName: string, versions: seq[(PkgType, string)]) =
  ## Prints all discovered installation formats.
  if versions.len == 0:
    errorMsg("No versions of \'", pkgName, "\' found.")
    return

  styledWriteLine(stdout, fgGreen, styleBright, pkgName, resetStyle)

  # Use an index loop to cleanly check for the last element
  for i, pair in versions:
    let (pkgType, versionStr) = pair
    if i == versions.high:
      styledWriteLine(stdout, "  └── ", fgYellow, ("[" & $pkgType & "]").alignLeft(15), fgBlue, styleBright, versionStr, resetStyle)

    else:
      styledWriteLine(stdout, "  ├── ", fgYellow, ("[" & $pkgType & "]").alignLeft(15), fgBlue, styleBright, versionStr, resetStyle)
  echo ""

proc getFlatpakVersion(pkgName: string): string =
  ## Queries flatpak for an exact application ID or name match
  # flatpak info --show-version matches standard IDs like org.videolan.VLC
  let (output, exitCode) = execCmdEx("flatpak info --show-version " & pkgName)
  if exitCode == 0 and output.strip.len > 0:
    return output.strip
  return ""

proc getSnapVersion(pkgName: string): string =
  ## Queries snap list to find the version of a specific package
  # snap list <name> outputs headings, then details. We parse the version column.
  let (output, exitCode) = execCmdEx("snap list " & pkgName)
  if exitCode == 0:
    let lines = output.strip.splitLines()
    if lines.len > 1:
      # Line 1 is the match data; columns are typically: Name, Version, Rev, Tracking, Publisher, Notes
      let parts = strutils.splitWhitespace(lines[1])
      if parts.len > 1:
        return parts[1] # The version column
  return ""

proc listPkgVersions(pkgMan: string, targetStr: string) =
  let repoList = loadOrCreateRepoList(repoFile)
  var installedVer = ""
  var pkgName = targetStr
  var versions: seq[(PkgType, string)] = @[]

  # Check if target is natively installed package (Deb, Rpm)
  let nativeCmd = getNativeCommand(pkgMan, actStatus, targetStr)
  let (output, exitCode) = execCmdEx(nativeCmd)

  if exitCode == 0 and output.len > 0:
    let nativeVer = getNativeVersion(pkgMan, pkgName)
    let nativeType =
      case pkgMan
      of "apt", "nala": Deb
      of "dnf", "yum", "zypper": Rpm
      else: Binary

    versions.add((nativeType, nativeVer))

  # Check if target is already in the manifest
  for entry in repoList:
    let matchName = entry.getOrDefault("pkg_name").getStr("").toLowerAscii()
    let matchRepo = entry.getOrDefault("repo").getStr("").toLowerAscii()
    let searchStr = targetStr.toLowerAscii()

    if matchName == searchStr or matchRepo == searchStr:
      debug "Found package '", targetStr, "' in manifest."

      pkgName = entry.getOrDefault("pkg_name").getStr(targetStr)
      let pkgType =
        try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
        except ValueError: Binary

      if pkgType == Deb or pkgType == Rpm:
        break

      # Get currently installed version
      installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)

      # Check if it's missing
      if installedVer != "":
        versions.add((pkgType, installedVer)) 
      break

  # Check for Flatpak Installation
  let flatpakVer = getFlatpakVersion(pkgName)
  if flatpakVer != "":
    versions.add((Flatpak, flatpakVer))

  # Check for Snap Installation
  let snapVer = getSnapVersion(pkgName)
  if snapVer != "":
    versions.add((Snap, snapVer))

  printPkgVersions(pkgName, versions)

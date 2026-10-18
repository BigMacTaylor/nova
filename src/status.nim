# ========================================================================================
#
#                                   Nova
#                                  Status
#
# ========================================================================================

proc printPkgStatus(pkgName, pkgVer, pkgSize: string) =
  styledWriteLine(stdout, fgWhite, styleBright, "Package:   ", resetStyle, pkgName)
  stdout.write "  Status:  "
  if (pkgVer.len == 0) or (pkgVer.toLower == "none"):
    styledWriteLine(stdout, fgRed, styleBright, "Not Installed")
  else:
    styledWriteLine(stdout, fgGreen, styleBright, "Installed")
  echo "  Version: " & pkgVer
  echo "  Size:    " & pkgSize
  echo ""

proc formatBytes(bytesStr: string): string =
  try:
    let bytes = bytesStr.strip().parseInt()
    if bytes <= 0:
      return "Unknown"
    elif bytes < 1024:
      return $bytes & " B"
    elif bytes < 1024 * 1024:
      return (bytes.float / 1024.0).formatFloat(ffDecimal, 1) & " KB"
    else:
      return (bytes.float / (1024.0 * 1024.0)).formatFloat(ffDecimal, 1) & " MB"
  except:
    return bytesStr.strip()

proc printNativeStatus(pkgMan: string, target: string, output: string) =
  var version = "none"
  var size = "unknown"
  let cleanOut = output.strip()

  if cleanOut.len > 0:
    let components = cleanOut.split('|')
    case pkgMan
    of "apt", "nala":
      if components.len >= 3 and "installed" in components[0].toLowerAscii() and
        "not-installed" notin components[0].toLowerAscii():
        version = components[1].strip()
        size = components[2].strip()
    of "dnf":
      if components.len >= 3 and components[0].strip() == "installed":
        version = components[1].strip()
        size = formatBytes(components[2])
    of "pacman":
      if components.len >= 3 and components[0].strip().len > 0:
        version = components[1].strip()
        size = components[2].strip()
    of "zypper":
      let lowerOut = cleanOut.toLowerAscii()
      if "installed : yes" in lowerOut or "installed: yes" in lowerOut:
        for comp in components:
          let parts = comp.split(':', 1)
          if parts.len == 2:
            let key = parts[0].toLowerAscii()
            if "version" in key: version = parts[1].strip()
            elif "installed size" in key: size = parts[1].strip()
    of "apk":
      if components.len >= 2:
        size = components[0].strip()
        version = components[^1].strip()
    of "xbps":
      version = cleanOut
    of "emerge":
      let lines = cleanOut.splitLines()
      if lines.len > 0 and lines[0].strip().len > 0:
        version = lines[0].strip()
        if lines.len > 1: size = lines[1].strip()
    of "brew":
      if "built from source" in cleanOut.toLowerAscii() or
        "installed at" in cleanOut.toLowerAscii():
        version = "Detected"
        size = "Managed dynamically"

  printPkgStatus(target, version, size)

proc showPkgStatus(pkgMan: string, targetStr: string) =
  debug "showPkgStatus"
  let repoList = loadOrCreateRepoList(repoFile)

  # Check if target is already in the manifest
  let foundIndex = repoList.findInManifest(targetStr)
  if foundIndex != -1:
    debug "Found package \'", targetStr, "\' in manifest."
    let entry = repoList[foundIndex]
    let pkgType =
      try: parseEnum[PkgType](entry.getOrDefault("pkg_type").getStr("Binary"))
      except ValueError: Binary

    if pkgType notin {Deb, Rpm, Pacman}:
      let pkgName = entry.getOrDefault("pkg_name").getStr("")

      # Get currently installed version
      let installedVer = getInstalledVersion(pkgMan, pkgName, pkgType)
      if installedVer.len > 0:
        printPkgStatus(pkgName, installedVer, "unknown")
        return

      debug "Package '" & pkgName & "' not found on host system. Skipping..."

  # Check if target is natively installed package
  let nativeCmd = getNativeCommand(pkgMan, actStatus, targetStr)
  let (output, exitCode) = execCmdEx(nativeCmd)

  debug "Exit Code: ", exitCode, " ", output

  if exitCode == 0:
    printNativeStatus(pkgMan, targetStr, output)
  else:
    printPkgStatus(targetStr, "none", "unknown")

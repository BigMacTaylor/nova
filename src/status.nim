# ========================================================================================
#
#                                   Nova
#                                  Status
#
# ========================================================================================

proc formatBytes(bytesStr: string): string =
  try:
    let bytes = bytesStr.strip().parseInt()
    if bytes <= 0: return "Unknown"
    elif bytes < 1024: return $bytes & " B"
    elif bytes < 1024 * 1024: return (bytes.float / 1024.0).formatFloat(ffDecimal, 1) & " KB"
    else: return (bytes.float / (1024.0 * 1024.0)).formatFloat(ffDecimal, 1) & " MB"
  except:
    return bytesStr.strip()

proc parseAndPrintStatus(pkgMan: string, target: string, output: string) =
  var isInstalled = false
  var versionStr = "None"
  var sizeStr = "Unknown"
  let cleanOut = output.strip()

  if cleanOut.len > 0:
    case pkgMan
    of "apt":
      let components = cleanOut.split('|')
      if components.len >= 3:
        isInstalled = "installed" in components[0].toLowerAscii()
        versionStr = components[1].strip()
        sizeStr = components[2].strip()

    of "dnf":
      let components = cleanOut.split('|')
      if components.len >= 3 and components[0].strip() == "installed":
        isInstalled = true
        versionStr = components[1].strip()
        sizeStr = formatBytes(components[2])

    of "pacman":
      let components = cleanOut.split('|')
      if components.len >= 3:
        isInstalled = true
        versionStr = components[1].strip()
        sizeStr = components[2].strip()

    of "zypper":
      let components = cleanOut.split('|')
      isInstalled = "yes" in cleanOut.toLowerAscii() or "installed" in cleanOut.toLowerAscii()
      for comp in components:
        let parts = comp.split(':', 1)
        if parts.len == 2:
          let key = parts[0].toLowerAscii().strip()
          let val = parts[1].strip()
          if "version" in key: versionStr = val
          elif "installed size" in key: sizeStr = val

    of "apk":
      isInstalled = true
      let components = cleanOut.split('|')
      if components.len > 1:
        sizeStr = components[0].strip()
        versionStr = components[^1].strip()

    of "brew":
      isInstalled = "installed" in cleanOut
      versionStr = "Detected"
      sizeStr = "Managed dynamically"
      
    else: discard

  styledWriteLine(stdout, fgWhite, styleBright, "Package Status: ", resetStyle, target)
  stdout.write "  Status:  "
  if isInstalled: styledWriteLine(stdout, fgGreen, styleBright, "Installed")
  else: styledWriteLine(stdout, fgRed, styleBright, "Not Installed")
  echo "  Version: " & versionStr
  echo "  Size:    " & sizeStr

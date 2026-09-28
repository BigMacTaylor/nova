# ========================================================================================
#
#                                   Nova
#                                  Status
#
# ========================================================================================

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

proc parseAndPrintStatus(pkgMan: string, target: string, output: string) =
  var isInstalled = false
  var version = "None"
  var size = "Unknown"
  let cleanOut = output.strip()

  # If terminal execution yielded nothing, the package definitely isn't installed
  if cleanOut.len == 0:
    isInstalled = false
  else:
    case pkgMan
    of "apt", "nala":
      let components = cleanOut.split('|')
      if components.len >= 3:
        # Check if the status explicitly says 'installed' and not 'not-installed'
        let statusField = components[0].toLowerAscii()
        isInstalled = "installed" in statusField and "not-installed" notin statusField
        if isInstalled:
          version = components[1].strip()
          size = components[2].strip()

    of "dnf":
      let components = cleanOut.split('|')
      if components.len >= 3 and components[0].strip() == "installed":
        isInstalled = true
        version = components[1].strip()
        size = formatBytes(components[2])

    of "pacman":
      let components = cleanOut.split('|')
      # pacman outputs nothing or standard error on failure. If data exists, it's installed.
      if components.len >= 3 and components[0].strip().len > 0:
        isInstalled = true
        version = components[1].strip()
        size = components[2].strip()

    of "zypper":
      # Ensure it's explicitly installed and not matching an error sentence
      let lowerOut = cleanOut.toLowerAscii()
      if ("installed: yes" in lowerOut or "installed : yes" in lowerOut) and "not installed" notin lowerOut:
        isInstalled = true
        let components = cleanOut.split('|')
        for comp in components:
          let parts = comp.split(':', 1)
          if parts.len == 2:
            let key = parts[0].toLowerAscii().strip()
            let val = parts[1].strip()
            if "version" in key:
              version = val
            elif "installed size" in key:
              size = val

    of "apk":
      let components = cleanOut.split('|')
      if components.len >= 2:
        isInstalled = true
        size = components[0].strip()
        version = components[^1].strip()

    of "xbps":
      # xbps-query -W returns properties natively if installed, empty if missing
      if cleanOut.len > 0:
        isInstalled = true
        version = cleanOut # xbps-query -W targets raw field dumps directly

    of "emerge":
      let components = cleanOut.split('\n')
      if components.len > 0 and components[0].strip().len > 0:
        isInstalled = true
        version = components[0].strip()
        if components.len > 1:
          size = components[1].strip()

    of "brew":
      # Avoid false matches on descriptive text lines by demanding positive layout confirmation
      if "built from source" in cleanOut.toLowerAscii() or "installed at" in cleanOut.toLowerAscii():
        isInstalled = true
        version = "Detected"
        size = "Managed dynamically"
    else:
      discard

  styledWriteLine(stdout, fgWhite, styleBright, "Package:   ", resetStyle, target)
  stdout.write "  Status:  "
  if isInstalled:
    styledWriteLine(stdout, fgGreen, styleBright, "Installed")
  else:
    styledWriteLine(stdout, fgRed, styleBright, "Not Installed")
  echo "  Version: " & version
  echo "  Size:    " & size
  echo ""

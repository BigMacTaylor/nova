# ========================================================================================
#
#                                   Nova
#                                 Parsers
#
# ========================================================================================

proc normalizeVersion*(asset: string): string =
  var i = 0
  while i < asset.len:
    # Look for digits, or a 'v' followed by a digit
    let isStartOfVersion = asset[i] in Digits or 
      (asset[i] == 'v' and i + 1 < asset.len and asset[i+1] in Digits)

    # Ensure it's bounded by a standard separator not 'x86_64' or 'linux64'
    let isBounded = i == 0 or asset[i-1] in {'-', '_', '.', ' '}

    if isStartOfVersion and isBounded:
      # If it's a leading 'v', skip past it to keep the output purely numeric
      var nextIdx = i
      if asset[nextIdx] == 'v': inc(nextIdx)

      # Collect only numeric components (digits and dots)
      var cleanVer = ""
      var versionDots = 0

      while nextIdx < asset.len and asset[nextIdx] in (Digits + {'.'}):
        # Only count this as a valid version divider if it's a dot 
        # that is immediately followed by another digit (e.g., .8 or .2)
        if asset[nextIdx] == '.' and nextIdx + 1 < asset.len and asset[nextIdx+1] in Digits:
          inc(versionDots)
        cleanVer.add(asset[nextIdx])
        inc(nextIdx)

      # Strip trailing dot from file extensions
      cleanVer = cleanVer.strip(chars = {'.'})

      # Must have at least one internal version dot divider, and end with a digit
      if versionDots >= 1 and cleanVer.len > 0 and cleanVer[cleanVer.high] in Digits:
        return cleanVer

    inc(i)

  return "none"

proc getNativeVersion(pkgMan, pkgName: string): string =
  ## Returns the version string natively installed on the host machine.
  ## Returns "" if the package is missing or not installed.
  debug "getNativeVersion"
  let nativeCmd = getNativeCommand(pkgMan, actStatus, pkgName)
  let (output, exitCode) = execCmdEx(nativeCmd)
  let cleanOut = output.strip()

  if exitCode != 0 or cleanOut.len == 0:
    return ""

  let components = cleanOut.split('|')
  
  case pkgMan
  of "apt", "nala", "dnf":
    # Outputs format: Status|Version|Size
    if components.len >= 2 and "installed" in components[0].toLowerAscii():
      return components[1].strip()

  of "pacman":
    # Output schema: Name|Version|Installed Size|
    if components.len >= 2:
      return components[1].strip()

  of "zypper":
    # Output schema: Yes (or No/status)|Version|Installed Size|
    if components.len >= 2:
      let isInstalled = components[0].strip().toLowerAscii()
      if isInstalled in ["yes", "i", "installed"]:
        return components[1].strip()

  of "apk":
    # Output layout: size-description|pkgname-version
    # format from: apk info -s | tr '\n' '|'; apk info -v
    if components.len >= 2:
      let trailingPart = components[^1].strip() # Contains pkgname-version
      if trailingPart.startsWith(pkgName & "-"):
        return trailingPart[pkgName.len + 1 .. ^1]

  of "xbps":
    # Output layout: ii pkgname-version description
    # xbps-query -W outputs plain metadata space-separated lines
    let tokens = strutils.splitWhitespace(cleanOut)
    if tokens.len >= 2 and tokens[0] == "ii":
      let pkgAndVer = tokens[1]
      if pkgAndVer.startsWith(pkgName & "-"):
        return pkgAndVer[pkgName.len + 1 .. ^1]

  of "emerge":
    # Output layout: category/pkgname-version
    # from qlist -Iv package
    let lines = cleanOut.splitLines()
    if lines.len > 0:
      let matchingLine = lines[0].strip()
      if '-' in matchingLine:
        # Splits the slot/version details out from the package atom name
        let parts = matchingLine.split('-')
        if parts.len >= 2:
          return matchingLine.split('-', 1)[1]

  of "brew":
    # Output schema: raw JSON via brew info --json=v2
    try:
      let jsonNode = parseJson(cleanOut)
      let formulae = jsonNode.getOrDefault("formulae")
      if formulae != nil and formulae.len > 0:
        let linkedPkg = formulae[0].getOrDefault("linked_keg")
        if linkedPkg.kind == JString and linkedPkg.getStr().len > 0:
          return linkedPkg.getStr()
    except CatchableError:
      discard

  else:
    discard

  return ""

proc getAppImageMountVer(appImagePath: string): string =
  ## Extracts the version string from an AppImage by mounting it via FUSE,
  ## reading its .desktop file metadata, and cleanly unmounting it.
  if not fileExists(appImagePath):
    return ""

  # Start the AppImage mount process in the background
  # poStdErrToStdOut combines streams so we can catch early initialization errors
  var process = startProcess(
    command = appImagePath, 
    args = ["--appimage-mount"], 
    options = {poUsePath, poDaemon, poStdErrToStdOut}
  )
  
  if process == nil:
    return ""

  var mountDir = ""
  
  try:
    # Use standard File reading from the raw process output handle
    var outFile: File
    if open(outFile, process.outputHandle, fmRead):
      # Read the first line safely (which contains the /tmp mount path)
      mountDir = outFile.readLine().strip()
      close(outFile) # Free handle lock

    # Verify we got a valid directory path and wait briefly for FUSE to sync
    if mountDir.len > 0 and dirExists(mountDir):
      sleep(50) # Tiny synchronization window for the virtual file system loop
      
      # Scan the mount directory for the application's configuration .desktop file
      for kind, path in walkDir(mountDir):
        if kind == pcFile and path.endsWith(".desktop"):
          for line in lines(path):
            let cleanLine = line.strip()
            if cleanLine.startsWith("X-AppImage-Version="):
              let parts = cleanLine.split('=', 1)
              if parts.len == 2:
                result = parts[1].strip()
                break
          if result.len > 0: break

  except CatchableError:
    discard

  finally:
    # Safely close down background runtimes and eliminate zombie paths
    process.terminate()
    discard process.waitForExit()
    process.close()

  return result

proc getAppImageVersion(appName: string): string =
  ## Scrapes the static binary declaration of an AppImage payload 
  ## to extract its internal version signature safely.
  debug "get AppImage version"
  let appsDir = os.getHomeDir() / ".local" / "bin"
  let appImagePath = appsDir / appName

  if not fileExists(appImagePath):
    debug "AppImage file does not exist"
    return ""

  # Uses strings to extract the exact match without mounting/running code
  let cmd = "strings " & quoteShell(appImagePath) & " | grep -m 1 '^X-AppImage-Version='"
  let (output, exitCode) = execCmdEx(cmd)
  
  if exitCode == 0 and '=' in output:
    return output.split('=', 1)[1].strip()

  return getAppImageMountVer(appImagePath)

proc getInstalledVersion(pkgMan, pkgName: string, pkgType: PkgType): string =
  debug "get installed version"
  case pkgType
  of Deb, Rpm:
    return normalizeVersion(getNativeVersion(pkgMan, pkgName))
  of AppImage:
    return normalizeVersion(getAppImageVersion(pkgName))
  else:
    debug "no version installed"
    return "none"

proc loadOrCreateRepoList(fileName: string): JsonNode =
  if fileExists(fileName):
    try:
      return parseFile(fileName)
    except JsonParsingError:
      warnMsg("Could not parse JSON file. Starting fresh.")
      return newJArray()
  else:
    try:
      let dir = splitFile(fileName).dir
      if dir != "":
        createDir(dir)

      # Create the file with a valid empty JSON array
      writeFile(fileName, "[]")
      return newJArray()
    except IOError as e:
      errorMsg("Could not create file or directory due to system permissions: " & e.msg)
      return newJArray()

proc getSourceType*(target: string): SourceType =
  let clean = target.toLowerAscii().strip()

  if clean.startsWith("ppa:"):
    return srcPpa
  elif clean.startsWith("./") or clean.startsWith("../") or
    clean.startsWith("/") or clean.startsWith("file://") or fileExists(target):
    return srcLocalFile
  elif clean.contains("github.com"):
    return srcGithubRepo
  elif clean.contains("gitlab.com"):
    return srcGitlabRepo
  elif clean.split('/').len == 2:
    return srcGithubRepo
  else:
    return srcGenericUrl

proc getRepoName*(target: string): string =
  var clean = target.strip().strip(chars = {'/', '\\'})
  if clean.len == 0:
    return ""

  let prefixes = [
    "https://github.com", "http://github.com", "github.com",
    "git@github.com:", "://://github.com", "://github.com",
    "https://gitlab.com", "http://gitlab.com", "gitlab.com",
    "git@gitlab.com:", "://://gitlab.com", "://gitlab.com"
  ]

  let lowerClean = clean.toLowerAscii()
  var prefixMatched = false

  for prefix in prefixes:
    if lowerClean.startsWith(prefix):
      clean = clean.substr(prefix.len)
      prefixMatched = true
      break

  # Git validation: If it's a full URL but didn't match our supported platforms, exit early
  if not prefixMatched and ("://" in clean or "@" in clean or clean.startsWith("www.")):
    return ""

  # Remove slashes if they linger
  clean = clean.strip(chars = {'/', '\\', ' '})

  # Clean up trailing ".git"
  if clean.toLowerAscii().endsWith(".git"):
    clean.setLen(clean.len - 4)

  # Remove empty tokens caused by duplicate slashes (e.g., owner//repo)
  var rawParts = clean.split({'/', '\\'})
  var parts: seq[string] = @[]
  
  for p in rawParts:
    let trimmed = p.strip()
    if trimmed.len > 0:
      parts.add(trimmed)

  # Enforce that a complete package entity context must have exactly an owner and repository
  if parts.len >= 2:
    return parts[0] & "/" & parts[1]

  # If the string has no slashes, confirm it doesn't contain invalid trailing sub-elements
  if parts.len == 1:
    return parts[0]

  return ""

proc findVersionStart(asset: string): int =
  var i = 0
  while i < asset.len:
    let isStartOfVersion = asset[i] in Digits or 
                           (asset[i] == 'v' and i + 1 < asset.len and asset[i+1] in Digits)
    let isBounded = i == 0 or asset[i-1] in {'-', '_', '.', ' '}
    
    if isStartOfVersion and isBounded:
      let startIdx = i
      var iMove = i
      if asset[iMove] == 'v': inc(iMove)
      
      var dotCount = 0
      while iMove < asset.len and asset[iMove] in (Digits + {'.'}):
        if asset[iMove] == '.': inc(dotCount)
        inc(iMove)
      
      if dotCount >= 1:
        return startIdx
    inc(i)
  return -1

proc cleanKeywords(name: string): string =
  ## Drops architectural noise and platform descriptors from unversioned regions
  result = name
  for keyword in [
    "-linux", "_linux", "-x86", "_x86", "-arm", "_arm", "-riscv", "-anylinux", 
    "-musl", "_musl", "-static", "_static", "-gnu", "_gnu", "-unknown", "_unknown"
  ]:
    let idx = result.find(keyword)
    if idx > 0:
      result = result[0 ..< idx]

proc getPackageName*(asset, pkgExtension, repoPath: string): string =
  # Edge Case: Pure version strings
  let isPureVer = asset[0] in Digits or (asset[0] == 'v' and asset.len > 1 and asset[1] in Digits)
  if isPureVer:
    var idx = if asset[0] == 'v': 1 else: 0
    while idx < asset.len and asset[idx] in (Digits + {'.'}): inc(idx)
    if idx == asset.len or asset[idx] in {'-', '+'}:
      return "unknown"

  # Global aliases up front
  if asset.startsWith("nvim"): return "neovim"

  # Parse via Version boundaries
  let verIdx = findVersionStart(asset)
  if verIdx > 0:
    let separator = asset[verIdx - 1]
    
    if separator == '_':
      # Conventions like "bat-musl_0.26.1" preserve everything on the left side
      return asset[0 ..< verIdx - 1].toLowerAscii()
      
    elif separator == '-':
      # Handle hyphenated structures like "fastfetch-linux-amd64"
      var baseName = asset[0 ..< verIdx - 1].toLowerAscii()
      return cleanKeywords(baseName)

  # Fallback for completely unversioned binaries (e.g., btop-x86_64, tldr-linux-arm64)
  var cleanStr = asset.toLowerAscii()
  let dotPos = cleanStr.find('.')
  if dotPos != -1: cleanStr = cleanStr[0 ..< dotPos] # drop extensions

  return cleanKeywords(cleanStr)

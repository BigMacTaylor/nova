# ========================================================================================
#
#                                   Nova
#                                 Parsers
#
# ========================================================================================

proc stripAnsi*(s: string): string =
  ## Removes ANSI color/style escape sequences from the string.
  var i = 0
  while i < s.len:
    # Look for the ESC character
    if s[i] == '\e' or (s[i] == '\\' and i + 1 < s.len and s[i+1] == 'e'):
      if s[i] == '\\': i += 1
      i += 1 # skip 'e'
      if i < s.len and i < s.len and s[i] == '[':
        while i < s.len and s[i] != 'm': i += 1
        i += 1 # skip 'm'
    else:
      result.add(s[i])
      i += 1

proc normalizeVersion*(asset: string): string =
  # Clean ANSI escape styles and trim whitespace
  var cleanAsset = asset.stripAnsi().strip()
  
  # Remove architecture-specific numbers to prevent false major-version picking (e.g., x86_64 -> x86_arch)
  for arch in ["x86_64", "x86-64", "amd64", "arm64", "riscv64", "aarch64", "linux64", "anylinux"]:
    cleanAsset = cleanAsset.replace(arch, "arch")

  # Fast exclusion check for pure noise files
  let lowerAsset = cleanAsset.toLowerAscii()
  if "linux" in lowerAsset and not anyIt(["-4.", "-v0", "_v0", "linux-arch-1.", "fedora-v"], it in lowerAsset):
    if not anyIt(["0.", "1.", "2.", "3.", "4.", "5.", "6.", "7.", "8.", "9."], it in lowerAsset):
      return ""

  var i = 0
  while i < cleanAsset.len:
    var offset = 0
    if cleanAsset[i] in {'v', 'V'}:
      offset = 1
      if i + 1 < cleanAsset.len and cleanAsset[i+1] == '.': offset = 2
    
    let digitIdx = i + offset
    let isStart = digitIdx < cleanAsset.len and cleanAsset[digitIdx].isDigit
    let isBounded = i == 0 or cleanAsset[i-1] in {'-', '_', '.', ' '} or (cleanAsset[i] in {'v', 'V'} and cleanAsset[i-1].isAlphaAscii)

    if isStart and isBounded:
      var nextIdx = digitIdx
      var cleanVer = ""
      var versionDots = 0
      
      while nextIdx < cleanAsset.len:
        let c = cleanAsset[nextIdx]
        
        # Cease ingestion if hitting system distro payload metadata tags
        if c in {'-', '_', '+'}:
          if nextIdx + 1 < cleanAsset.len:
            let tail = cleanAsset[nextIdx+1 .. ^1].toLowerAscii()
            if tail.startsWith("linux") or tail.startsWith("arch") or tail.startsWith("armhf") or
               tail.startsWith("ubuntu") or tail.startsWith("ghrelease") or tail.startsWith("fc"):
              break
        
        if c.isDigit or c == '.':
          if c == '.': inc(versionDots)
          cleanVer.add(c)
          inc(nextIdx)
        else:
          break

      cleanVer = cleanVer.strip(chars = {'.'})

      if cleanVer.len > 0:
        # Ignore false-positive isolated numbers inside string noise configurations (e.g., ubu24)
        if versionDots == 0 and cleanVer.len <= 2:
          let trailingContext = cleanAsset[nextIdx .. ^1].toLowerAscii()
          if "arch" in trailingContext or "linux" in trailingContext or "ubu" in lowerAsset:
            i = nextIdx
            continue

        let rawSegments = cleanVer.split('.')
        var cleanSegments: seq[string] = @[]
        
        for seg in rawSegments:
          if seg.len == 0: continue
          var normalizedSeg = seg.strip(leading = true, trailing = false, chars = {'0'})
          if normalizedSeg.len == 0: normalizedSeg = "0"
          cleanSegments.add(normalizedSeg)
          if cleanSegments.len == 3: break
        
        while cleanSegments.len < 3:
          cleanSegments.add("0")
          
        return cleanSegments.join(".")

    inc(i)

  return ""

proc compareVersionStrings*(v1, v2: string): int =
  # Returns 1 if the first version is newer
  # -1 if the second version is newer
  let parts1 =
    if v1.len > 0: v1.split('.').map(parseInt)
    else: @[0, 0, 0]
  let parts2 =
    if v2.len > 0: v2.split('.').map(parseInt)
    else: @[0, 0, 0]
  let maxLen = max(parts1.len, parts2.len)

  for i in 0 ..< maxLen:
    # If one version has fewer segments (e.g., "1.0" vs "1.0.1")
    # Missing segments are safely evaluated as 0. 
    let
      num1 = if i < parts1.len: parts1[i] else: 0
      num2 = if i < parts2.len: parts2[i] else: 0
    if num1 < num2:
      return -1
    elif num1 > num2:
      return 1

  # Both versions are equal
  return 0

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

proc getMountedAppImageVer(appImagePath: string): string =
  ## Extracts the version string from an AppImage by mounting it via FUSE,
  ## reading its .desktop file metadata, and cleanly unmounting it.

  # Start the AppImage mount process in the background
  # poStdErrToStdOut combines streams so we can catch early initialization errors
  var process: Process = nil
  try:
    process = startProcess(
      command = appImagePath, 
      args = ["--appimage-mount"], 
      options = {poUsePath, poDaemon, poStdErrToStdOut}
    )
  
    if process == nil:
      return ""

    var mountDir = ""
    var outFile: File

    if open(outFile, process.outputHandle, fmRead):
      # Read the first line safely (which contains the /tmp mount path)
      try:
        mountDir = outFile.readLine().strip()
      finally:
        close(outFile)

    # Verify we got a valid directory path and wait for FUSE to sync
    if mountDir.len > 0:
      var retries = 0
      while retries < 50 and not dirExists(mountDir):
        sleep(25)
        inc(retries)

      if dirExists(mountDir):
        # Scan the mount directory for the application's configuration .desktop file
        for kind, path in walkDir(mountDir):
          if kind == pcFile and path.endsWith(".desktop"):
            try:
              for line in lines(path):
                let cleanLine = line.strip()
                if cleanLine.startsWith("X-AppImage-Version="):
                  let parts = cleanLine.split('=', 1)
                  if parts.len == 2:
                    result = parts[1].strip()
                    break
            except CatchableError:
              discard # individual file IO failures
            if result.len > 0: break

  except CatchableError:
    discard

  finally:
    if process != nil:
      try:
        process.terminate()
        discard process.waitForExit(timeout = 500)
      except CatchableError:
        discard
      finally:
        process.close()

  return result

proc getAppImageVersion(appName: string): string =
  ## Searches the AppImage metadata for version string
  debug "getAppImageVersion"
  let appsDir = os.getHomeDir() / ".local" / "bin"
  let appImagePath = appsDir / appName

  var fs = newFileStream(appImagePath, fmRead)
  if fs != nil:
    try:
      # Read the first 16 bytes to inspect the AppImage Magic Number
      let header = fs.readStr(16)
      
      # AppImage Specification check: Type 2 explicitly embeds 'A', 'I', 0x02 at byte index 8
      let isType2 = header.len >= 11 and header[8] == 'A' and header[9] == 'I' and header[10] == '\x02'
      
      if not isType2:
        debug "Legacy Type 1 AppImage detected. Skipping execution-based extraction pipelines safely."
        # Legacy Type 1 configs generally embed version context into their external filenames 
        # (e.g. app-1.0.0.AppImage). Fall back to parsing the file name string directly.
        fs.close()
        return normalizeVersion(appName)

      # Reset stream head position back to start
      fs.setPosition(0)

      # AppImage embedding rules put metadata definitions in the first 32KB block.
      const scanLimit = 32768

      # Scan the memory buffer for the metadata sequence
      let buffer = fs.readStr(scanLimit)
      let pattern = "X-AppImage-Version="
      let matchPos = buffer.find(pattern)
      
      if matchPos != -1:
        # Extract the version payload terminating at the next control character or newline
        var val = ""
        var idx = matchPos + pattern.len
        while idx < buffer.len:
          let c = buffer[idx]
          if c in {'\0', '\n', '\r'}: break
          val.add(c)
          inc(idx)
        result = val.strip()

    except CatchableError:
      discard
    finally:
      if fs != nil: fs.close()

  # Fall back to process mounting if structural parsing failed
  if result.len == 0:
    debug "Static header extraction failed. Falling back to mounting AppImage..."
    return getMountedAppImageVer(appImagePath)

  return result

proc checkBinaryFlag(binaryPath, flag: string, timeoutMs: int = 500): (string, bool) =
  ## Spawns a sandboxed subprocess with a strict timeout.
  var process: Process = nil
  try:
    # Spawn the process without an attached stdin channel to prevent interactive blocks
    process = startProcess(
      command = binaryPath,
      args = [flag],
      options = {poUsePath, poStdErrToStdOut}
    )
    
    if process == nil: return ("", false)

    # Time Firewall: Track execution loop using exponential backoff up to the timeout ceiling
    var elapsed = 0
    var delay = 2
    var exitCode = -1
    
    while elapsed < timeoutMs:
      if not process.running():
        exitCode = process.peekExitCode()
        break
      
      sleep(delay)
      elapsed += delay
      delay = min(32, delay shl 1) # Cap delay stepping to preserve quick loops

    # If the process is still running after hitting the timeout ceiling, destroy it instantly
    if process.running():
      debug "Process timeout exceeded for flag '" & flag & "'. Terminating hang hazard safely."
      process.terminate()
      discard process.waitForExit(timeout = 50)
      return ("", false)

    # If it finished but exited with a failure code, invalidate this flag lookahead pass
    if exitCode != 0:
      return ("", false)

    # Safely stream out the captured layout payload
    var stream = process.outputStream()
    if stream != nil:
      let output = stream.readAll().strip()
      if output.len > 0:
        return (output, true)

  except CatchableError as e:
    debug "Exception caught during binary lookup: " & e.msg
  finally:
    if process != nil:
      process.close()

  return ("", false)

proc getBinaryVersion(pkgName: string): string =
  ## Tries to execute the local binary with '--version', '-v', or 'version'
  debug "getBinaryVersion"
  let binaryPath = os.getHomeDir() / ".local" / "bin" / pkgName

  const flags = ["--version", "-v", "version"]

  for flag in flags:
    let (cleanOutput, success) = checkBinaryFlag(binaryPath, flag)
    if not success: continue

    # Parse lines to find common version strings
    for line in cleanOutput.splitLines():
      let lowerLine = line.toLowerAscii()
      var pos = lowerLine.find("version:")
      var offset = "version:".len

      # Fallback to checking for "version=" if "version:" is missing
      if pos == -1:
        pos = lowerLine.find("version=")
        offset = "version=".len

      if pos != -1:
        # Slice from right after "version:" to the end of that specific line
        let startIdx = pos + offset
        var content = line[startIdx .. ^1].strip()

        # If the value is comma-separated (like lazygit's format), truncate at the comma
        let commaPos = content.find(',')
        if commaPos != -1:
          content = content[0 ..< commaPos].strip()
          
        if content.len > 0:
          return content

    # Generic fallback: return the first line if no "version" prefix was found
    let lines = cleanOutput.splitLines()
    if lines.len > 0 and lines[0].strip().len > 0:
      return lines[0].strip()

  # Fallback string if all flags fail or time out
  return ""

proc getInstalledVersion(pkgMan, pkgName: string, pkgType: PkgType): string =
  debug "getInstalledVersion"
  case pkgType
  of Deb, Rpm, Pacman:
    return normalizeVersion(getNativeVersion(pkgMan, pkgName))
    
  of AppImage, Binary:
    let localBinDir = os.getHomeDir() / ".local" / "bin"
    let binaryPath = localBinDir / pkgName

    if not fileExists(binaryPath):
      debug "file does not exist at: ", binaryPath
      return ""

    var parsedVer = ""
    if pkgType == AppImage:
      parsedVer = normalizeVersion(getAppImageVersion(pkgName))
    else:
      parsedVer = normalizeVersion(getBinaryVersion(pkgName))
      
    # If the file exists but failed to get version, return "none"
    if parsedVer.len == 0:
      return "none"
    else:
      return parsedVer

  else:
    debug "unsupported package type: ", pkgType
    return ""

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
  debug "getRepoName, ", target
  # Edge Cases
  if not target.contains('/'):
    return ""

  var clean = target.strip().strip(chars = {'/', '\\'})
  if clean.len == 0:
    return ""

  const prefixes = [
    "https://github.com", "http://github.com", "github.com",
    "git@github.com:", "://://github.com", "://github.com",
    "https://gitlab.com", "http://gitlab.com", "gitlab.com",
    "git@gitlab.com:", "://://gitlab.com", "://gitlab.com",
    "https://codeberg.org", "http://codeberg.org", "codeberg.org",
    "git@codeberg.org:", "://://codeberg.org", "://codeberg.org",
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
    let isStart =
      (asset[i] in Digits) or
      (asset[i] == 'v' and i + 1 < asset.len and asset[i+1] in Digits)
    let isBounded = i == 0 or asset[i-1] in {'-', '_', '.', ' '}

    if isStart and isBounded:
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
  ## Drops explicit internal platform and OS distribution noise
  result = name.toLowerAscii()
  const keywords = [
    "-linux", "_linux", "-x86", "_x86", "-arm", "_arm", "-riscv", "-anylinux", 
    "_fedora", "-fedora", "_ubu24", "-ubu24", "_ubuntu", "-ubuntu"
  ]
  for keyword in keywords:
    let idx = result.find(keyword)
    if idx > 0:
      result = result[0 ..< idx]

proc getPackageName*(asset: string): string =
  # Edge Case: Pure version strings
  if asset.len == 0: return "unknown"
  let isPureVer = asset[0] in Digits or (asset[0] == 'v' and asset.len > 1 and asset[1] in Digits)
  if isPureVer:
    var idx = if asset[0] == 'v': 1 else: 0
    while idx < asset.len and asset[idx] in (Digits + {'.'}): inc(idx)
    if idx == asset.len or asset[idx] in {'-', '+'}:
      return "unknown"

  # Global aliases up front
  if asset.startsWith("nvim"): return "neovim"

  # Determine raw name before versioning metadata markers
  var baseName = ""
  let verIdx = findVersionStart(asset)
  
  if verIdx > 0:
    let separator = asset[verIdx - 1]
    baseName = asset[0 ..< verIdx - 1]
    
    # If separated by an underscore (like deb/rpm assets), do not strip keywords on the left.
    if separator != '_':
      baseName = cleanKeywords(baseName)
  else:
    baseName = asset
    let dotPos = baseName.find('.')
    if dotPos != -1: baseName = baseName[0 ..< dotPos] # drop extensions like .AppImage
    baseName = cleanKeywords(baseName)

    # Completely unversioned fallback logic: Strip trailing metadata tags sequentially
    const trailingNoise = [
      "musl", "gnu", "static", "linux", "amd64", "arm64", "x86", "x86_64", "unknown"
    ]
    while true:
      let lastDash = baseName.rfind('-')
      let lastUnder = baseName.rfind('_')
      let lastSepIdx = max(lastDash, lastUnder)
      
      if lastSepIdx == -1: break
      
      let trailingPart = baseName.substr(lastSepIdx + 1).toLowerAscii()
      if trailingPart in trailingNoise or trailingPart.len == 0:
        baseName = baseName.substr(0, lastSepIdx - 1)
      else:
        break

  # Expand PascalCase / camelCase structural layouts into kebab-case (e.g., BambuStudio -> bambu-studio)
  var processedName = ""
  for i, ch in baseName:
    if i > 0 and ch in {'A'..'Z'}:
      let prev = baseName[i - 1]
      if prev in {'a'..'z'} or prev in Digits:
        processedName.add('-')
    processedName.add(ch.toLowerAscii())

  # Normalize internal underscores to standardized hyphens unless it's preserved metadata
  processedName = processedName.replace('_', '-')

  # Trim accidental leading or trailing hyphens introduced during extraction shifts
  processedName = processedName.strip(chars = {'-'})

  return if processedName.len > 0: processedName else: "unknown"

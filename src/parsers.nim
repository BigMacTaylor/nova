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

proc getInstalledOSVersion(pkgMan, pkgName: string): string =
  ## Returns the version string natively installed on the host machine.
  ## Returns "" if the package is missing or not installed.
  let nativeCmd = getNativeCommand(pkgMan, actStatus, pkgName)
  let (output, exitCode) = execCmdEx(nativeCmd)
  let cleanOut = output.strip()

  if exitCode == 0 and cleanOut.len > 0:
    let components = cleanOut.split('|')
    case pkgMan
    of "apt", "nala":
      # Your apt query format maps to: ${Status}|${Version}|${Installed-Size}
      if components.len >= 2 and "installed" in components[0].toLowerAscii():
        return components[1].strip()
    of "dnf":
      # Your dnf query format maps to: installed|%{VERSION}|%{SIZE}
      if components.len >= 2 and components[0].strip() == "installed":
        return components[1].strip()
    else:
      discard
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

proc getSourceType(target: string): SourceType =
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

proc getRepoName(target: string): string =
  var clean = target.strip()

  let prefixes = [
    "https://github.com", "http://github.com", "git@github.com:", "://github.com",
    "https://gitlab.com", "http://gitlab.com", "git@gitlab.com:", "://gitlab.com",
  ]

  for prefix in prefixes:
    if clean.toLowerAscii().startsWith(prefix):
      clean = clean.substr(prefix.len)
      break

  # Remove leading slashes if they linger
  clean = clean.strip(leading = true, trailing = false, chars = {'/'})

  # Clean up trailing ".git" securely using Nim's endswith/substr
  if clean.toLowerAscii().endsWith(".git"):
    clean.removeSuffix(".git")

  # Isolate the base 'owner/repo' component from deep paths
  let parts = clean.split('/')
  if parts.len >= 2:
    return parts[0] & "/" & parts[1]

  return clean

proc getPackageNameBak(assetName, pkgExtension, repoPath: string): string =
  # Remove the trailing extension (e.g., ".rpm" or ".deb")
  var baseName = assetName.substr(0, assetName.len - pkgExtension.len - 2)

  # Clean up architecture and environment suffixes
  const suffixesToRemove = [
    "-musl", "-gnu", "-static", "-linux", "-unknown",
    "-x86_64", "-x86", "-amd64", "-arm64", "-aarch64", 
    ".x86_64", ".amd64", ".aarch64", "all"
  ]
  
  var changed = true
  while changed:
    changed = false
    for suffix in suffixesToRemove:
      if baseName.toLowerAscii().endsWith(suffix):
        baseName = baseName.substr(0, baseName.len - suffix.len - 1)
        changed = true
        break

  # Strip version numbers, releases, and keywords moving backwards.
  while true:
    let lastDash = baseName.rfind('-')
    let lastUnder = baseName.rfind('_')
    let lastSepIdx = max(lastDash, lastUnder)
    
    if lastSepIdx == -1:
      break
    
    let trailingPart = baseName.substr(lastSepIdx + 1).toLowerAscii()
    
    # Identify if the segment is a version component
    var hasDigits = false
    for ch in trailingPart:
      if ch.isDigit:
        hasDigits = true
        break

    # Check if the text matches common pre-release tag prefixes
    var isPreReleaseTag = false
    const preReleasePrefixes = ["rc", "alpha", "beta", "preview", "patch", "stable"]
    for prefix in preReleasePrefixes:
      if trailingPart.startsWith(prefix):
        isPreReleaseTag = true
        break

    let isMetadataSegment =
      hasDigits or
      isPreReleaseTag or
      trailingPart.startsWith("v") or 
      trailingPart.len == 0 or
      trailingPart in ["musl", "gnu", "static", "linux", "amd64", "arm64", "x86", "x86_64", "unknown", "all"]

    if isMetadataSegment:
      baseName = baseName.substr(0, lastSepIdx - 1)
    else:
      break

  # Fallback gracefully to the GitHub repository name if parsing clears out the string completely
  return if baseName.len > 0: baseName else: repoPath.split('/')[1]

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
  for keyword in ["-linux", "_linux", "-x86", "_x86", "-arm", "_arm", "-riscv", "-anylinux", "-musl", "_musl"]:
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

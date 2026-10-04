# ========================================================================================
#
#                                   Nova
#                                 Parsers
#
# ========================================================================================

proc normalizeVersionBak(versionStr: string): string =
  let clean = versionStr.strip().toLowerAscii()

  let startIdx = clean.find('-')
  var base = if startIdx != -1: clean.substr(startIdx + 1) else: clean

  # Remove 'v' prefix if GitHub tags include it (e.g., v15.2.0)
  if base.startsWith("v"):
    base = base.substr(1)

  # Strip any trailing suffixes like -deb or +fc34
  let dashIdx = base.find('-')
  let plusIdx = base.find('+')
  
  if dashIdx != -1 and plusIdx != -1:
    return base.substr(0, min(dashIdx, plusIdx) - 1)
  elif dashIdx != -1:
    return base.substr(0, dashIdx - 1)
  elif plusIdx != -1:
    return base.substr(0, plusIdx - 1)
  else:
    return base

proc normalizeVersion(versionStr: string): string =
  var base = versionStr.strip()

  # 1. First, strip out known trailing distro markers by finding the first '+' or a '-' followed by a distro revision
  # We can split by '+' first to get rid of things like '+dfsg-1' cleanly
  if '+' in base:
    base = base.split('+')[0]

  # 2. Handle the package name vs version separation
  # If there are dashes, we want to find the first piece that looks like a version number
  if '-' in base:
    let parts = base.split('-')
    for part in parts:
      if part.len > 0 and (part[0].isDigit or part.startsWith("v") or part.startsWith("V")):
        base = part
        break # Grab the first part that looks like a version string

  # 3. Final normalization
  base = base.toLowerAscii()
  if base.startsWith("v"):
    base = base.substr(1)
    
  return base

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

proc getPackageName(assetName, pkgExtension, repoPath: string): string =
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

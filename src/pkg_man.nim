# ========================================================================================
#
#                                   Nova
#                              Package Manager
#
# ========================================================================================

proc hasCommand(cmd: string): bool =
  findExe(cmd).len > 0

proc getDistroId(): string =
  result = "unknown"
  let osReleasePath = "/etc/os-release"
  if fileExists(osReleasePath):
    for line in lines(osReleasePath):
      if line.startsWith("ID="):
        let parts = line.split('=', 1)
        if parts.len == 2:
          return parts[1].strip().strip(chars = {'"', '\''})

proc detectSystemPackageManager(): string =
  if hasCommand("nala"):
    return "nala"
  elif hasCommand("apt"):
    return "apt"
  elif hasCommand("dnf"):
    return "dnf"
  elif hasCommand("pacman"):
    return "pacman"
  elif hasCommand("zypper"):
    return "zypper"
  elif hasCommand("apk"):
    return "apk"
  elif hasCommand("emerge"):
    return "emerge"
  elif hasCommand("brew"):
    return "brew"
  else:
    return "unknown"

proc getPackageManager(): string =
  case getDistroId()
  of "ubuntu", "debian", "pop", "mint", "elementary", "kali", "raspbian", "neon",
      "zorin", "pureos", "parrot", "deepin", "mx", "antix", "devuan":
    if hasCommand("nala"):
      return "nala"
    else:
      return "apt"
  of "fedora", "rhel", "centos", "rocky", "almalinux":
    return "dnf"
  of "arch", "manjaro", "endeavouros", "garuda", "artix", "arcolinux", "cachyos":
    return "pacman"
  of "opensuse", "opensuse-leap", "opensuse-tumbleweed", "sles", "sled", "geckolinux":
    return "zypper"
  of "alpine", "postmarketos":
    return "apk"
  of "void":
    return "xbps"
  of "gentoo", "funtoo":
    return "emerge"
  else:
    return detectSystemPackageManager()

proc parseAction(arg: string): Action =
  case arg.toLowerAscii()
  of "search": actSearch
  of "install": actInstall
  of "reinstall": actReinstall
  of "remove", "rm": actRemove
  of "autoremove": actAutoremove
  of "refresh", "update": actRefresh
  of "upgrade": actUpgrade
  of "add-repo", "add": actAddRepo
  of "remove-repo": actRemoveRepo
  of "list-repos": actListRepos
  of "list-installed": actListInstalled
  of "list-updates": actListUpdates
  of "status", "stat": actStatus
  of "show", "info": actInfo
  of "history": actHistory
  else: actUnknown

# ========================================================================================
#
#                                   Nova
#                                 Commands
#
# ========================================================================================

proc getSudoPrefix(): string =
  var suPrefix = ""

  if isAdmin():
    suPrefix = ""
  elif findExe("doas").len > 0:
    suPrefix = "doas "
  elif findExe("sudo").len > 0:
    suPrefix = "sudo "
  else:
    raise newException(OSError, "No privilege elevation tool (sudo/doas) found.")

  return suPrefix

# Returns the specific command based on the package manager and action
proc getNativeCommand(pkgMan: string, action: Action, target: string = ""): string =
  let su = getSudoPrefix()

  case pkgMan
  of "apt":
    case action
    of actSearch:        "apt search " & target
    of actInstall:       su & "apt install -y " & target
    of actReinstall:     su & "apt install --reinstall -y " & target
    of actRemove:        su & "apt remove -y " & target
    of actAutoremove:    su & "apt autoremove -y"
    of actRefresh:       su & "apt update"
    of actUpgrade:       su & "apt upgrade -y"
    of actInfo:          "apt show " & target
    of actStatus:        "dpkg-query -W -f='${Status}|${Version}|${Installed-Size} KB\\n' " & target &   " 2>/dev/null"
    of actAddRepo:       su & "add-apt-repository -y " & target
    of actRemoveRepo:    su & "add-apt-repository --remove -y " & target
    of actListRepos:     "grep -E '^[^#]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null"
    of actListInstalled: "apt list --manual-installed 2>/dev/null | grep -v 'Listing...'"
    of actListUpdates:   "apt list --upgradable 2>/dev/null | grep -v 'Listing...'"
    of actHistory:       "cat /var/log/apt/history.log 2>/dev/null"
    else: ""

  of "nala":
    case action
    of actSearch:        "nala search " & target
    of actInstall:       su & "nala install -y " & target
    of actReinstall:     su & "nala install --reinstall -y " & target
    of actRemove:        su & "nala remove -y " & target
    of actAutoremove:    su & "nala autoremove -y"
    of actRefresh:       su & "nala update"
    of actUpgrade:       su & "nala upgrade -y"
    of actInfo:          "nala show " & target
    of actStatus:        "dpkg-query -W -f='${Status}|${Version}|${Installed-Size} KB\\n' " & target &   " 2>/dev/null"
    of actAddRepo:       su & "add-apt-repository -y " & target
    of actRemoveRepo:    su & "add-apt-repository --remove -y " & target
    of actListRepos:     "grep -E '^[^#]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null"
    of actListInstalled: "nala list --installed 2>/dev/null"
    of actListUpdates:   "nala list --upgradable 2>/dev/null"
    of actHistory:       "nala history 2>/dev/null"
    else: ""

  of "dnf":
    case action
    of actSearch:        "dnf search " & target
    of actInstall:       su & "dnf install -y " & target
    of actReinstall:     su & "dnf reinstall -y " & target
    of actRemove:        su & "dnf remove -y " & target
    of actAutoremove:    su & "dnf autoremove -y"
    of actRefresh:       su & "dnf makecache"
    of actUpgrade:       su & "dnf upgrade -y"
    of actInfo:          "dnf info " & target
    of actStatus:        "rpm -q --queryformat 'installed|%{VERSION}|%{SIZE}\\n' " & target & " 2>/dev/null"
    of actAddRepo:       su & "dnf config-manager addrepo --from-repofile=" & target
    of actRemoveRepo:    su & "dnf config-manager setopt " & target & ".enabled=0"
    of actListRepos:     "dnf repolist"
    of actListInstalled: "dnf repoquery --userinstalled 2>/dev/null | sort"
    of actListUpdates:   "dnf check-update"
    of actHistory:       "dnf history list"
    else: ""

  of "pacman":
    case action
    of actSearch:        "pacman -Ss " & target
    of actInstall:       su & "pacman -S --noconfirm " & target
    of actReinstall:     su & "pacman -S --noconfirm " & target
    of actRemove:        su & "pacman -R --noconfirm " & target
    of actAutoremove:    su & "bash -c 'orphans=$(pacman -Qdtq); [ -n \"$orphans\" ] && pacman -Rns --noconfirm $orphans || echo \"No orphans found.\"'"
    of actRefresh:       su & "pacman -Sy"
    of actUpgrade:       su & "pacman -Syu --noconfirm"
    of actInfo:          "pacman -Si " & target
    of actStatus:        "pacman -Qi " & target & " 2>/dev/null | egrep 'Name|Version|Installed Size' | awk -F: '{print $2}' | sed 's/^[ \\t]*//' | tr '\\n' '|'"
    of actAddRepo:       "echo 'Edit /etc/pacman.conf manually to append repositories.'"
    of actRemoveRepo:    "echo 'Edit /etc/pacman.conf manually to remove repositories.'"
    of actListRepos:     "grep -E '^\\[.' /etc/pacman.conf | grep -v 'options'"
    of actListInstalled: "pacman -Qetq"
    of actListUpdates:   "pacman -Qu"
    of actHistory:       "cat /var/log/pacman.log 2>/dev/null"
    else: ""

  of "zypper":
    case action
    of actSearch:        "zypper se " & target
    of actInstall:       su & "zypper --non-interactive in " & target
    of actReinstall:     su & "zypper --non-interactive in -f " & target
    of actRemove:        su & "zypper --non-interactive rm " & target
    of actAutoremove:    su & "zypper rm -u"
    of actRefresh:       su & "zypper ref"
    of actUpgrade:       su & "zypper up -y"
    of actInfo:          "zypper info " & target
    of actStatus:        "zypper info " & target & " 2>/dev/null | egrep 'Installed|Version|Installed Size' | awk -F: '{print $2}' | sed 's/^[ \\t]*//' | tr '\\n' '|'"
    of actAddRepo:       su & "zypper ar " & target
    of actRemoveRepo:    su & "zypper rr " & target
    of actListRepos:     "zypper lr"
    of actListInstalled: "zypper search --installed-only --user-installed 2>/dev/null | awk 'NR>4 {print $3}' | grep -v '^$'"
    of actListUpdates:   "zypper lu"
    of actHistory:       "cat /var/log/Zypper.log 2>/dev/null"
    else: ""

  of "apk":
    case action
    of actSearch:        "apk search " & target
    of actInstall:       su & "apk add " & target
    of actReinstall:     su & "apk add --force-refresh " & target
    of actRemove:        su & "apk del " & target
    of actAutoremove:    "echo 'Alpine manages dependencies automatically upon removal.'"
    of actRefresh:       su & "apk update"
    of actUpgrade:       su & "apk upgrade"
    of actInfo:          "apk info " & target
    of actStatus:        "apk info -s " & target & " 2>/dev/null | tr '\\n' '|'; apk info -v " & target & " 2>/dev/null"
    of actAddRepo:       su & "bash -c \"echo '" & target & "' >> /etc/apk/repositories\""
    of actRemoveRepo:    su & "bash -c \"sed -i '\\|" & target & "|d' /etc/apk/repositories\""
    of actListRepos:     "cat /etc/apk/repositories 2>/dev/null"
    of actListInstalled: "cat /etc/apk/world 2>/dev/null"
    of actListUpdates:   "apk version -l '<' 2>/dev/null"
    of actHistory:       "echo 'Alpine APK does not log standalone transition histories.'"
    else: ""

  of "xbps":
    case action
    of actSearch:        "xbps-query -Rs " & target
    of actInstall:       su & "xbps-install -Sy " & target
    of actReinstall:     su & "xbps-install -fy " & target
    of actRemove:        su & "xbps-remove -y " & target
    of actAutoremove:    su & "xbps-remove -Oy"
    of actRefresh:       su & "xbps-install -S"
    of actUpgrade:       su & "xbps-install -Su"
    of actInfo:          "xbps-query -Rs " & target
    of actStatus:        "xbps-query -W " & target & " 2>/dev/null"
    of actAddRepo:       su & "xbps-install -y " & target
    of actRemoveRepo:    su & "xbps-remove -y " & target
    of actListRepos:     "xbps-query -L"
    of actListInstalled: "xbps-query -m"
    of actListUpdates:   "xbps-install -Sun"
    of actHistory:       "tail -n 100 /var/log/xbps-install.log 2>/dev/null"
    else: ""

  of "emerge":
    case action
    of actSearch:        "emerge --search " & target
    of actInstall:       su & "emerge --ask=n --verbose " & target
    of actReinstall:     su & "emerge --ask=n --noreplace " & target
    of actRemove:        su & "emerge --ask=n --unmerge " & target
    of actAutoremove:    su & "emerge --ask=n --depclean"
    of actRefresh:       su & "emaint sync --repo gentoo"
    of actUpgrade:       su & "emerge --update --deep --with-bdeps=y @world"
    of actInfo:          "emerge --searchdesc " & target
    of actStatus:        "qlist -Iv " & target & " 2>/dev/null; qsize -m " & target & " 2>/dev/null"
    of actAddRepo:       su & "eselect repository enable " & target
    of actRemoveRepo:    su & "eselect repository disable " & target
    of actListRepos:     "eselect repository list"
    of actListInstalled: "cat /var/lib/portage/world 2>/dev/null"
    of actListUpdates:   "emerge --update --deep --with-bdeps=y --pretend @world"
    of actHistory:       "cat /var/log/emerge.log 2>/dev/null"
    else: ""

  of "brew":
    case action
    of actSearch:        "brew search " & target
    of actInstall:       "brew install " & target
    of actReinstall:     "brew reinstall " & target
    of actRemove:        "brew uninstall " & target
    of actAutoremove:    "brew autoremove"
    of actRefresh:       "brew update"
    of actUpgrade:       "brew upgrade"
    of actInfo:          "brew info " & target
    of actStatus:        "brew info --json=v2 " & target & " 2>/dev/null"
    of actAddRepo:       "brew tap " & target
    of actRemoveRepo:    "brew untap " & target
    of actListRepos:     "brew tap"
    of actListInstalled: "brew leaves"
    of actListUpdates:   "brew outdated"
    of actHistory:       "echo 'Homebrew does not feature structural transactional tracking history logs.'"
    else: ""

  else:
    errorMsg("Package manager '", pkgMan, "' is not currently supported.")
    quit(1)

proc runNativeCommand(pkgMan: string, action: Action, targetStr: string): int =
  # Get the native package manager command and execute it
  let nativeCmd = getNativeCommand(pkgMan, action, targetStr)
  
  if nativeCmd.len == 0:
    errorMsg(pkgMan, " does not support the requested action.")
    return 0

  debug "Executing: " & nativeCmd

  result = execCmd(nativeCmd)
  if result != 0:
    errorMsg("Native package manager exited with status code: ", $result)

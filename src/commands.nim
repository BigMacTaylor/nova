# ========================================================================================
#
#                                   Nova
#                                 Commands
#
# ========================================================================================

# Ensure commands requiring root privileges are run via sudo if needed
proc enforceSudo(cmd: string): string =
  if isAdmin():
    return cmd

  var su = ""
  if findExe("doas").len > 0:
    su = "doas "
  elif findExe("sudo").len > 0:
    su = "sudo "
  else:
    raise newException(OSError, "No privilege elevation tool (sudo/doas) found.")

  return su & cmd

# Returns the specific command based on the package manager and action
proc getNativeCommand(pkgMan: string, action: Action, target: string = ""): string =
  case pkgMan
  of "apt":
    case action
    of actSearch:        "apt search " & target
    of actInstall:       enforceSudo("apt install -y " & target)
    of actReinstall:     enforceSudo("apt install --reinstall -y " & target)
    of actRemove:        enforceSudo("apt remove -y " & target)
    of actAutoremove:    enforceSudo("apt autoremove -y")
    of actRefresh:       enforceSudo("apt update")
    of actUpgrade:       enforceSudo("apt upgrade -y")
    of actInfo:          "apt show " & target
    of actStatus:        "dpkg-query -W -f='${Status}|${Version}|${Installed-Size} KB\\n' " & target & " 2>/dev/null"
    of actAddRepo:       enforceSudo("add-apt-repository -y " & target)
    of actRemoveRepo:    enforceSudo("add-apt-repository --remove -y " & target)
    of actListRepos:     "grep -E '^[^#]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null"
    of actListInstalled: "apt list --manual-installed 2>/dev/null | grep -v 'Listing...'"
    of actListUpdates:   "apt list --upgradable 2>/dev/null | grep -v 'Listing...'"
    of actHistory:       "cat /var/log/apt/history.log 2>/dev/null"
    else: ""

  of "dnf":
    case action
    of actSearch:        "dnf search " & target
    of actInstall:       enforceSudo("dnf install -y " & target)
    of actReinstall:     enforceSudo("dnf reinstall -y " & target)
    of actRemove:        enforceSudo("dnf remove -y " & target)
    of actAutoremove:    enforceSudo("dnf autoremove -y")
    of actRefresh:       enforceSudo("dnf makecache")
    of actUpgrade:       enforceSudo("dnf upgrade -y")
    of actInfo:          "dnf info " & target
    of actStatus:        "rpm -q --queryformat 'installed|%{VERSION}|%{SIZE}\\n' " & target & " 2>/dev/null"
    of actAddRepo:       enforceSudo("dnf config-manager addrepo --from-repofile=" & target)
    of actRemoveRepo:    enforceSudo("dnf config-manager setopt " & target & ".enabled=0")
    of actListRepos:     "dnf repolist"
    of actListInstalled: "dnf repoquery --userinstalled 2>/dev/null | sort"
    of actListUpdates:   "dnf check-update"
    of actHistory:       "dnf history list"
    else: ""

  of "pacman":
    case action
    of actSearch:        "pacman -Ss " & target
    of actInstall:       enforceSudo("pacman -S --noconfirm " & target)
    of actReinstall:     enforceSudo("pacman -S --noconfirm " & target)
    of actRemove:        enforceSudo("pacman -R --noconfirm " & target)
    #of actAutoremove:    enforceSudo("bash -c \"orphans=\$(pacman -Qdtq); [ -n '\$orphans' ] && pacman -Rns --noconfirm \$orphans || echo 'No orphans found.'\"")
    #of actAutoremove: enforceSudo("pacman -Rns $(pacman -Qdtq)") # Removes orphaned dependencies
    #of actAutoremove: enforceSudo("bash -c 'orphans=$(pacman -Qdtq); [ -n \"$orphans\" ] && pacman -Rns --noconfirm $orphans || echo \"No orphans found.\" '")
    of actAutoremove: enforceSudo("""bash -c \"orphans=\$(pacman -Qdtq); [ -n '\$orphans' ] && pacman -Rns --noconfirm \$orphans || echo 'No orphans found.'\"""")
    of actRefresh:       enforceSudo("pacman -Sy")
    of actUpgrade:       enforceSudo("pacman -Syu --noconfirm")
    of actInfo:          "pacman -Si " & target
    of actStatus:        "pacman -Qi " & target & " 2>/dev/null | egrep 'Name|Version|Installed Size' | awk -F: '{print $2}' | sed 's/^[ \t]*//' | tr '\\n' '|'"
    of actAddRepo:       "echo 'Edit /etc/pacman.conf manually to append repositories.'"
    of actRemoveRepo:    "echo 'Edit /etc/pacman.conf manually to remove repositories.'"
    of actListRepos:     "grep -E '^\\[' /etc/pacman.conf | grep -v 'options'"
    of actListInstalled: "pacman -Qetq"
    of actListUpdates:   "pacman -Qu"
    of actHistory:       "cat /var/log/pacman.log 2>/dev/null"
    else: ""

  of "zypper":
    case action
    of actSearch:        "zypper se " & target
    of actInstall:       enforceSudo("zypper --non-interactive in " & target)
    of actReinstall:     enforceSudo("zypper --non-interactive in -f " & target)
    of actRemove:        enforceSudo("zypper --non-interactive rm " & target)
    of actAutoremove:    enforceSudo("zypper rm -u")
    of actRefresh:       enforceSudo("zypper ref")
    of actUpgrade:       enforceSudo("zypper up -y")
    of actInfo:          "zypper info " & target
    of actStatus:        "zypper info " & target & " 2>/dev/null | egrep 'Installed|Version|Installed Size' | awk -F: '{print $2}' | sed 's/^[ \t]*//' | tr '\\n' '|'"
    of actAddRepo:       enforceSudo("zypper ar " & target)
    of actRemoveRepo:    enforceSudo("zypper rr " & target)
    of actListRepos:     "zypper lr"
    of actListInstalled: "zypper search --installed-only --user-installed 2>/dev/null | awk 'NR>4 {print $3}' | grep -v '^$'"
    of actListUpdates:   "zypper lu"
    of actHistory:       "cat /var/log/Zypper.log 2>/dev/null"
    else: ""

  of "apk":
    case action
    of actSearch:        "apk search " & target
    of actInstall:       enforceSudo("apk add " & target)
    of actReinstall:     enforceSudo("apk add --force-refresh " & target)
    of actRemove:        enforceSudo("apk del " & target)
    of actAutoremove:    "echo 'Alpine manages dependencies automatically upon removal.'"
    of actRefresh:       enforceSudo("apk update")
    of actUpgrade:       enforceSudo("apk upgrade")
    of actInfo:          "apk info " & target
    of actStatus:        "apk info -s " & target & " 2>/dev/null | tr '\\n' '|'; apk info -v " & target & " 2>/dev/null"
    of actAddRepo:       enforceSudo("bash -c \"echo '" & target & "' >> /etc/apk/repositories\"")
    of actRemoveRepo:    enforceSudo("bash -c \"sed -i '\\|" & target & "|d' /etc/apk/repositories\"")
    of actListRepos:     "cat /etc/apk/repositories 2>/dev/null"
    of actListInstalled: "cat /etc/apk/world 2>/dev/null"
    of actListUpdates:   "apk version -l '<' 2>/dev/null"
    of actHistory:       "echo 'Alpine APK does not log standalone transition histories.'"
    else: ""

  of "emerge":
    case action
    of actSearch:        "emerge --search " & target
    of actInstall:       enforceSudo("emerge --ask=n --verbose " & target)
    of actReinstall:     enforceSudo("emerge --ask=n --noreplace " & target)
    of actRemove:        enforceSudo("emerge --ask=n --unmerge " & target)
    of actAutoremove:    enforceSudo("emerge --ask=n --depclean")
    of actRefresh:       enforceSudo("emaint sync --repo gentoo")
    of actUpgrade:       enforceSudo("emerge --update --deep --with-bdeps=y @world")
    of actInfo:          "emerge --searchdesc " & target
    of actStatus:        "qlist -Iv " & target & " 2>/dev/null; qsize -m " & target & " 2>/dev/null"
    of actAddRepo:       enforceSudo("eselect repository enable " & target)
    of actRemoveRepo:    enforceSudo("eselect repository disable " & target)
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
    errorMsg("Package manager '", pkgMan, "' does not support the requested action.")
    quit(1)

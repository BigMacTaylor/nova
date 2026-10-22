# ========================================================================================
#
#                                   Nova
#                                   Help
#
# ========================================================================================

template printHelp() =
  const msg = """Nova:
  A native package manager wrapper, with git support built in.

Usage:
  nova [options] <command> [args]...

Options:
  -h, --help      Show this help message
  -v, --version   Show version number and exit

Commands:
  search          Search for a package
  install         Install package <name> or repo <owner/repo>
  reinstall       Reinstall one or more packages
  remove          Remove one or more packages
  autoremove      Automatically clean up unused dependencies
  refresh         Refresh the package cache and repos
  upgrade         Upgrade all packages
  add-repo        Add a system or git repository <owner/repo> 
  remove-repo     Remove a repo from the repo manifest
  list            List all installed versions of a package
  list-repos      List tracked repositories
  list-installed  List installed packages
  list-updates    List available updates
  status          Show install status, version, and size of a package
  info            Display detailed information about a package
  history         Show installation history

Examples:
  nova add-repo burntsushi/ripgrep
  nova install ripgrep

Use 'nova --help-all' to see all flags and commands.
"""

  echo formatHelpString(msg)

template printDetailedHelp() =
  const msg = """Nova:
  A wrapper around native package managers, that
  installs packages directly from git repositories.

Usage:
  nova [options] <command> [args]...

Options:
  -h, --help            Show basic help message and exit
  --help-all            Show detailed help message and exit
  -v, --version         Show version number and exit

Options(testing):
  --prefer-musl         Prefer musl over glibc binaires
  --include-prerelease  Allow beta, rc, and nightly versions over stable
  --no-verify           Disable SSL/TLS verification

Package Management Commands:
  search                Search for a package
  install               Install package <name> or repo <owner/repo>
  reinstall             Reinstall one or more packages
  remove, rm            Remove one or more packages
  autoremove            Automatically clean up unused dependencies

System & Upgrade Commands:
  update, refresh       Refresh the package cache and repositories
  upgrade               Upgrade all packages

Repository Commands:
  add-repo, repo-add    Track a new system or git repository <owner/repo>
  add                   Alias for add-repo
  remove-repo           Remove a repository from the tracking list
  repo-remove           Alias for remove-repo

Info & Query Commands:
  list                  List all installed versions of a package
  list-repos            List tracked repositories
  list-installed        List installed packages
  list-updates          List available updates
  list-upgrades         Alias for list-updates
  status, stat          Show install status, version, and size of a package
  info, show            Display detailed information about a package
  history               Show package installation history

Examples:
  # Add a shorthand GitHub repository and install
  nova add-repo burntsushi/ripgrep
  nova install ripgrep

  # Add a full URL repository and install
  nova add-repo https://github.com/BigMacTaylor/griddle
  nova install griddle

  # Get information about installed packages
  nova list neovim
  nova stat btop
"""

  echo formatHelpString(msg)

# Nova
A distro-agnostic package manager wrapper designed for users who switch environments frequently. It abstracts away the syntax
differences of native package managers, providing a single, consistent syntax across different Linux distributions.

Additionally, it allows you to install and update packages directly from GitHub releases. You can install a package with
```bash
nova install BigMacTaylor/griddle
```
Running `nova refresh` and then `nova upgrade` will automatically search Github for new releases. And keep applications up to date just like your system's regular package manager.

### Installation

Download the binary from the [releases page](https://github.com/BigMacTaylor/nova/releases) Make it executable and place it somewhere in your system `$PATH`.

```bash
# Example: move the downloaded file to /usr/local/bin/ and make it executable
sudo mv ~/Downloads/nova /usr/local/bin/nova
sudo chmod +x /usr/local/bin/nova
```

### Usage

#### Managing Packages
```bash
# Search for a package
nova search ripgrep

# Install a package from the system repositories or a GitHub repo
nova install ripgrep
nova install burntsushi/ripgrep

# Reinstall or remove packages
nova reinstall ripgrep
nova remove ripgrep
nova autoremove
```

#### Updating & Upgrading
```bash
# Refresh the package cache and automatically search Github for new releases
nova refresh

# Upgrade all installed packages to their latest versions
nova upgrade
```

#### Managing Repositories
```bash
# Add a new system repo or GitHub repository
nova add-repo burntsushi/ripgrep

# Remove an existing repository
nova remove-repo burntsushi/ripgrep

# List all repositories currently being tracked
nova list-repos
```

### Command Reference

| Command | Description |
| :--- | :--- |
| `search` | Search for a package |
| `install` | Install package `<name>` or repo `<owner/repo>` |
| `reinstall` | Reinstall one or more packages |
| `remove` | Remove one or more packages |
| `autoremove` | Automatically clean up unused dependencies |
| `refresh` | Refresh the package cache and repos |
| `update` | Update (same as `refresh`) |
| `upgrade` | Upgrade all packages |
| `add-repo` | Add system or git repo `<owner/repo>` |
| `remove-repo` | Remove repo from repo list |
| `list-repos` | List all tracked repos |
| `list-installed` | List installed packages |
| `list-updates` | List available updates |
| `status` | Display install status, version, and size |
| `show` | Show detailed information about a package |
| `info` | Display information (same as `show`) |
| `history` | Show installation history |

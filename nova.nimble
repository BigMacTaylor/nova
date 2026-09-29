# Package

version       = "0.0.5"
author        = "BigMacTaylor"
description   = "A distro-agnostic package manager"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["nova"]


# Dependencies
requires "nim >= 2.0.0"


task install, "Custom install task":
  exec "nim c -d:release -d:danger -d:strip --opt:speed -o:bin/nova src/nova.nim"

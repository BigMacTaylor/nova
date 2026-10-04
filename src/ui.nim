# ========================================================================================
#
#                                   Nova
#                                    UI
#
# ========================================================================================

const
  ANSI_RESET = "\x1B[0m"
  ANSI_BOLD = "\x1B[1m"
  ANSI_CYAN = "\x1B[36m"
  ANSI_GREEN = "\x1B[32m"

template debug(args: varargs[untyped]) =
  when not defined(release) and not defined(danger):
    system.debugEcho("Debug: ", args)

template errorMsg(args: varargs[untyped]) =
  styledWriteLine(stderr, fgRed, "Error: ", resetStyle, args)

template warnMsg(args: varargs[untyped]) =
  styledWriteLine(stderr, fgYellow, styleBright, "Warning: ", resetStyle, args)

template infoMsg(args: varargs[untyped]) =
  styledWriteLine(stdout, fgCyan, "Info: ", resetStyle, args)

template successMsg(args: varargs[untyped]) =
  styledWriteLine(stdout, fgGreen, "Success: ", resetStyle, args)

proc getTermWidth(): int =
  let padding = 1
  var termWidth = terminalWidth() - padding
  if termWidth <= 0:
    termWidth = 80
  return termWidth

proc formatHelpString(text: string): string =
  const commands = [
    "search", "install", "reinstall", "remove", "autoremove", 
    "refresh", "update", "upgrade", "add-repo", "remove-repo", 
    "list-repos", "list-installed", "list-updates", "status", 
    "show", "info", "history"
  ]
  
  var resultLines: seq[string] = @[]
  
  for line in text.splitLines():
    let trimmed = line.strip()
    
    # 1. Skip completely empty lines or handle clean pass-throughs
    if line.len == 0 or trimmed.len == 0:
      resultLines.add(line)
      continue

    # 2. Format Section Titles (e.g., "Usage:", "Options:", "Commands:")
    if trimmed.endsWith(':'):
      resultLines.add(ANSI_BOLD & line & ANSI_RESET)
      
    # 3. Format Flags (Lines starting with '-')
    elif trimmed.startsWith('-'):
      let dashIdx = line.find('-')
      let leadingSpaces = if dashIdx != -1: line[0 ..< dashIdx] else: ""
      
      # Split by double space to isolate the flags from the description column
      let parts = trimmed.split("  ", maxsplit = 1)
      if parts.len == 2:
        let flagsOnly = parts[0]
        let description = parts[1]
        resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & flagsOnly & ANSI_RESET & "  " & description)
      else:
        resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & trimmed & ANSI_RESET)

    # 4. Handle Commands and Examples (Cleanly isolated inside 'else')
    else:
      let isExample = trimmed.startsWith("nova ")
      
      # If it's an example, we temporarily strip "nova " to extract the underlying command
      let lookupString = if isExample: trimmed[5..^1] else: trimmed
      
      var matchedCommand = ""
      for cmd in commands:
        if lookupString.startsWith(cmd & " ") or lookupString == cmd:
          matchedCommand = cmd
          break
          
      if matchedCommand != "":
        if isExample:
          # Reconstruct example line: [spaces] + [cyan]nova command[/cyan] + [white]args[/white]
          let baseIdx = line.find("nova ")
          let leadingSpaces = if baseIdx != -1: line[0 ..< baseIdx] else: ""
          let remainingArgs = lookupString[matchedCommand.len .. ^1]
          
          resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & "nova " & matchedCommand & ANSI_RESET & remainingArgs)
        else:
          # Reconstruct standard command row layout
          let cmdIdx = line.find(matchedCommand)
          let leadingSpaces = if cmdIdx != -1: line[0 ..< cmdIdx] else: ""
          let remainingText = line[cmdIdx + matchedCommand.len .. ^1]
          
          resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & matchedCommand & ANSI_RESET & remainingText)
          
      elif isExample:
        # Fallback for "nova" commands that don't match our specific actions list
        let baseIdx = line.find("nova ")
        let leadingSpaces = if baseIdx != -1: line[0 ..< baseIdx] else: ""
        resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & trimmed & ANSI_RESET)
      else:
        resultLines.add(line)
      
  return resultLines.join("\n")


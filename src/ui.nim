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

proc printTableHeaders(title, col1, col2, col3: string) =
  styledWriteLine(stdout, fgWhite, styleBright, title, resetStyle)
  echo "  " & col1.alignLeft(30) & col2.alignLeft(20) & col3
  echo "  " & "-".repeat(70)

proc formatHelpString(text: string): string =
  const commands = [
    "add-repo", "remove-repo", "repo-remove", "list-installed", "list-updates", "list-upgrades",
    "list-repos", "autoremove", "reinstall", "search", "install", "remove", "refresh", "upgrade",
    "history", "update", "status", "info", "show", "stat", "list", "add", "rm"
  ]
  
  var resultLines: seq[string] = @[]
  
  for line in text.splitLines():
    let trimmed = line.strip()

    # Skip completely empty lines
    if line.len == 0 or trimmed.len == 0:
      resultLines.add(line)
      continue

    # Skip comments (# ...)
    if trimmed.startsWith('#'):
      resultLines.add(line)
      continue

    # Format Section Titles (e.g., "Usage:", "Options:", "Commands:")
    if trimmed.endsWith(':'):
      resultLines.add(ANSI_BOLD & line & ANSI_RESET)
      continue

    # Format Flags (Lines starting with '-')
    if trimmed.startsWith('-'):
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
      continue

    # Handle Commands and Examples
    let isExample = trimmed.startsWith("nova ")

    # If it's an example, temporarily strip "nova " to extract the underlying command
    let lookupString = if isExample: trimmed[5..^1] else: trimmed
    
    var matchedCommand = ""
    for cmd in commands:
      # Matches exact standalone words or groupings like "remove, rm"
      if lookupString == cmd or 
         lookupString.startsWith(cmd & " ") or 
         lookupString.startsWith(cmd & ",") or
         lookupString.contains(", " & cmd):
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
        let parts = trimmed.split("  ", maxsplit = 1)
        let cmdIdx = line.find(parts[0])
        let leadingSpaces = if cmdIdx != -1: line[0 ..< cmdIdx] else: ""
        
        if parts.len == 2:
          resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & parts[0] & ANSI_RESET & "  " & parts[1])
        else:
          resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & trimmed & ANSI_RESET)
          
    elif isExample:
      # Fallback for "nova" commands that don't match actions list
      let baseIdx = line.find("nova ")
      let leadingSpaces = if baseIdx != -1: line[0 ..< baseIdx] else: ""
      resultLines.add(leadingSpaces & ANSI_BOLD & ANSI_CYAN & trimmed & ANSI_RESET)
    else:
      resultLines.add(line)
      
  return resultLines.join("\n")

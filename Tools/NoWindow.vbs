' T043 zero-window launcher.
' Usage:
'   wscript.exe Tools\NoWindow.vbs <logPath> <commandLine>
' Starts <commandLine> through cmd.exe with windowStyle=0 so no console is shown,
' redirects stdout/stderr to <logPath>, waits for exit, and returns the same exit code.
' Never launch godot_console.exe for automation; use the GUI exe with --headless.
Option Explicit
Dim sh, args, logPath, cmd, line, rc, fso, dbg, q
Set sh = CreateObject("WScript.Shell")
Set args = WScript.Arguments
q = Chr(34)
If args.Count < 2 Then
  WScript.Quit 2
End If
logPath = args(0)
cmd = ""
Dim i
For i = 1 To args.Count - 1
  If i > 1 Then cmd = cmd & " "
  cmd = cmd & args(i)
Next
line = sh.ExpandEnvironmentStrings("%ComSpec%") & " /d /s /c " & cmd & " > " & q & logPath & q & " 2>&1"
Set fso = CreateObject("Scripting.FileSystemObject")
Set dbg = fso.OpenTextFile(logPath & ".launcher", 8, True)
dbg.WriteLine "CMD=" & cmd
dbg.WriteLine "LINE=" & line
dbg.Close
rc = sh.Run(line, 0, True)
Set dbg = fso.OpenTextFile(logPath & ".launcher", 8, True)
dbg.WriteLine "RC=" & rc
dbg.Close
WScript.Quit rc

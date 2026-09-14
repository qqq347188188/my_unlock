Set oShell = CreateObject("WScript.Shell")
strCmd = Chr(34) & "C:\Program Files\nodejs\node.exe" & Chr(34) & " " & Chr(34) & "C:\Users\Administrator\Desktop\cam-recorder.js" & Chr(34)
oShell.Run strCmd, 0, False

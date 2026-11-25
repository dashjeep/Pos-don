Option Explicit
Dim sh, fso, wmi, localApp, roamingApp, tempDir, vaultDir
Dim procs, p, pName, pCmd, eaDetectado
Dim epicRoot, ubiBase, svc, discDir, item, subP, pastaSettings, arq
Dim opDir, steamDir, pasta, arqVault
Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
Set wmi = GetObject("winmgmts:\\.\root\cimv2")
localApp = sh.ExpandEnvironmentStrings(Chr(37) & "LOCALAPPDATA" & Chr(37))
roamingApp = sh.ExpandEnvironmentStrings(Chr(37) & "APPDATA" & Chr(37))
tempDir = sh.ExpandEnvironmentStrings(Chr(37) & "TEMP" & Chr(37))
vaultDir = sh.ExpandEnvironmentStrings(Chr(37) & "USERPROFILE" & Chr(37)) & "\Documents\Credenciais"
On Error Resume Next
eaDetectado = False
Set procs = wmi.ExecQuery("Select Name, ProcessId, CommandLine From Win32_Process")
For Each p In procs
  pName = LCase(p.Name & "")
  Select Case pName
    Case "steam.exe", "steamwebhelper.exe", "gameoverlayui.exe", "epicgameslauncher.exe", "epicwebhelper.exe", "upc.exe", "ubisoftconnect.exe", "uplaywebcore.exe", "ubisoftwebcore.exe", "ubisoftextension.exe", "uplaycrashreporter.exe", "discord.exe", "whatsapp.root.exe", "whatsapp.exe", "opera.exe", "opera_crashreporter.exe"
      p.Terminate
    Case "eadesktop.exe", "ealauncher.exe", "eacefsubprocess.exe", "eabackgroundservice.exe"
      eaDetectado = True : p.Terminate
    Case "msedgewebview2.exe"
      pCmd = LCase(p.CommandLine & "")
      If InStr(1, pCmd, "whatsappdesktop") > 0 Then p.Terminate
    Case "update.exe"
      pCmd = LCase(p.CommandLine & "")
      If InStr(1, pCmd, "discord") > 0 Then p.Terminate
  End Select
Next
steamDir = Replace(sh.RegRead("HKCU\Software\Valve\Steam\SteamPath"), "/", "\")
If steamDir = "" Or Not fso.FolderExists(steamDir) Then steamDir = "C:\Program Files (x86)\Steam"
If Not fso.FolderExists(steamDir) Then steamDir = "C:\Steam"
If fso.FolderExists(steamDir) Then
  If fso.FileExists(steamDir & "\config\loginusers.vdf") Then fso.DeleteFile steamDir & "\config\loginusers.vdf", True
  If fso.FileExists(steamDir & "\config\config.vdf") Then fso.DeleteFile steamDir & "\config\config.vdf", True
  If fso.FileExists(steamDir & "\steam_autologin.dat") Then fso.DeleteFile steamDir & "\steam_autologin.dat", True
  If fso.FolderExists(steamDir & "\_cofre_tmp") Then LimparPasta fso, steamDir & "\_cofre_tmp"
  Set pasta = fso.GetFolder(steamDir)
  For Each arq In pasta.Files : If LCase(Left(arq.Name, 4)) = "ssfn" Then fso.DeleteFile arq.Path, True : End If : Next
End If
sh.RegWrite "HKCU\Software\Valve\Steam\AutoLoginUser", "", "REG_SZ"
sh.RegWrite "HKCU\Software\Valve\Steam\RememberPassword", 0, "REG_DWORD"
sh.RegDelete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\EpicGamesLauncher"
epicRoot = localApp & "\EpicGamesLauncher"
If fso.FolderExists(epicRoot & "\Saved") Then LimparPasta fso, epicRoot & "\Saved"
If fso.FolderExists(epicRoot & "\_cofre_tmp") Then LimparPasta fso, epicRoot & "\_cofre_tmp"
If fso.FolderExists(localApp & "\Ubisoft Game Launcher") Then LimparPasta fso, localApp & "\Ubisoft Game Launcher"
If fso.FolderExists(localApp & "\_cofre_ubisoft_tmp") Then LimparPasta fso, localApp & "\_cofre_ubisoft_tmp"
For Each ubiBase In Array(roamingApp & "\Ubisoft Game Launcher", "C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher")
  If fso.FileExists(ubiBase & "\users.dat") Then fso.DeleteFile ubiBase & "\users.dat", True
  If fso.FileExists(ubiBase & "\settings.yml") Then fso.DeleteFile ubiBase & "\settings.yml", True
  If fso.FileExists(ubiBase & "\settings.yaml") Then fso.DeleteFile ubiBase & "\settings.yaml", True
  If fso.FolderExists(ubiBase & "\cache\ownership") Then LimparPasta fso, ubiBase & "\cache\ownership"
  If fso.FolderExists(ubiBase & "\cache\ul") Then LimparPasta fso, ubiBase & "\cache\ul"
Next
If fso.FolderExists(localApp & "\Electronic Arts\EA Desktop") Then eaDetectado = True : LimparPasta fso, localApp & "\Electronic Arts\EA Desktop"
If fso.FolderExists(roamingApp & "\Electronic Arts\EA Desktop") Then eaDetectado = True : LimparPasta fso, roamingApp & "\Electronic Arts\EA Desktop"
If fso.FolderExists(localApp & "\Electronic Arts\_cofre_ea_tmp") Then LimparPasta fso, localApp & "\Electronic Arts\_cofre_ea_tmp"
If eaDetectado Then
  For Each svc In wmi.ExecQuery("Select * From Win32_Service Where Name = 'EABackgroundService' And State = 'Running'") : svc.StopService : Next
  LimparCredenciaisEAInvisivel wmi
End If
sh.RegDelete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Discord"
discDir = roamingApp & "\discord"
If fso.FolderExists(roamingApp & "\_cofre_discord_tmp") Then LimparPasta fso, roamingApp & "\_cofre_discord_tmp"
If fso.FolderExists(discDir) Then
  For Each item In Array("Local Storage", "Network", "Session Storage", "IndexedDB", "SharedStorage") : If fso.FolderExists(discDir & "\" & item) Then LimparPasta fso, discDir & "\" & item : End If : Next
  For Each item In Array("Cookies", "Cookies-journal") : If fso.FileExists(discDir & "\" & item) Then fso.DeleteFile discDir & "\" & item, True : End If : Next
End If
If fso.FolderExists(localApp & "\Packages") Then
  For Each subP In fso.GetFolder(localApp & "\Packages").SubFolders
    If InStr(1, subP.Name, "WhatsAppDesktop", 1) > 0 Then
      If fso.FolderExists(subP.Path & "\_cofre_wa_tmp") Then LimparPasta fso, subP.Path & "\_cofre_wa_tmp"
      For Each item In Array("LocalState", "LocalCache", "RoamingState") : If fso.FolderExists(subP.Path & "\" & item) Then LimparPasta fso, subP.Path & "\" & item : End If : If Not fso.FolderExists(subP.Path & "\" & item) Then fso.CreateFolder subP.Path & "\" & item : End If : Next
      If fso.FolderExists(subP.Path & "\Settings") Then : Set pastaSettings = fso.GetFolder(subP.Path & "\Settings") : For Each arq In pastaSettings.Files : fso.DeleteFile arq.Path, True : Next : End If
    End If
  Next
End If
If fso.FolderExists(tempDir & "\_cofre_opera_tmp") Then LimparPasta fso, tempDir & "\_cofre_opera_tmp"
For Each opDir In Array(roamingApp & "\Opera Software\Opera Stable", roamingApp & "\Opera Software\Opera Stable\Default", roamingApp & "\Opera Software\Opera GX Stable", roamingApp & "\Opera Software\Opera GX Stable\Default")
  If fso.FolderExists(opDir) Then
    For Each item In Array("Network", "Sessions", "Local Storage", "Session Storage", "IndexedDB") : If fso.FolderExists(opDir & "\" & item) Then LimparPasta fso, opDir & "\" & item : End If : Next
    For Each item In Array("Cookies", "Cookies-journal", "Login Data", "Login Data-journal", "Login Data For Account", "Login Data For Account-journal", "Web Data", "Web Data-journal", "Account Web Data", "Account Web Data-journal", "History", "History-journal", "Media History", "Media History-journal", "Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts", "Shortcuts-journal", "Current Session", "Current Tabs", "Last Session", "Last Tabs") : If fso.FileExists(opDir & "\" & item) Then fso.DeleteFile opDir & "\" & item, True : End If : Next
  End If
Next
If fso.FolderExists(vaultDir) Then
  For Each arqVault In fso.GetFolder(vaultDir).Files : If LCase(Left(arqVault.Name, 6)) = "cofre_" And LCase(Right(arqVault.Name, 8)) = ".zip.tmp" Then fso.DeleteFile arqVault.Path, True : End If : Next
End If
On Error GoTo 0
Sub LimparPasta(objFso, caminho)
  Dim objP, objArq, objSub : On Error Resume Next
  If Not objFso.FolderExists(caminho) Then Exit Sub
  Set objP = objFso.GetFolder(caminho) : objP.Attributes = 0 : objFso.DeleteFolder caminho, True
  If objFso.FolderExists(caminho) Then
    For Each objArq In objP.Files : objArq.Attributes = 0 : objFso.DeleteFile objArq.Path, True : Next
    For Each objSub In objP.SubFolders : LimparPasta objFso, objSub.Path : Next
    objFso.DeleteFolder caminho, True
  End If : On Error GoTo 0
End Sub
Sub LimparCredenciaisEAInvisivel(objWmi)
  Dim objStartup, objConfig, objProc, intPid, strCmd : On Error Resume Next
  Set objStartup = objWmi.Get("Win32_ProcessStartup") : Set objConfig = objStartup.SpawnInstance_ : objConfig.ShowWindow = 0
  Set objProc = objWmi.Get("Win32_Process")
  strCmd = "cmd.exe /c for /f ""tokens=1,* delims=: "" " & Chr(37) & "a in ('cmdkey /list | findstr /i ""EA_ EADesktop Origin""') do cmdkey /delete:" & Chr(37) & "b"
  objProc.Create strCmd, Null, objConfig, intPid : On Error GoTo 0
End Sub

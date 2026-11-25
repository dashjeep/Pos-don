Option Explicit
Dim objShell, objFSO, objWMI, colProc, strVaultDir, strZipFile, strTmpZip, strLocalApp, strRoamingApp, strOperaExe, strOperaProfile, strStageDir, str7z, arrPastasAlvo, arrArquivosAlvo, strPass, strPassConfirm, strSafePass, intRet, i
Set objShell = CreateObject("WScript.Shell") : Set objFSO = CreateObject("Scripting.FileSystemObject") : Set objWMI = GetObject("winmgmts:\\.\root\cimv2")
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
strZipFile = strVaultDir & "\cofre_opera.zip" : strTmpZip = strZipFile & ".tmp"
strLocalApp = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") : strRoamingApp = objShell.ExpandEnvironmentStrings("%APPDATA%") : strStageDir = objShell.ExpandEnvironmentStrings("%TEMP%") & "\_cofre_opera_tmp"
arrPastasAlvo = Array("Network", "Sessions", "Local Storage", "Session Storage", "IndexedDB")
arrArquivosAlvo = Array("Cookies", "Cookies-journal", "Login Data", "Login Data-journal", "Login Data For Account", "Login Data For Account-journal", "Web Data", "Web Data-journal", "Account Web Data", "Account Web Data-journal", "History", "History-journal", "Media History", "Media History-journal", "Visited Links", "Top Sites", "Top Sites-journal", "Shortcuts", "Shortcuts-journal", "Current Session", "Current Tabs", "Last Session", "Last Tabs")
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Este sistema exige o 7-Zip (nao compativel com WinRAR).", vbCritical, "Erro: 7-Zip Ausente"
    WScript.Quit
End If
strOperaExe = DetectarExecutavelOpera(objShell, objFSO, strLocalApp) : If strOperaExe = "" Then MsgBox "Opera nao encontrado.", vbCritical, "Erro" : WScript.Quit
strOperaProfile = DetectarPerfilOpera(objFSO, strRoamingApp)
EncerrarProcesso objWMI, "opera.exe" : EncerrarProcesso objWMI, "opera_crashreporter.exe" : WScript.Sleep 300 : LimparPasta objFSO, strStageDir
If Not objFSO.FileExists(strZipFile) Then
    strPass = PedirSenhaOculta("Criar Cofre Opera", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:") : If strPass = "" Then WScript.Quit
    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente:") : If strPass <> strPassConfirm Then MsgBox "As senhas nao conferem.", vbCritical, "Erro" : WScript.Quit
    strSafePass = Replace(strPass, """", "\""")
    objFSO.CreateFolder(strStageDir) : ColetarDadosSeletivos objFSO, strOperaProfile, strStageDir, arrPastasAlvo, arrArquivosAlvo, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strStageDir & "\*"" -p""" & strSafePass & """ -y", 0, True)
    LimparPasta objFSO, strStageDir
    If intRet = 0 And objFSO.FileExists(strZipFile) Then LimparDadosSeletivos objFSO, strOperaProfile, arrPastasAlvo, arrArquivosAlvo : MsgBox "Cofre criado ('cofre_opera.zip')! Cookies, sessoes e historico removidos (marcadores e extensoes mantidos).", vbInformation, "Protecao Ativada"
    WScript.Quit
End If
strPass = PedirSenhaOculta("Cofre Opera", "Digite a senha para abrir o Opera:") : If strPass = "" Then WScript.Quit
strSafePass = Replace(strPass, """", "\""")
intRet = objShell.Run("""" & str7z & """ t """ & strZipFile & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then MsgBox "Senha incorreta!", vbCritical, "Acesso Negado" : WScript.Quit
If Not objFSO.FolderExists(strOperaProfile) Then objShell.Run "cmd.exe /c mkdir """ & strOperaProfile & """ 2>nul", 0, True
LimparDadosSeletivos objFSO, strOperaProfile, arrPastasAlvo, arrArquivosAlvo
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strOperaProfile & """ -p""" & strSafePass & """ -y", 0, True)
objShell.Run """" & strOperaExe & """", 1, False
For i = 1 To 120 : Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'opera.exe'") : If colProc.Count > 0 Then Exit For : End If : WScript.Sleep 150 : Next
Do : Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'opera.exe'") : If colProc.Count = 0 Then : WScript.Sleep 250 : Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'opera.exe'") : If colProc.Count = 0 Then Exit Do : End If : End If : WScript.Sleep 150 : Loop
WScript.Sleep 350 : EncerrarProcesso objWMI, "opera_crashreporter.exe" : LimparPasta objFSO, strStageDir : objFSO.CreateFolder(strStageDir)
For i = 1 To 15 : ColetarDadosSeletivos objFSO, strOperaProfile, strStageDir, arrPastasAlvo, arrArquivosAlvo, False : If Not ExistemDadosSeletivos(objFSO, strOperaProfile, arrPastasAlvo, arrArquivosAlvo) Then Exit For : End If : WScript.Sleep 100 : Next
If PastaTemConteudo(objFSO, strStageDir) Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -p""" & strSafePass & """ -y", 0, True)
    If intRet = 0 And objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strZipFile, True : objFSO.MoveFile strTmpZip, strZipFile
End If
LimparPasta objFSO, strStageDir : For i = 1 To 10 : LimparDadosSeletivos objFSO, strOperaProfile, arrPastasAlvo, arrArquivosAlvo : If Not ExistemDadosSeletivos(objFSO, strOperaProfile, arrPastasAlvo, arrArquivosAlvo) Then Exit For : End If : WScript.Sleep 150 : Next
MsgBox "Opera encerrado. Cofre atualizado e sessoes removidas (marcadores e extensoes mantidos).", vbInformation, "Limpeza Concluida"
Function DetectarExecutavelOpera(sh, fso, localApp)
    Dim c, regCmd, posExe, caminho : DetectarExecutavelOpera = ""
    For Each c In Array(localApp & "\Programs\Opera\opera.exe", localApp & "\Programs\Opera GX\opera.exe", "C:\Program Files\Opera\opera.exe", "C:\Program Files\Opera GX\opera.exe", "C:\Program Files (x86)\Opera\opera.exe", "C:\Program Files (x86)\Opera GX\opera.exe")
        If fso.FileExists(c) Then DetectarExecutavelOpera = c : Exit Function
    Next
    On Error Resume Next
    regCmd = sh.RegRead("HKCU\Software\Clients\StartMenuInternet\OperaStable\shell\open\command\")
    If regCmd = "" Then regCmd = sh.RegRead("HKCU\Software\Clients\StartMenuInternet\OperaGXStable\shell\open\command\")
    If regCmd <> "" Then
        regCmd = Replace(regCmd, """", "")
        posExe = InStr(1, regCmd, ".exe", 1)
        If posExe > 0 Then : caminho = Trim(Left(regCmd, posExe + 3)) : If fso.FileExists(caminho) Then DetectarExecutavelOpera = caminho : Exit Function : End If : End If
    End If : On Error GoTo 0
End Function
Function DetectarPerfilOpera(fso, roamingApp)
    Dim c
    For Each c In Array(roamingApp & "\Opera Software\Opera Stable\Default", roamingApp & "\Opera Software\Opera Stable", roamingApp & "\Opera Software\Opera GX Stable\Default", roamingApp & "\Opera Software\Opera GX Stable")
        If fso.FileExists(c & "\Preferences") Or fso.FileExists(c & "\Bookmarks") Then DetectarPerfilOpera = c : Exit Function
    Next
    DetectarPerfilOpera = roamingApp & "\Opera Software\Opera Stable"
End Function
Sub ColetarDadosSeletivos(fso, origem, destino, pastas, arquivos, apenasCopiar)
    Dim item : On Error Resume Next
    For Each item In pastas
        If fso.FolderExists(origem & "\" & item) Then
            If apenasCopiar Then fso.CopyFolder origem & "\" & item, destino & "\" & item, True Else fso.MoveFolder origem & "\" & item, destino & "\" & item
        End If
    Next
    For Each item In arquivos
        If fso.FileExists(origem & "\" & item) Then
            If apenasCopiar Then fso.CopyFile origem & "\" & item, destino & "\" & item, True Else fso.MoveFile origem & "\" & item, destino & "\" & item
        End If
    Next
    On Error GoTo 0
End Sub
Sub LimparDadosSeletivos(fso, perfil, pastas, arquivos)
    Dim item : On Error Resume Next
    For Each item In pastas : If fso.FolderExists(perfil & "\" & item) Then fso.DeleteFolder perfil & "\" & item, True : End If : Next
    For Each item In arquivos : If fso.FileExists(perfil & "\" & item) Then fso.DeleteFile perfil & "\" & item, True : End If : Next
    On Error GoTo 0
End Sub
Function ExistemDadosSeletivos(fso, perfil, pastas, arquivos)
    Dim item : ExistemDadosSeletivos = False
    For Each item In pastas : If fso.FolderExists(perfil & "\" & item) Then ExistemDadosSeletivos = True : Exit Function : End If : Next
    For Each item In arquivos : If fso.FileExists(perfil & "\" & item) Then ExistemDadosSeletivos = True : Exit Function : End If : Next
End Function
Sub EncerrarProcesso(wmi, nomeProc)
    Dim procs, p : On Error Resume Next
    Set procs = wmi.ExecQuery("Select * From Win32_Process Where Name = '" & nomeProc & "'")
    For Each p In procs : p.Terminate : Next : On Error GoTo 0
End Sub
Sub LimparPasta(fso, caminho)
    On Error Resume Next : If fso.FolderExists(caminho) Then fso.DeleteFolder caminho, True : End If : On Error GoTo 0
End Sub
Function PastaTemConteudo(fso, caminho)
    Dim pasta : PastaTemConteudo = False : On Error Resume Next
    If fso.FolderExists(caminho) Then
        Set pasta = fso.GetFolder(caminho)
        If pasta.Files.Count > 0 Or pasta.SubFolders.Count > 0 Then PastaTemConteudo = True
    End If : On Error GoTo 0
End Function
Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_opera_auth.hta"
    Set objFile = objFSO.CreateTextFile(strTempHta, True)
    objFile.WriteLine "<html><head><title>" & titulo & "</title>"
    objFile.WriteLine "<hta:application border=""dialog"" caption=""yes"" maximizebutton=""no"" minimizebutton=""no"" scroll=""no"" showintaskbar=""yes"" singleinstance=""yes"" sysmenu=""yes"" />"
    objFile.WriteLine "<style>body{font-family:Segoe UI,sans-serif;font-size:13px;background:#f3f3f3;color:#111;margin:16px}"
    objFile.WriteLine "p{margin:0 0 10px 0}input{width:326px;padding:5px 7px;font-size:14px;border:1px solid #999}"
    objFile.WriteLine ".btns{margin-top:14px;text-align:right;width:326px}button{padding:4px 16px;font-size:13px;margin-left:6px;cursor:pointer}</style>"
    objFile.WriteLine "<script>function iniciar(){window.resizeTo(375,175);window.moveTo((screen.availWidth-375)/2,(screen.availHeight-175)/2);document.getElementById('senha').focus();}"
    objFile.WriteLine "function enviar(){var v=document.getElementById('senha').value;if(v!==''){new ActiveXObject('Scripting.FileSystemObject').GetStandardStream(1).Write(v);}window.close();}"
    objFile.WriteLine "function tecla(){if(window.event.keyCode===13)enviar();if(window.event.keyCode===27)window.close();}</script></head>"
    objFile.WriteLine "<body onload=""iniciar()""><p>" & mensagem & "</p><input type=""password"" id=""senha"" onkeydown=""tecla()"" />"
    objFile.WriteLine "<div class=""btns""><button onclick=""enviar()"">OK</button><button onclick=""window.close()"">Cancelar</button></div></body></html>"
    objFile.Close
    Set execObj = objShell.Exec("mshta.exe """ & strTempHta & """")
    saida = execObj.StdOut.ReadAll
    On Error Resume Next
    If objFSO.FileExists(strTempHta) Then objFSO.DeleteFile strTempHta, True
    On Error GoTo 0
    PedirSenhaOculta = saida
End Function
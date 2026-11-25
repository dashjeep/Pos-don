Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strLocalApp, strRoamingApp
Dim strEALocal, strEARoaming, strStageDir, str7z, strEAExe
Dim strPass, strPassConfirm, strSafePass, intRet, i

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

' Pasta do cofre
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_ea.zip"
strTmpZip = strZipFile & ".tmp"

strLocalApp = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
strRoamingApp = objShell.ExpandEnvironmentStrings("%APPDATA%")

strEALocal = strLocalApp & "\Electronic Arts\EA Desktop"
strEARoaming = strRoamingApp & "\Electronic Arts\EA Desktop"
strStageDir = strLocalApp & "\Electronic Arts\_cofre_ea_tmp"

' Detecta automaticamente o 7-Zip
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Instale o 7-Zip antes de executar.", vbCritical, "Erro"
    WScript.Quit
End If

' Detecta automaticamente o EA App (EADesktop.exe)
strEAExe = ""
On Error Resume Next
strEAExe = objShell.RegRead("HKLM\SOFTWARE\Electronic Arts\EA Desktop\DesktopAppPath")
On Error GoTo 0

If strEAExe = "" Or Not objFSO.FileExists(strEAExe) Then
    If objFSO.FileExists("C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe") Then
        strEAExe = "C:\Program Files\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
    ElseIf objFSO.FileExists("C:\Program Files (x86)\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe") Then
        strEAExe = "C:\Program Files (x86)\Electronic Arts\EA Desktop\EA Desktop\EADesktop.exe"
    Else
        MsgBox "EADesktop.exe (EA App) nao encontrado na pasta padrao.", vbCritical, "Erro"
        WScript.Quit
    End If
End If

' Encerra processos e servico em segundo plano do EA App
PararTudoEA objShell, objWMI
LimparPasta objFSO, strStageDir

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_ea.zip e limpa o PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not PastaTemConteudo(objFSO, strEALocal) And Not PastaTemConteudo(objFSO, strEARoaming) Then
        MsgBox "Nenhuma sessao salva encontrada no EA App." & vbCrLf & "Abra o EA App, faca login marcando 'Manter conectada', feche-o completamente perto do relogio e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre EA App", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")

    GarantirPasta objFSO, strStageDir
    On Error Resume Next
    If PastaTemConteudo(objFSO, strEALocal) Then
        objFSO.CopyFolder strEALocal, strStageDir & "\Local", True
    End If
    If PastaTemConteudo(objFSO, strEARoaming) Then
        objFSO.CopyFolder strEARoaming, strStageDir & "\Roaming", True
    End If
    On Error GoTo 0

    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strStageDir & "\*"" -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!Logs -xr!Crashpad -xr!Crashes -p""" & strSafePass & """ -y", 0, True)

    LimparPasta objFSO, strStageDir

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparPasta objFSO, strEALocal
        LimparPasta objFSO, strEARoaming
        LimparCredenciaisWindows objShell
        MsgBox "Cofre criado em Credenciais ('cofre_ea.zip') e credenciais apagadas do PC!", vbInformation, "Protecao Ativada"
    Else
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' =========================================================================
' MODO 2: USO NORMAL (Restaura -> Abre EA App -> Bloqueio Instantaneo)
' =========================================================================
strPass = PedirSenhaOculta("Cofre EA App", "Digite a senha para abrir o EA App:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

LimparPasta objFSO, strEALocal
LimparPasta objFSO, strEARoaming
GarantirPasta objFSO, strStageDir

' Extrai a sessao criptografada
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strStageDir & """ -p""" & strSafePass & """ -y", 0, True)

If intRet <> 0 Then
    LimparPasta objFSO, strStageDir
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

GarantirPasta objFSO, strLocalApp & "\Electronic Arts"
GarantirPasta objFSO, strRoamingApp & "\Electronic Arts"

On Error Resume Next
If objFSO.FolderExists(strStageDir & "\Local") Or objFSO.FolderExists(strStageDir & "\Roaming") Then
    If objFSO.FolderExists(strStageDir & "\Local") Then
        objFSO.MoveFolder strStageDir & "\Local", strEALocal
    End If
    If objFSO.FolderExists(strStageDir & "\Roaming") Then
        objFSO.MoveFolder strStageDir & "\Roaming", strEARoaming
    End If
Else
    ' Compatibilidade automatica com cofre_ea.zip criado na versao anterior
    objFSO.MoveFolder strStageDir, strEALocal
End If
On Error GoTo 0
LimparPasta objFSO, strStageDir

' Inicia o EA App
objShell.Run """" & strEAExe & """", 1, False

' Aguarda ate 10 segundos para o processo EADesktop.exe iniciar
For i = 1 To 65
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'EADesktop.exe'")
    If colProc.Count > 0 Then Exit For
    WScript.Sleep 150
Next

' Monitora a cada 150ms e age no exato instante (0ms de atraso) em que fechar
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'EADesktop.exe'")
    If colProc.Count = 0 Then Exit Do
    WScript.Sleep 150
Loop

' 1. BLOQUEIO IMEDIATO: Derruba o servico de fundo e arranca todos os arquivos na hora
PararTudoEA objShell, objWMI
LimparCredenciaisWindows objShell

GarantirPasta objFSO, strStageDir
GarantirPasta objFSO, strStageDir & "\Local"
GarantirPasta objFSO, strStageDir & "\Roaming"

For i = 1 To 12
    MoverConteudoRecursivo objFSO, strEALocal, strStageDir & "\Local"
    MoverConteudoRecursivo objFSO, strEARoaming, strStageDir & "\Roaming"
    LimparPasta objFSO, strEALocal
    LimparPasta objFSO, strEARoaming
    If Not PastaTemConteudo(objFSO, strEALocal) And Not PastaTemConteudo(objFSO, strEARoaming) Then Exit For
    PararTudoEA objShell, objWMI
    WScript.Sleep 100
Next

' 2. REEMPACOTAMENTO EM SEGUNDO PLANO (pastas originais ja estao vazias)
If PastaTemConteudo(objFSO, strStageDir & "\Local") Or PastaTemConteudo(objFSO, strStageDir & "\Roaming") Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!Logs -xr!Crashpad -xr!Crashes -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        objFSO.DeleteFile strZipFile, True
        objFSO.MoveFile strTmpZip, strZipFile
    End If
End If

LimparPasta objFSO, strStageDir
LimparPasta objFSO, strEALocal
LimparPasta objFSO, strEARoaming

If PastaTemConteudo(objFSO, strEALocal) Or PastaTemConteudo(objFSO, strEARoaming) Then
    MsgBox "Aviso: Alguns arquivos do EA App ainda estavam em uso. Execute o comando de liberacao do servico no CMD como Administrador.", vbExclamation, "Aviso de Limpeza"
Else
    MsgBox "EA App encerrado. Cofre atualizado e credenciais bloqueadas.", vbInformation, "Limpeza Concluida"
End If

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Sub PararTudoEA(sh, wmi)
    On Error Resume Next
    sh.Run "schtasks /Run /TN ""PararEAService""", 0, True
    EncerrarProcesso wmi, "EADesktop.exe"
    EncerrarProcesso wmi, "EALauncher.exe"
    EncerrarProcesso wmi, "EACefSubProcess.exe"
    EncerrarProcesso wmi, "EABackgroundService.exe"
    On Error GoTo 0
End Sub

Sub EncerrarProcesso(wmi, nomeProc)
    Dim procs, p
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select * From Win32_Process Where Name = '" & nomeProc & "'")
    For Each p In procs
        p.Terminate
    Next
    On Error GoTo 0
End Sub

Sub GarantirPasta(fso, caminho)
    On Error Resume Next
    If Not fso.FolderExists(caminho) Then
        fso.CreateFolder caminho
    End If
    On Error GoTo 0
End Sub

Sub LimparPasta(fso, caminho)
    On Error Resume Next
    If fso.FolderExists(caminho) Then
        fso.DeleteFolder caminho, True
    End If
    On Error GoTo 0
End Sub

Sub MoverConteudoRecursivo(fso, origem, destino)
    Dim pastaOrig, arq, subPasta
    On Error Resume Next
    If Not fso.FolderExists(origem) Then Exit Sub
    GarantirPasta fso, destino
    Set pastaOrig = fso.GetFolder(origem)
    For Each arq In pastaOrig.Files
        fso.MoveFile arq.Path, destino & "\" & arq.Name
    Next
    For Each subPasta In pastaOrig.SubFolders
        MoverConteudoRecursivo fso, subPasta.Path, destino & "\" & subPasta.Name
        fso.DeleteFolder subPasta.Path, True
    Next
    fso.DeleteFolder origem, True
    On Error GoTo 0
End Sub

Function PastaTemConteudo(fso, caminho)
    Dim pasta
    PastaTemConteudo = False
    On Error Resume Next
    If fso.FolderExists(caminho) Then
        Set pasta = fso.GetFolder(caminho)
        If pasta.Files.Count > 0 Or pasta.SubFolders.Count > 0 Then
            PastaTemConteudo = True
        End If
    End If
    On Error GoTo 0
End Function

Sub LimparCredenciaisWindows(sh)
    On Error Resume Next
    sh.Run "cmd.exe /c for /f ""tokens=1,* delims=: "" %a in ('cmdkey /list ^| findstr /i ""EA_ EADesktop Origin""') do cmdkey /delete:%b", 0, True
    On Error GoTo 0
End Sub

Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_ea_auth.hta"

    Set objFile = objFSO.CreateTextFile(strTempHta, True)
    objFile.WriteLine "<html><head><title>" & titulo & "</title>"
    objFile.WriteLine "<hta:application border=""dialog"" caption=""yes"" maximizebutton=""no"" minimizebutton=""no"" scroll=""no"" showintaskbar=""yes"" singleinstance=""yes"" sysmenu=""yes"" />"
    objFile.WriteLine "<style>"
    objFile.WriteLine "body { font-family: Segoe UI, Tahoma, sans-serif; font-size: 13px; background: #f3f3f3; color: #111; margin: 16px; }"
    objFile.WriteLine "p { margin: 0 0 10px 0; }"
    objFile.WriteLine "input { width: 326px; padding: 5px 7px; font-size: 14px; border: 1px solid #999; }"
    objFile.WriteLine ".btns { margin-top: 14px; text-align: right; width: 326px; }"
    objFile.WriteLine "button { padding: 4px 16px; font-size: 13px; margin-left: 6px; cursor: pointer; }"
    objFile.WriteLine "</style>"
    objFile.WriteLine "<script>"
    objFile.WriteLine "function iniciar() {"
    objFile.WriteLine "  window.resizeTo(375, 175);"
    objFile.WriteLine "  window.moveTo((screen.availWidth - 375) / 2, (screen.availHeight - 175) / 2);"
    objFile.WriteLine "  document.getElementById('senha').focus();"
    objFile.WriteLine "}"
    objFile.WriteLine "function enviar() {"
    objFile.WriteLine "  var v = document.getElementById('senha').value;"
    objFile.WriteLine "  if (v !== '') {"
    objFile.WriteLine "    new ActiveXObject('Scripting.FileSystemObject').GetStandardStream(1).Write(v);"
    objFile.WriteLine "  }"
    objFile.WriteLine "  window.close();"
    objFile.WriteLine "}"
    objFile.WriteLine "function tecla() {"
    objFile.WriteLine "  if (window.event.keyCode === 13) enviar();"
    objFile.WriteLine "  if (window.event.keyCode === 27) window.close();"
    objFile.WriteLine "}"
    objFile.WriteLine "</script></head>"
    objFile.WriteLine "<body onload=""iniciar()"">"
    objFile.WriteLine "<p>" & mensagem & "</p>"
    objFile.WriteLine "<input type=""password"" id=""senha"" onkeydown=""tecla()"" />"
    objFile.WriteLine "<div class=""btns"">"
    objFile.WriteLine "<button onclick=""enviar()"">OK</button>"
    objFile.WriteLine "<button onclick=""window.close()"">Cancelar</button>"
    objFile.WriteLine "</div></body></html>"
    objFile.Close

    Set execObj = objShell.Exec("mshta.exe """ & strTempHta & """")
    saida = execObj.StdOut.ReadAll

    On Error Resume Next
    If objFSO.FileExists(strTempHta) Then objFSO.DeleteFile strTempHta, True
    On Error GoTo 0

    PedirSenhaOculta = saida
End Function
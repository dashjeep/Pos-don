Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strEpicRoot, strEpicData, strStageDir, str7z, strEpicExe
Dim strPass, strPassConfirm, strSafePass, intRet, i

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

' Pasta fixa do cofre
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_epic.zip"
strTmpZip = strZipFile & ".tmp"
strEpicRoot = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\EpicGamesLauncher"
strEpicData = strEpicRoot & "\Saved"
strStageDir = strEpicRoot & "\_cofre_tmp"

' Detecta automaticamente o 7-Zip
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Instale o 7-Zip antes de executar.", vbCritical, "Erro"
    WScript.Quit
End If

' Detecta automaticamente o Epic Games Launcher
If objFSO.FileExists("C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe") Then
    strEpicExe = "C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win32\EpicGamesLauncher.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe") Then
    strEpicExe = "C:\Program Files (x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
ElseIf objFSO.FileExists("C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe") Then
    strEpicExe = "C:\Program Files\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
Else
    MsgBox "EpicGamesLauncher.exe nao encontrado na pasta padrao.", vbCritical, "Erro"
    WScript.Quit
End If

' Encerra processos residuais da Epic instantaneamente via WMI
EncerrarProcesso objWMI, "EpicGamesLauncher.exe"
EncerrarProcesso objWMI, "EpicWebHelper.exe"
LimparPasta objFSO, strStageDir

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_epic.zip e limpa o PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not objFSO.FolderExists(strEpicData & "\Config") Then
        MsgBox "Nenhuma sessao salva encontrada." & vbCrLf & "Abra a Epic Games, faca login marcando 'Lembrar de mim', feche a Epic e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre Epic", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strEpicData & "\*"" -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!Logs -xr!Crashes -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparPasta objFSO, strEpicData
        MsgBox "Cofre criado em Credenciais ('cofre_epic.zip') e pasta 'Saved' apagada do PC!", vbInformation, "Protecao Ativada"
    Else
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' =========================================================================
' MODO 2: USO NORMAL (Restaura -> Abre Epic -> Isolamento Instantaneo -> Repack)
' =========================================================================
strPass = PedirSenhaOculta("Cofre Epic Games", "Digite a senha para abrir a Epic Games:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

LimparPasta objFSO, strEpicData
If Not objFSO.FolderExists(strEpicRoot) Then objFSO.CreateFolder(strEpicRoot)
objFSO.CreateFolder(strEpicData)

' Extrai toda a pasta Saved criptografada
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strEpicData & """ -p""" & strSafePass & """ -y", 0, True)

If intRet <> 0 Then
    LimparPasta objFSO, strEpicData
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

' Inicia o Epic Games Launcher
objShell.Run """" & strEpicExe & """", 1, False
WScript.Sleep 3000

' Monitora o processo a cada 250ms para agir no instante em que fechar
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'EpicGamesLauncher.exe'")
    If colProc.Count = 0 Then Exit Do
    WScript.Sleep 250
Loop

' 1. BLOQUEIO IMEDIATO: Mata auxiliar e tira a pasta Saved do caminho em milissegundos
EncerrarProcesso objWMI, "EpicWebHelper.exe"

For i = 1 To 15
    On Error Resume Next
    If objFSO.FolderExists(strEpicData) Then
        objFSO.MoveFolder strEpicData, strStageDir
    End If
    On Error GoTo 0
    If Not objFSO.FolderExists(strEpicData) Then Exit For
    WScript.Sleep 150
Next

' 2. REEMPACOTAMENTO EM SEGUNDO PLANO (com a pasta original ja limpa)
If objFSO.FolderExists(strStageDir) Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!Logs -xr!Crashes -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        objFSO.DeleteFile strZipFile, True
        objFSO.MoveFile strTmpZip, strZipFile
    End If
    LimparPasta objFSO, strStageDir
ElseIf objFSO.FolderExists(strEpicData) Then
    LimparPasta objFSO, strEpicData
End If

If objFSO.FolderExists(strEpicData) Then
    MsgBox "Aviso: A pasta 'Saved' nao pode ser totalmente apagada porque esta aberta em alguma janela do Explorador de Arquivos.", vbExclamation, "Aviso de Limpeza"
Else
    MsgBox "Epic Games encerrada. Cofre atualizado e credenciais removidas.", vbInformation, "Limpeza Concluida"
End If

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Sub EncerrarProcesso(wmi, nomeProc)
    Dim procs, p
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select * From Win32_Process Where Name = '" & nomeProc & "'")
    For Each p In procs
        p.Terminate
    Next
    On Error GoTo 0
End Sub

Sub LimparPasta(fso, caminho)
    On Error Resume Next
    If fso.FolderExists(caminho) Then
        fso.DeleteFolder caminho, True
    End If
    On Error GoTo 0
End Sub

Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_epic_auth.hta"

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
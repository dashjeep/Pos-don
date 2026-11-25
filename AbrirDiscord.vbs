Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strLocalApp, strRoamingApp
Dim strDiscordExe, strDiscordData, strStageDir, str7z
Dim arrPastasAlvo, arrArquivosAlvo
Dim strPass, strPassConfirm, strSafePass, intRet, i

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

' Pasta padronizada do cofre
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_discord.zip"
strTmpZip = strZipFile & ".tmp"

strLocalApp = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
strRoamingApp = objShell.ExpandEnvironmentStrings("%APPDATA%")

strDiscordExe = strLocalApp & "\Discord\Update.exe"
strDiscordData = strRoamingApp & "\discord"
strStageDir = strRoamingApp & "\_cofre_discord_tmp"

' Local Storage e Network vao primeiro para invalidar o login em < 1ms
arrPastasAlvo = Array("Local Storage", "Network", "Session Storage", "IndexedDB", "SharedStorage")
arrArquivosAlvo = Array("Cookies", "Cookies-journal")

' Detecta automaticamente o 7-Zip
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Este sistema exige o 7-Zip (nao compativel com WinRAR).", vbCritical, "Erro: 7-Zip Ausente"
    WScript.Quit
End If

If Not objFSO.FileExists(strDiscordExe) Then
    MsgBox "Discord nao encontrado em AppData\Local\Discord.", vbCritical, "Erro"
    WScript.Quit
End If

' Encerra processos residuais do Discord antes de iniciar
If DiscordAtivo(objWMI) Then
    EncerrarTudoDiscord objWMI
    WScript.Sleep 200
End If
LimparPasta objFSO, strStageDir

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_discord.zip e limpa tokens do PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not objFSO.FolderExists(strDiscordData & "\Local Storage\leveldb") Then
        MsgBox "Nenhuma sessao salva encontrada no Discord." & vbCrLf & "Abra o Discord normalmente, faca login, clique em 'Sair do Discord' perto do relogio e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre Discord", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")

    objFSO.CreateFolder(strStageDir)
    ColetarTokens objFSO, strDiscordData, strStageDir, arrPastasAlvo, arrArquivosAlvo, True

    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strStageDir & "\*"" -p""" & strSafePass & """ -y", 0, True)
    LimparPasta objFSO, strStageDir

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparTokens objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo
        On Error Resume Next
        objShell.RegDelete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Discord"
        On Error GoTo 0
        MsgBox "Cofre criado em Credenciais ('cofre_discord.zip') e tokens apagados do PC!", vbInformation, "Protecao Ativada"
    Else
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' =========================================================================
' MODO 2: USO NORMAL (Restaura -> Abre Discord -> Bloqueio Instantaneo)
' =========================================================================
strPass = PedirSenhaOculta("Cofre Discord", "Digite a senha para abrir o Discord:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

intRet = objShell.Run("""" & str7z & """ t """ & strZipFile & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

If Not objFSO.FolderExists(strDiscordData) Then objFSO.CreateFolder(strDiscordData)
LimparTokens objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo

intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strDiscordData & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    LimparTokens objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo
    MsgBox "Falha ao extrair o cofre do Discord.", vbCritical, "Erro"
    WScript.Quit
End If

' Inicia o Discord
objShell.Run """" & strDiscordExe & """ --processStart Discord.exe", 1, False

' Aguarda ate 45 segundos para o Discord.exe iniciar (considerando eventuais updates)
For i = 1 To 300
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'Discord.exe'")
    If colProc.Count > 0 Then Exit For
    WScript.Sleep 150
Next

' Monitora a cada 80ms e reage imediatamente ao encerrar
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'Discord.exe'")
    If colProc.Count = 0 Then
        WScript.Sleep 80
        Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'Discord.exe'")
        If colProc.Count = 0 Then Exit Do
    End If
    WScript.Sleep 80
Loop

' 1. BLOQUEIO INSTANTANEO (0ms): Derruba processos e arranca Local Storage + Network na hora
EncerrarTudoDiscord objWMI
LimparPasta objFSO, strStageDir
objFSO.CreateFolder(strStageDir)

For i = 1 To 40
    ColetarTokens objFSO, strDiscordData, strStageDir, arrPastasAlvo, arrArquivosAlvo, False
    If Not ExistemTokens(objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo) Then Exit For
    EncerrarTudoDiscord objWMI
    WScript.Sleep 15
Next

' 2. REEMPACOTAMENTO EM SEGUNDO PLANO (PC ja esta 100% deslogado)
If PastaTemConteudo(objFSO, strStageDir) Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        objFSO.DeleteFile strZipFile, True
        objFSO.MoveFile strTmpZip, strZipFile
    End If
End If

LimparPasta objFSO, strStageDir
For i = 1 To 10
    LimparTokens objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo
    If Not ExistemTokens(objFSO, strDiscordData, arrPastasAlvo, arrArquivosAlvo) Then Exit For
    WScript.Sleep 50
Next

On Error Resume Next
objShell.RegDelete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\Discord"
On Error GoTo 0

MsgBox "Discord encerrado. Cofre atualizado e tokens removidos do PC.", vbInformation, "Limpeza Concluida"

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Function DiscordAtivo(wmi)
    Dim procs
    DiscordAtivo = False
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select ProcessId From Win32_Process Where Name = 'Discord.exe' Or (Name = 'Update.exe' And CommandLine Like '%Discord%')")
    If procs.Count > 0 Then DiscordAtivo = True
    On Error GoTo 0
End Function

Sub EncerrarTudoDiscord(wmi)
    Dim procs, p
    EncerrarProcesso wmi, "Discord.exe"
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select * From Win32_Process Where Name = 'Update.exe' And CommandLine Like '%Discord%'")
    For Each p In procs
        p.Terminate
    Next
    On Error GoTo 0
End Sub

Sub ColetarTokens(fso, origem, destino, pastas, arquivos, apenasCopiar)
    Dim item
    On Error Resume Next
    For Each item In pastas
        If fso.FolderExists(origem & "\" & item) Then
            If apenasCopiar Then
                fso.CopyFolder origem & "\" & item, destino & "\" & item, True
            Else
                fso.MoveFolder origem & "\" & item, destino & "\" & item
            End If
        End If
    Next
    For Each item In arquivos
        If fso.FileExists(origem & "\" & item) Then
            If apenasCopiar Then
                fso.CopyFile origem & "\" & item, destino & "\" & item, True
            Else
                fso.MoveFile origem & "\" & item, destino & "\" & item
            End If
        End If
    Next
    On Error GoTo 0
End Sub

Sub LimparTokens(fso, pastaBase, pastas, arquivos)
    Dim item
    On Error Resume Next
    For Each item In pastas
        If fso.FolderExists(pastaBase & "\" & item) Then fso.DeleteFolder pastaBase & "\" & item, True
    Next
    For Each item In arquivos
        If fso.FileExists(pastaBase & "\" & item) Then fso.DeleteFile pastaBase & "\" & item, True
    Next
    On Error GoTo 0
End Sub

Function ExistemTokens(fso, pastaBase, pastas, arquivos)
    Dim item
    ExistemTokens = False
    For Each item In pastas
        If fso.FolderExists(pastaBase & "\" & item) Then
            ExistemTokens = True
            Exit Function
        End If
    Next
    For Each item In arquivos
        If fso.FileExists(pastaBase & "\" & item) Then
            ExistemTokens = True
            Exit Function
        End If
    Next
End Function

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
    If fso.FolderExists(caminho) Then fso.DeleteFolder caminho, True
    On Error GoTo 0
End Sub

Function PastaTemConteudo(fso, caminho)
    Dim pasta
    PastaTemConteudo = False
    On Error Resume Next
    If fso.FolderExists(caminho) Then
        Set pasta = fso.GetFolder(caminho)
        If pasta.Files.Count > 0 Or pasta.SubFolders.Count > 0 Then PastaTemConteudo = True
    End If
    On Error GoTo 0
End Function

Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_discord_auth.hta"

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
    objFile.WriteLine "function iniciar() { window.resizeTo(375, 175); window.moveTo((screen.availWidth - 375) / 2, (screen.availHeight - 175) / 2); document.getElementById('senha').focus(); }"
    objFile.WriteLine "function enviar() { var v = document.getElementById('senha').value; if (v !== '') { new ActiveXObject('Scripting.FileSystemObject').GetStandardStream(1).Write(v); } window.close(); }"
    objFile.WriteLine "function tecla() { if (window.event.keyCode === 13) enviar(); if (window.event.keyCode === 27) window.close(); }"
    objFile.WriteLine "</script></head><body onload=""iniciar()"">"
    objFile.WriteLine "<p>" & mensagem & "</p>"
    objFile.WriteLine "<input type=""password"" id=""senha"" onkeydown=""tecla()"" />"
    objFile.WriteLine "<div class=""btns""><button onclick=""enviar()"">OK</button><button onclick=""window.close()"">Cancelar</button></div></body></html>"
    objFile.Close

    Set execObj = objShell.Exec("mshta.exe """ & strTempHta & """")
    saida = execObj.StdOut.ReadAll

    On Error Resume Next
    If objFSO.FileExists(strTempHta) Then objFSO.DeleteFile strTempHta, True
    On Error GoTo 0

    PedirSenhaOculta = saida
End Function
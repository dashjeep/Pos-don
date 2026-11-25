Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strLocalApp
Dim strPkgDir, strPkgName, strStageDir, str7z
Dim strPass, strPassConfirm, strSafePass, intRet, i

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_whatsapp.zip"
strTmpZip = strZipFile & ".tmp"
strLocalApp = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")

If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Instale o 7-Zip antes de executar.", vbCritical, "Erro"
    WScript.Quit
End If

' Localiza automaticamente o pacote do WhatsApp Desktop instalado
strPkgDir = LocalizarPacoteWhatsApp(objFSO, strLocalApp & "\Packages")
If strPkgDir = "" Then
    MsgBox "Pacote do WhatsApp Desktop nao encontrado em AppData\Local\Packages.", vbCritical, "Erro"
    WScript.Quit
End If

strPkgName = objFSO.GetFileName(strPkgDir)
strStageDir = strPkgDir & "\_cofre_wa_tmp"

EncerrarTudoWhatsApp objWMI
WScript.Sleep 300
LimparPasta objFSO, strStageDir

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_whatsapp.zip completo e limpa o PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not PastaTemConteudo(objFSO, strPkgDir & "\LocalState") And Not PastaTemConteudo(objFSO, strPkgDir & "\LocalCache") Then
        MsgBox "Nenhuma sessao conectada encontrada no WhatsApp Desktop." & vbCrLf & "Abra o WhatsApp normalmente, conecte seu celular via QR Code, feche o aplicativo e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre WhatsApp", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")

    objFSO.CreateFolder(strStageDir)
    ColetarDadosWhatsApp objFSO, strPkgDir, strStageDir, True

    intRet = objShell.Run("""" & str7z & """ a -ssw -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strStageDir & "\*"" -xr!Crashpad -xr!Logs -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!DawnCache -xr!DawnGraphiteCache -xr!DawnWebGPUCache -xr!CacheStorage -xr!MediaCache -p""" & strSafePass & """ -y", 0, True)

    LimparPasta objFSO, strStageDir

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparSessaoWhatsApp objFSO, strPkgDir
        MsgBox "Cofre completo criado em Credenciais ('cofre_whatsapp.zip') e sessao do WhatsApp apagada do PC!", vbInformation, "Protecao Ativada"
    Else
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' =========================================================================
' MODO 2: USO NORMAL (Limpa residuos -> Restaura -> Abre -> Isola ao Sair)
' =========================================================================
strPass = PedirSenhaOculta("Cofre WhatsApp Desktop", "Digite a senha para abrir o WhatsApp:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

' Valida a senha antes de alterar qualquer arquivo
intRet = objShell.Run("""" & str7z & """ t """ & strZipFile & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

' Remove qualquer estado vazio/deslogado (caso o WhatsApp comum tenha sido aberto antes)
LimparSessaoWhatsApp objFSO, strPkgDir

' Extrai LocalState, LocalCache, Settings e RoamingState de volta para o pacote
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strPkgDir & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    LimparSessaoWhatsApp objFSO, strPkgDir
    MsgBox "Falha ao extrair o cofre do WhatsApp.", vbCritical, "Erro"
    WScript.Quit
End If

' Inicia o aplicativo UWP da Microsoft Store pelo seu AppUserModelID
objShell.Run "explorer.exe shell:AppsFolder\" & strPkgName & "!App", 1, False

' Aguarda ate 20 segundos para o WhatsApp iniciar
For i = 1 To 130
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'WhatsApp.Root.exe' Or Name = 'WhatsApp.exe'")
    If colProc.Count > 0 Then Exit For
    WScript.Sleep 150
Next

' Monitora enquanto o WhatsApp estiver aberto
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'WhatsApp.Root.exe' Or Name = 'WhatsApp.exe'")
    If colProc.Count = 0 Then
        WScript.Sleep 350
        Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'WhatsApp.Root.exe' Or Name = 'WhatsApp.exe'")
        If colProc.Count = 0 Then Exit Do
    End If
    WScript.Sleep 200
Loop

' Aguarda gravacao final do SQLite WAL e WebView2, depois encerra processos filhos do WhatsApp
WScript.Sleep 600
EncerrarTudoWhatsApp objWMI
WScript.Sleep 200

LimparPasta objFSO, strStageDir
objFSO.CreateFolder(strStageDir)

For i = 1 To 15
    ColetarDadosWhatsApp objFSO, strPkgDir, strStageDir, False
    If Not PastaTemConteudo(objFSO, strPkgDir & "\LocalState") And Not PastaTemConteudo(objFSO, strPkgDir & "\LocalCache") Then Exit For
    EncerrarTudoWhatsApp objWMI
    WScript.Sleep 150
Next

' Reempacota a sessao atualizada (com o PC ja isolado)
If PastaTemConteudo(objFSO, strStageDir) Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -ssw -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -xr!Crashpad -xr!Logs -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!DawnCache -xr!DawnGraphiteCache -xr!DawnWebGPUCache -xr!CacheStorage -xr!MediaCache -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        objFSO.DeleteFile strZipFile, True
        objFSO.MoveFile strTmpZip, strZipFile
    End If
End If

LimparPasta objFSO, strStageDir
LimparSessaoWhatsApp objFSO, strPkgDir

MsgBox "WhatsApp encerrado. Cofre atualizado e sessao removida do PC.", vbInformation, "Limpeza Concluida"

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Function LocalizarPacoteWhatsApp(fso, packagesDir)
    Dim subP
    LocalizarPacoteWhatsApp = ""
    If Not fso.FolderExists(packagesDir) Then Exit Function
    For Each subP In fso.GetFolder(packagesDir).SubFolders
        If InStr(1, subP.Name, "WhatsAppDesktop", vbTextCompare) > 0 Then
            LocalizarPacoteWhatsApp = subP.Path
            Exit Function
        End If
    Next
End Function

Sub EncerrarTudoWhatsApp(wmi)
    Dim procs, p
    EncerrarProcesso wmi, "WhatsApp.Root.exe"
    EncerrarProcesso wmi, "WhatsApp.exe"
    ' Encerra apenas instancias do WebView2 pertencentes ao pacote do WhatsApp
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select * From Win32_Process Where Name = 'msedgewebview2.exe'")
    For Each p In procs
        If InStr(1, p.CommandLine & "", "WhatsAppDesktop", vbTextCompare) > 0 Then
            p.Terminate
        End If
    Next
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

Sub ColetarDadosWhatsApp(fso, pkgDir, stageDir, apenasCopiar)
    Dim subNome, orig, dest
    On Error Resume Next
    For Each subNome In Array("LocalState", "LocalCache", "RoamingState")
        orig = pkgDir & "\" & subNome
        dest = stageDir & "\" & subNome
        If fso.FolderExists(orig) Then
            If apenasCopiar Then
                fso.CopyFolder orig, dest, True
            Else
                fso.MoveFolder orig, dest
                If fso.FolderExists(orig) Then
                    fso.CopyFolder orig, dest, True
                    fso.DeleteFolder orig, True
                End If
            End If
        End If
    Next
    ' Copia Settings (settings.dat pode ter handle de leitura do sistema UWP)
    If fso.FolderExists(pkgDir & "\Settings") Then
        fso.CopyFolder pkgDir & "\Settings", stageDir & "\Settings", True
    End If
    On Error GoTo 0
End Sub

Sub LimparSessaoWhatsApp(fso, pkgDir)
    Dim subNome, caminho, pastaSettings, arq
    On Error Resume Next
    For Each subNome In Array("LocalState", "LocalCache", "RoamingState")
        caminho = pkgDir & "\" & subNome
        If fso.FolderExists(caminho) Then fso.DeleteFolder caminho, True
        If Not fso.FolderExists(caminho) Then fso.CreateFolder caminho
    Next
    If fso.FolderExists(pkgDir & "\Settings") Then
        Set pastaSettings = fso.GetFolder(pkgDir & "\Settings")
        For Each arq In pastaSettings.Files
            fso.DeleteFile arq.Path, True
        Next
    End If
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
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_wa_auth.hta"

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
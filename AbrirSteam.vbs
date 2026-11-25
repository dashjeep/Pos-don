Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strSteamDir, strStageDir, strSteamExe, str7z
Dim strPass, strPassConfirm, strSafePass, strFileList, strAutoUser, intRet, i
Dim pastaRaiz, arq, objStageFolder

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

' Pasta padronizada do cofre
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_steam.zip"
strTmpZip = strZipFile & ".tmp"

' Detecta automaticamente a pasta da Steam
strSteamDir = ""
On Error Resume Next
strSteamDir = Replace(objShell.RegRead("HKCU\Software\Valve\Steam\SteamPath"), "/", "\")
On Error GoTo 0

If strSteamDir = "" Or Not objFSO.FileExists(strSteamDir & "\steam.exe") Then
    If objFSO.FileExists("C:\Program Files (x86)\Steam\steam.exe") Then
        strSteamDir = "C:\Program Files (x86)\Steam"
    ElseIf objFSO.FileExists("C:\Steam\steam.exe") Then
        strSteamDir = "C:\Steam"
    Else
        If WScript.Arguments.Count > 0 Then
            If LCase(WScript.Arguments(0)) = "/bootclean" Then WScript.Quit
        End If
        MsgBox "steam.exe nao encontrado no computador.", vbCritical, "Erro"
        WScript.Quit
    End If
End If

strSteamExe = strSteamDir & "\steam.exe"
strStageDir = strSteamDir & "\_cofre_tmp"

' =========================================================================
' MODO SILENCIOSO DE RECUPERACAO POS-QUEDA DE LUZ (/bootclean)
' =========================================================================
If WScript.Arguments.Count > 0 Then
    If LCase(WScript.Arguments(0)) = "/bootclean" Then
        If objFSO.FileExists(strZipFile) Then
            Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'steam.exe'")
            If colProc.Count = 0 Then
                LimparDadosSteam objShell, objFSO, strSteamDir
                LimparPastaRecursiva objFSO, strStageDir
                If objFSO.FileExists(strTmpZip) Then
                    On Error Resume Next
                    objFSO.DeleteFile strTmpZip, True
                    On Error GoTo 0
                End If
            End If
        End If
        WScript.Quit
    End If
End If

' Detecta automaticamente o 7-Zip
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Instale o 7-Zip antes de executar.", vbCritical, "Erro"
    WScript.Quit
End If

' Encerra processos residuais e limpa qualquer vestigio anterior (ex: queda de luz)
EncerrarProcesso objWMI, "steam.exe"
EncerrarProcesso objWMI, "steamwebhelper.exe"
EncerrarProcesso objWMI, "GameOverlayUI.exe"
LimparPastaRecursiva objFSO, strStageDir
If objFSO.FileExists(strTmpZip) Then
    On Error Resume Next
    objFSO.DeleteFile strTmpZip, True
    On Error GoTo 0
End If

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_steam.zip e limpa o PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not objFSO.FileExists(strSteamDir & "\config\loginusers.vdf") Or Not objFSO.FileExists(strSteamDir & "\config\config.vdf") Then
        MsgBox "Nenhuma sessao salva encontrada na Steam." & vbCrLf & "Abra a Steam, faca login marcando 'Lembrar senha', feche a Steam completamente e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre Steam", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")
    strAutoUser = LerELimparRegAuth(objShell)
    GravarAutoLoginDat objFSO, strSteamDir, strAutoUser
    strFileList = MontarListaArquivosSteam(objFSO, strSteamDir)

    objShell.CurrentDirectory = strSteamDir
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ " & strFileList & " -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparDadosSteam objShell, objFSO, strSteamDir
        RegistrarProtecaoBoot objShell
        MsgBox "Cofre criado em Credenciais ('cofre_steam.zip') e credenciais apagadas do PC!", vbInformation, "Protecao Ativada"
    Else
        If objFSO.FileExists(strSteamDir & "\steam_autologin.dat") Then objFSO.DeleteFile strSteamDir & "\steam_autologin.dat", True
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' Garante que a limpeza automatica no boot esteja ativa caso ocorra queda de luz
RegistrarProtecaoBoot objShell

' =========================================================================
' MODO 2: USO NORMAL (Restaura -> Abre Steam -> Isolamento Instantaneo -> Repack)
' =========================================================================
strPass = PedirSenhaOculta("Cofre Steam", "Digite a senha para abrir a Steam:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

' Valida a senha antes de tocar nos arquivos locais
intRet = objShell.Run("""" & str7z & """ t """ & strZipFile & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    LimparDadosSteam objShell, objFSO, strSteamDir
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

LimparDadosSteam objShell, objFSO, strSteamDir

' Extrai os arquivos de autenticacao da Steam
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strSteamDir & """ -p""" & strSafePass & """ -y", 0, True)
If intRet <> 0 Then
    LimparDadosSteam objShell, objFSO, strSteamDir
    MsgBox "Falha ao extrair o cofre da Steam!", vbCritical, "Erro"
    WScript.Quit
End If

RestaurarRegAuth objShell, objFSO, strSteamDir

' Inicia a Steam
objShell.Run """" & strSteamExe & """", 1, False

' Aguarda ate 15 segundos para steam.exe aparecer
For i = 1 To 150
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'steam.exe'")
    If colProc.Count > 0 Then Exit For
    WScript.Sleep 100
Next

' Monitora a cada 80ms e reage imediatamente quando a Steam fechar
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'steam.exe'")
    If colProc.Count = 0 Then
        WScript.Sleep 80
        Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'steam.exe'")
        If colProc.Count = 0 Then Exit Do
    End If
    WScript.Sleep 80
Loop

' 1. BLOQUEIO INSTANTANEO (< 10ms): Limpa registro, mata processos filhos e arranca loginusers.vdf primeiro
strAutoUser = LerELimparRegAuth(objShell)
EncerrarProcesso objWMI, "steamwebhelper.exe"
EncerrarProcesso objWMI, "GameOverlayUI.exe"

objFSO.CreateFolder(strStageDir)
On Error Resume Next
Set objStageFolder = objFSO.GetFolder(strStageDir)
objStageFolder.Attributes = 6 ' Oculto + Sistema
On Error GoTo 0
objFSO.CreateFolder(strStageDir & "\config")

' Arranca loginusers.vdf e config.vdf imediatamente para impedir abertura pelo icone normal
MoverComRetentativa objFSO, strSteamDir & "\config\loginusers.vdf", strStageDir & "\config\loginusers.vdf"
MoverComRetentativa objFSO, strSteamDir & "\config\config.vdf", strStageDir & "\config\config.vdf"

Set pastaRaiz = objFSO.GetFolder(strSteamDir)
For Each arq In pastaRaiz.Files
    If LCase(Left(arq.Name, 4)) = "ssfn" Then
        MoverComRetentativa objFSO, arq.Path, strStageDir & "\" & arq.Name
    End If
Next

' 2. REEMPACOTAMENTO ATOMICO EM SEGUNDO PLANO (com a pasta da Steam ja vazia e limpa)
If objFSO.FileExists(strStageDir & "\config\config.vdf") And objFSO.FileExists(strStageDir & "\config\loginusers.vdf") Then
    GravarAutoLoginDat objFSO, strStageDir, strAutoUser
    strFileList = MontarListaArquivosSteam(objFSO, strStageDir)

    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    objShell.CurrentDirectory = strStageDir
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ " & strFileList & " -p""" & strSafePass & """ -y", 0, True)

    ' Substituicao atomica: so apaga o cofre antigo se o novo .tmp foi gerado integro
    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        If objFSO.GetFile(strTmpZip).Size > 0 Then
            If objFSO.FileExists(strZipFile) Then objFSO.DeleteFile strZipFile, True
            objFSO.MoveFile strTmpZip, strZipFile
        End If
    End If
End If

' 3. LIMPEZA TOTAL DE VESTIGIOS
LimparPastaRecursiva objFSO, strStageDir
LimparDadosSteam objShell, objFSO, strSteamDir
If objFSO.FileExists(strTmpZip) Then
    On Error Resume Next
    objFSO.DeleteFile strTmpZip, True
    On Error GoTo 0
End If

MsgBox "Steam encerrada. Cofre atualizado e credenciais removidas.", vbInformation, "Limpeza Concluida"

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Sub RegistrarProtecaoBoot(sh)
    Dim strCmd
    On Error Resume Next
    strCmd = "wscript.exe """ & WScript.ScriptFullName & """ /bootclean"
    sh.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Run\CofreSteamGuard", strCmd, "REG_SZ"
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

Sub LimparPastaRecursiva(fso, caminho)
    Dim pasta, arq, subP
    On Error Resume Next
    If Not fso.FolderExists(caminho) Then Exit Sub
    Set pasta = fso.GetFolder(caminho)
    pasta.Attributes = 0
    fso.DeleteFolder caminho, True
    If fso.FolderExists(caminho) Then
        For Each arq In pasta.Files
            arq.Attributes = 0
            fso.DeleteFile arq.Path, True
        Next
        For Each subP In pasta.SubFolders
            LimparPastaRecursiva fso, subP.Path
        Next
        fso.DeleteFolder caminho, True
    End If
    On Error GoTo 0
End Sub

Sub MoverComRetentativa(fso, origem, destino)
    Dim tentativa
    For tentativa = 1 To 40
        On Error Resume Next
        If fso.FileExists(origem) Then
            fso.MoveFile origem, destino
        End If
        On Error GoTo 0
        If Not fso.FileExists(origem) Then Exit For
        WScript.Sleep 15
    Next
End Sub

Function LerELimparRegAuth(sh)
    Dim u
    u = ""
    On Error Resume Next
    u = sh.RegRead("HKCU\Software\Valve\Steam\AutoLoginUser")
    sh.RegWrite "HKCU\Software\Valve\Steam\AutoLoginUser", "", "REG_SZ"
    sh.RegWrite "HKCU\Software\Valve\Steam\RememberPassword", 0, "REG_DWORD"
    On Error GoTo 0
    LerELimparRegAuth = u
End Function

Sub GravarAutoLoginDat(fso, pastaDestino, autoUser)
    Dim f
    If autoUser <> "" Then
        Set f = fso.CreateTextFile(pastaDestino & "\steam_autologin.dat", True)
        f.Write autoUser
        f.Close
    End If
End Sub

Sub RestaurarRegAuth(sh, fso, pastaSteam)
    Dim datFile, f, autoUser
    datFile = pastaSteam & "\steam_autologin.dat"
    If fso.FileExists(datFile) Then
        Set f = fso.OpenTextFile(datFile, 1)
        If Not f.AtEndOfStream Then autoUser = f.ReadAll
        f.Close
        On Error Resume Next
        If autoUser <> "" Then
            sh.RegWrite "HKCU\Software\Valve\Steam\AutoLoginUser", autoUser, "REG_SZ"
            sh.RegWrite "HKCU\Software\Valve\Steam\RememberPassword", 1, "REG_DWORD"
        End If
        fso.DeleteFile datFile, True
        On Error GoTo 0
    End If
End Sub

Function MontarListaArquivosSteam(fso, pastaBase)
    Dim lista, pasta, arq
    lista = """config\config.vdf"" ""config\loginusers.vdf"""
    If fso.FileExists(pastaBase & "\steam_autologin.dat") Then
        lista = lista & " ""steam_autologin.dat"""
    End If
    Set pasta = fso.GetFolder(pastaBase)
    For Each arq In pasta.Files
        If LCase(Left(arq.Name, 4)) = "ssfn" Then
            lista = lista & " ""ssfn*"""
            Exit For
        End If
    Next
    MontarListaArquivosSteam = lista
End Function

Sub LimparDadosSteam(sh, fso, pastaSteam)
    Dim pasta, arq
    On Error Resume Next
    If fso.FileExists(pastaSteam & "\config\config.vdf") Then fso.DeleteFile pastaSteam & "\config\config.vdf", True
    If fso.FileExists(pastaSteam & "\config\loginusers.vdf") Then fso.DeleteFile pastaSteam & "\config\loginusers.vdf", True
    If fso.FileExists(pastaSteam & "\steam_autologin.dat") Then fso.DeleteFile pastaSteam & "\steam_autologin.dat", True
    Set pasta = fso.GetFolder(pastaSteam)
    For Each arq In pasta.Files
        If LCase(Left(arq.Name, 4)) = "ssfn" Then
            fso.DeleteFile arq.Path, True
        End If
    Next
    sh.RegWrite "HKCU\Software\Valve\Steam\AutoLoginUser", "", "REG_SZ"
    sh.RegWrite "HKCU\Software\Valve\Steam\RememberPassword", 0, "REG_DWORD"
    On Error GoTo 0
End Sub

Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_steam_auth.hta"

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
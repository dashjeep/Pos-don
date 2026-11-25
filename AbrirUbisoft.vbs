Option Explicit

Dim objShell, objFSO, objWMI, colProc
Dim strVaultDir, strZipFile, strTmpZip, strLocalApp, strUbiDir, strUbiData, strStageDir, str7z, strUbiExe
Dim strPass, strPassConfirm, strSafePass, intRet, i

Set objShell = CreateObject("WScript.Shell")
Set objFSO = CreateObject("Scripting.FileSystemObject")
Set objWMI = GetObject("winmgmts:\\.\root\cimv2")

' Pasta do cofre (.zip com AES-256)
strVaultDir = objShell.ExpandEnvironmentStrings("%USERPROFILE%") & "\Documents\Credenciais"
If Not objFSO.FolderExists(strVaultDir) Then
    objShell.Run "cmd.exe /c mkdir """ & strVaultDir & """ 2>nul", 0, True
End If

strZipFile = strVaultDir & "\cofre_ubisoft.zip"
strTmpZip = strZipFile & ".tmp"

strLocalApp = objShell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
strUbiDir = "C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher"
strUbiData = strLocalApp & "\Ubisoft Game Launcher"
strStageDir = strLocalApp & "\_cofre_ubisoft_tmp"

' Detecta automaticamente o 7-Zip
If objFSO.FileExists("C:\Program Files\7-Zip\7z.exe") Then
    str7z = "C:\Program Files\7-Zip\7z.exe"
ElseIf objFSO.FileExists("C:\Program Files (x86)\7-Zip\7z.exe") Then
    str7z = "C:\Program Files (x86)\7-Zip\7z.exe"
Else
    MsgBox "7-Zip nao encontrado! Instale o 7-Zip antes de executar.", vbCritical, "Erro"
    WScript.Quit
End If

' Detecta o executavel do Ubisoft Connect
strUbiExe = ""
If objFSO.FileExists(strUbiDir & "\UbisoftConnect.exe") Then
    strUbiExe = strUbiDir & "\UbisoftConnect.exe"
ElseIf objFSO.FileExists(strUbiDir & "\upc.exe") Then
    strUbiExe = strUbiDir & "\upc.exe"
Else
    On Error Resume Next
    strUbiDir = objShell.RegRead("HKLM\SOFTWARE\WOW6432Node\Ubisoft\Launcher\InstallDir")
    If Right(strUbiDir, 1) = "\" Then strUbiDir = Left(strUbiDir, Len(strUbiDir) - 1)
    On Error GoTo 0
    If objFSO.FileExists(strUbiDir & "\UbisoftConnect.exe") Then
        strUbiExe = strUbiDir & "\UbisoftConnect.exe"
    ElseIf objFSO.FileExists(strUbiDir & "\upc.exe") Then
        strUbiExe = strUbiDir & "\upc.exe"
    End If
End If

If strUbiExe = "" Or Not objFSO.FileExists(strUbiExe) Then
    MsgBox "Executavel do Ubisoft Connect nao encontrado em C:\Program Files (x86)\Ubisoft\Ubisoft Game Launcher.", vbCritical, "Erro"
    WScript.Quit
End If

' Encerra qualquer processo residual antes de iniciar
If AlgumProcessoUbiAtivo(objWMI) Then
    EncerrarTudoUbi objWMI
    WScript.Sleep 250
End If
LimparPastaRecursiva objFSO, strStageDir

' =========================================================================
' MODO 1: PRIMEIRA EXECUCAO (Cria cofre_ubisoft.zip e limpa o PC)
' =========================================================================
If Not objFSO.FileExists(strZipFile) Then
    If Not objFSO.FileExists(strUbiData & "\users.dat") And Not PastaTemConteudo(objFSO, strUbiData) Then
        MsgBox "Nenhuma sessao salva encontrada no Ubisoft Connect." & vbCrLf & "Abra o Ubisoft Connect normalmente, faca login marcando 'Lembrar-me', feche-o completamente perto do relogio (Sair) e execute este script novamente.", vbExclamation, "Configuracao Inicial"
        WScript.Quit
    End If

    strPass = PedirSenhaOculta("Criar Cofre Ubisoft", "PRIMEIRO USO: Digite a senha para criar o cofre AES-256:")
    If strPass = "" Then WScript.Quit

    strPassConfirm = PedirSenhaOculta("Confirmar Senha", "Digite a senha novamente para confirmar:")
    If strPass <> strPassConfirm Then
        MsgBox "As senhas nao conferem. Nada foi alterado.", vbCritical, "Erro"
        WScript.Quit
    End If

    strSafePass = Replace(strPass, """", "\""")

    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strZipFile & """ """ & strUbiData & "\*"" -xr!httpcache -xr!Cache_Data -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!DawnCache -xr!DawnGraphiteCache -xr!DawnWebGPUCache -xr!avatars -xr!assets -xr!logs -xr!crashes -xr!Crashpad -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strZipFile) Then
        LimparPastaRecursiva objFSO, strUbiData
        MsgBox "Cofre criado em Credenciais ('cofre_ubisoft.zip') e credenciais apagadas do PC!", vbInformation, "Protecao Ativada"
    Else
        MsgBox "Erro ao criptografar arquivos. Os dados originais foram mantidos.", vbCritical, "Erro"
    End If
    WScript.Quit
End If

' =========================================================================
' MODO 2: USO NORMAL (Restaura -> Abre Ubisoft -> Bloqueio Instantaneo)
' =========================================================================
strPass = PedirSenhaOculta("Cofre Ubisoft Connect", "Digite a senha para abrir o Ubisoft Connect:")
If strPass = "" Then WScript.Quit

strSafePass = Replace(strPass, """", "\""")

LimparPastaRecursiva objFSO, strUbiData
If Not objFSO.FolderExists(strUbiData) Then objFSO.CreateFolder(strUbiData)

' Extrai a sessao criptografada
intRet = objShell.Run("""" & str7z & """ x """ & strZipFile & """ -o""" & strUbiData & """ -p""" & strSafePass & """ -y", 0, True)

If intRet <> 0 Then
    LimparPastaRecursiva objFSO, strUbiData
    MsgBox "Senha incorreta ou arquivo corrompido!", vbCritical, "Acesso Negado"
    WScript.Quit
End If

' Inicia o Ubisoft Connect
objShell.Run """" & strUbiExe & """", 1, False

' Aguarda ate 15 segundos para o processo principal iniciar
For i = 1 To 100
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'UbisoftConnect.exe' Or Name = 'upc.exe'")
    If colProc.Count > 0 Then Exit For
    WScript.Sleep 150
Next

' Monitora a cada 80ms e reage no exato instante em que fechar
Do
    Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'UbisoftConnect.exe' Or Name = 'upc.exe'")
    If colProc.Count = 0 Then
        WScript.Sleep 80
        Set colProc = objWMI.ExecQuery("Select ProcessId From Win32_Process Where Name = 'UbisoftConnect.exe' Or Name = 'upc.exe'")
        If colProc.Count = 0 Then Exit Do
    End If
    WScript.Sleep 80
Loop

' 1. BLOQUEIO INSTANTANEO (0ms): Derruba helpers e arranca users.dat PRIMEIRO
EncerrarTudoUbi objWMI
LimparPastaRecursiva objFSO, strStageDir
objFSO.CreateFolder(strStageDir)

' Isola o token principal (users.dat) imediatamente, antes de qualquer log
For i = 1 To 40
    On Error Resume Next
    If objFSO.FileExists(strUbiData & "\users.dat") Then
        objFSO.MoveFile strUbiData & "\users.dat", strStageDir & "\users.dat"
    End If
    On Error GoTo 0
    If Not objFSO.FileExists(strUbiData & "\users.dat") Then Exit For
    EncerrarTudoUbi objWMI
    WScript.Sleep 15
Next

' Move o restante dos arquivos de configuracao/sessao (ignorando logs presos se houver)
For i = 1 To 15
    MoverRestanteUbi objFSO, strUbiData, strStageDir
    LimparPastaRecursiva objFSO, strUbiData
    If Not objFSO.FolderExists(strUbiData) Then Exit For
    EncerrarTudoUbi objWMI
    WScript.Sleep 50
Next

' 2. REEMPACOTAMENTO EM SEGUNDO PLANO (PC ja esta 100% deslogado)
If PastaTemConteudo(objFSO, strStageDir) Then
    If objFSO.FileExists(strTmpZip) Then objFSO.DeleteFile strTmpZip, True
    intRet = objShell.Run("""" & str7z & """ a -tzip -mem=AES256 -mx=1 """ & strTmpZip & """ """ & strStageDir & "\*"" -xr!httpcache -xr!Cache_Data -xr!Cache -xr!""Code Cache"" -xr!GPUCache -xr!DawnCache -xr!DawnGraphiteCache -xr!DawnWebGPUCache -xr!avatars -xr!assets -xr!logs -xr!crashes -xr!Crashpad -p""" & strSafePass & """ -y", 0, True)

    If intRet = 0 And objFSO.FileExists(strTmpZip) Then
        objFSO.DeleteFile strZipFile, True
        objFSO.MoveFile strTmpZip, strZipFile
    End If
End If

LimparPastaRecursiva objFSO, strStageDir
LimparPastaRecursiva objFSO, strUbiData

MsgBox "Ubisoft Connect encerrado. Cofre atualizado e credenciais bloqueadas.", vbInformation, "Limpeza Concluida"

' =========================================================================
' FUNCOES AUXILIARES
' =========================================================================
Function AlgumProcessoUbiAtivo(wmi)
    Dim procs
    AlgumProcessoUbiAtivo = False
    On Error Resume Next
    Set procs = wmi.ExecQuery("Select ProcessId From Win32_Process Where Name = 'UbisoftConnect.exe' Or Name = 'upc.exe' Or Name = 'UplayWebCore.exe' Or Name = 'UbisoftWebCore.exe'")
    If procs.Count > 0 Then AlgumProcessoUbiAtivo = True
    On Error GoTo 0
End Function

Sub EncerrarTudoUbi(wmi)
    EncerrarProcesso wmi, "UplayWebCore.exe"
    EncerrarProcesso wmi, "UbisoftWebCore.exe"
    EncerrarProcesso wmi, "UbisoftExtension.exe"
    EncerrarProcesso wmi, "UplayCrashReporter.exe"
    EncerrarProcesso wmi, "upc.exe"
    EncerrarProcesso wmi, "UbisoftConnect.exe"
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

Sub MoverRestanteUbi(fso, origem, destino)
    Dim pasta, arq, subP, nomeLow
    On Error Resume Next
    If Not fso.FolderExists(origem) Then Exit Sub
    If Not fso.FolderExists(destino) Then fso.CreateFolder destino
    Set pasta = fso.GetFolder(origem)
    For Each arq In pasta.Files
        fso.MoveFile arq.Path, destino & "\" & arq.Name
    Next
    For Each subP In pasta.SubFolders
        nomeLow = LCase(subP.Name)
        If nomeLow = "logs" Or nomeLow = "crashes" Or nomeLow = "crashpad" Or nomeLow = "cache" Or nomeLow = "cache_data" Or nomeLow = "httpcache" Or nomeLow = "code cache" Or nomeLow = "gpucache" Or nomeLow = "dawncache" Then
            fso.DeleteFolder subP.Path, True
        Else
            fso.MoveFolder subP.Path, destino & "\" & subP.Name
            If fso.FolderExists(subP.Path) Then
                MoverRestanteUbi fso, subP.Path, destino & "\" & subP.Name
                fso.DeleteFolder subP.Path, True
            End If
        End If
    Next
    On Error GoTo 0
End Sub

Sub LimparPastaRecursiva(fso, caminho)
    Dim pasta, arq, subP
    On Error Resume Next
    If Not fso.FolderExists(caminho) Then Exit Sub
    fso.DeleteFolder caminho, True
    If fso.FolderExists(caminho) Then
        Set pasta = fso.GetFolder(caminho)
        For Each arq In pasta.Files
            fso.DeleteFile arq.Path, True
        Next
        For Each subP In pasta.SubFolders
            LimparPastaRecursiva fso, subP.Path
        Next
        fso.DeleteFolder caminho, True
    End If
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

Function PedirSenhaOculta(titulo, mensagem)
    Dim strTempHta, objFile, execObj, saida
    strTempHta = objShell.ExpandEnvironmentStrings("%TEMP%") & "\cofre_ubi_auth.hta"

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
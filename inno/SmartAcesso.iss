#define MyAppName "SmartAcesso"
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0"
#endif
#define MyAppPublisher "SmartPonto"
#define MyAppURL "https://www.smartponto.com"
#define Staging "..\staging"

[Setup]
AppId={{8F3C1A62-4B9E-4D71-9C2A-7E1B5D0A3F18}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=SmartAcesso-Setup-{#MyAppVersion}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
UninstallDisplayName={#MyAppName}
SetupLogging=yes
CloseApplications=yes
RestartApplications=no
UsePreviousTasks=yes

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Types]
Name: "full"; Description: "Completa (nucleo + TopData + desktop)"
Name: "operator"; Description: "Operacao (nucleo + desktop)"
Name: "gate"; Description: "Catraca (nucleo + TopData)"
Name: "custom"; Description: "Personalizada"; Flags: iscustom

[Components]
Name: "core"; Description: "Nucleo SmartAcesso (servico Windows, porta 8090)"; Types: full operator gate custom; Flags: fixed
Name: "topdata"; Description: "Integracao TopData / catraca (servico Windows, porta 8080)"; Types: full gate
Name: "desktop"; Description: "Aplicativo Desktop"; Types: full operator

[Tasks]
Name: "desktopicon"; Description: "Criar atalho na Area de Trabalho"; Components: desktop; Flags: unchecked
Name: "autostart"; Description: "Iniciar o Desktop com o Windows"; Components: desktop; Flags: unchecked

[Dirs]
Name: "{commonappdata}\SmartAcesso\config\core"; Components: core; Flags: uninsneveruninstall
Name: "{commonappdata}\SmartAcesso\data\core\database"; Components: core; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{commonappdata}\SmartAcesso\logs\core"; Components: core; Permissions: users-modify
Name: "{commonappdata}\SmartAcesso\config\topdata"; Components: topdata; Flags: uninsneveruninstall
Name: "{commonappdata}\SmartAcesso\data\topdata\database"; Components: topdata; Permissions: users-modify; Flags: uninsneveruninstall
Name: "{commonappdata}\SmartAcesso\logs\topdata"; Components: topdata; Permissions: users-modify

[Files]
Source: "{#Staging}\core\*"; DestDir: "{app}\core"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: core
Source: "{#Staging}\config\core\*"; DestDir: "{commonappdata}\SmartAcesso\config\core"; Flags: onlyifdoesntexist uninsneveruninstall; Components: core

Source: "{#Staging}\topdata\*"; DestDir: "{app}\topdata"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: topdata
Source: "{#Staging}\config\topdata\*"; DestDir: "{commonappdata}\SmartAcesso\config\topdata"; Flags: onlyifdoesntexist uninsneveruninstall; Components: topdata

Source: "{#Staging}\desktop\*"; DestDir: "{app}\desktop"; Flags: ignoreversion recursesubdirs createallsubdirs; Components: desktop

[Icons]
Name: "{group}\SmartAcesso"; Filename: "{app}\desktop\SmartAcesso.exe"; Components: desktop
Name: "{autodesktop}\SmartAcesso"; Filename: "{app}\desktop\SmartAcesso.exe"; Tasks: desktopicon; Components: desktop

[Run]
Filename: "{app}\desktop\SmartAcesso.exe"; Description: "Abrir o SmartAcesso agora"; Flags: nowait postinstall skipifsilent unchecked; Components: desktop

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "SmartAcessoDesktop"; ValueData: """{app}\desktop\SmartAcesso.exe"""; Flags: uninsdeletevalue; Tasks: autostart; Components: desktop

[UninstallDelete]
Type: files; Name: "{app}\core\SmartAcessoCore.xml"
Type: files; Name: "{app}\topdata\SmartAcessoTopData.xml"

[Code]
function SlashUri(const P: String): String;
begin
  Result := P;
  StringChangeEx(Result, '\', '/', True);
end;

procedure ExpandServiceTemplate(const Src, Dest: String);
var
  Lines: TArrayOfString;
  I: Integer;
  Line, ProgramData, ProgramDataUri: String;
begin
  if not FileExists(Src) then
  begin
    Log('Template ausente: ' + Src);
    Exit;
  end;
  if not LoadStringsFromFile(Src, Lines) then
  begin
    Log('Falha ao ler template: ' + Src);
    Exit;
  end;
  ProgramData := ExpandConstant('{commonappdata}\SmartAcesso');
  ProgramDataUri := SlashUri(ProgramData);
  for I := 0 to GetArrayLength(Lines) - 1 do
  begin
    Line := Lines[I];
    StringChangeEx(Line, '@@PROGRAMDATA@@', ProgramData, True);
    StringChangeEx(Line, '@@PROGRAMDATA_URI@@', ProgramDataUri, True);
    Lines[I] := Line;
  end;
  if not SaveStringsToFile(Dest, Lines, False) then
    Log('Falha ao gravar: ' + Dest)
  else
    DeleteFile(Src);
end;

procedure RunService(const Exe, Params: String);
var
  ResultCode: Integer;
begin
  if not FileExists(Exe) then
    Exit;
  Exec(Exe, Params, ExtractFilePath(Exe), SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Log(Exe + ' ' + Params + ' -> ' + IntToStr(ResultCode));
end;

procedure InstallAndStartService(const Exe: String);
begin
  RunService(Exe, 'stop');
  RunService(Exe, 'uninstall');
  RunService(Exe, 'install');
  RunService(Exe, 'start');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsComponentSelected('core') then
    begin
      ExpandServiceTemplate(
        ExpandConstant('{app}\core\SmartAcessoCore.xml.tpl'),
        ExpandConstant('{app}\core\SmartAcessoCore.xml'));
      InstallAndStartService(ExpandConstant('{app}\core\SmartAcessoCore.exe'));
    end;
    if WizardIsComponentSelected('topdata') then
    begin
      ExpandServiceTemplate(
        ExpandConstant('{app}\topdata\SmartAcessoTopData.xml.tpl'),
        ExpandConstant('{app}\topdata\SmartAcessoTopData.xml'));
      InstallAndStartService(ExpandConstant('{app}\topdata\SmartAcessoTopData.exe'));
    end;
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    RunService(ExpandConstant('{app}\topdata\SmartAcessoTopData.exe'), 'stop');
    RunService(ExpandConstant('{app}\topdata\SmartAcessoTopData.exe'), 'uninstall');
    RunService(ExpandConstant('{app}\core\SmartAcessoCore.exe'), 'stop');
    RunService(ExpandConstant('{app}\core\SmartAcessoCore.exe'), 'uninstall');
  end;
end;

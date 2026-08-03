; Script di configurazione Inno Setup per l'installer standalone di A.U.R.A. (Artificial Unbound Reasoning Arena)
#define MyAppName "A.U.R.A."
#define MyAppVersion "0.1.0"
#define MyAppPublisher "NatureWhisp"
#define MyAppURL "https://github.com/naturewhisp/aura"
#define MyAppExeName "aura_app.exe"

[Setup]
AppId={{D37E88A1-90B2-4A73-A882-C9F339891F84}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\AURA
DisableProgramGroupPage=yes
OutputBaseFilename=aura_setup_v{#MyAppVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\release\aura-v{#MyAppVersion}-win-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
// Verifica PID-based dell'ownership prima di procedere con l'installazione o la disinstallazione
function InitializeSetup(): Boolean;
var
  ErrorCode: Integer;
begin
  Result := True;
  // Se l'applicazione è in esecuzione, richiede all'utente la chiusura controllata
  if CheckForMutexes('AURA_APPLICATION_SINGLE_INSTANCE_MUTEX') then
  begin
    MsgBox('A.U.R.A. risulta attualmente in esecuzione. Si prega di chiudere l''applicazione prima di continuare con l''installazione.', mbInformation, MB_OK);
    Result := False;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if CheckForMutexes('AURA_APPLICATION_SINGLE_INSTANCE_MUTEX') then
  begin
    MsgBox('A.U.R.A. risulta in esecuzione. Si prega di chiudere l''applicazione prima di procedere con la disinstallazione.', mbCritical, MB_OK);
    Result := False;
  end;
end;

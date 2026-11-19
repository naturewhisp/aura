; Script di configurazione Inno Setup per l'installer standalone di A.U.R.A. (Artificial Unbound Reasoning Arena)
#ifndef MyAppVersion
#define MyAppVersion "0.1.0"
#endif

#define MyAppName "A.U.R.A."
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
AppMutex=AURA_APPLICATION_SINGLE_INSTANCE_MUTEX
DefaultDirName={autopf}\AURA
DisableProgramGroupPage=yes
OutputBaseFilename=aura_setup_v{#MyAppVersion}
OutputDir=..\release
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
// Controlla lo stato di esecuzione dell'applicazione A.U.R.A. e dei relativi processi nativi di inferenza posseduti
function CheckAuraRunning(): Boolean;
begin
  Result := CheckForMutexes('AURA_APPLICATION_SINGLE_INSTANCE_MUTEX');
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  if CheckAuraRunning() then
  begin
    MsgBox('A.U.R.A. o i relativi servizi di inferenza risultano attualmente in esecuzione.' + #13#10 +
           'Si prega di chiudere l''applicazione prima di continuare con l''installazione.', mbInformation, MB_OK);
    Result := False;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  if CheckAuraRunning() then
  begin
    MsgBox('A.U.R.A. risulta in esecuzione. Si prega di chiudere l''applicazione prima di procedere con la disinstallazione.', mbError, MB_OK);
    Result := False;
  end;
end;

// Disinstallazione selettiva: i dati utente restano di default (risposta predefinita NO,
// e nessuna rimozione in modalita' silenziosa). Viene rimosso solo cio' che A.U.R.A.
// gestisce direttamente: lo store dei modelli gestiti e i dati applicativi. I modelli GGUF
// esterni scelti dall'utente (anche se collocati in %LOCALAPPDATA%\AURA\staging) non
// vengono mai toccati.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ManagedStore: String;
  AppData: String;
begin
  if (CurUninstallStep <> usPostUninstall) or UninstallSilent() then
    Exit;

  ManagedStore := ExpandConstant('{localappdata}\AURA\store');
  AppData := ExpandConstant('{userappdata}\aura');

  if DirExists(ManagedStore) then
  begin
    if MsgBox('Rimuovere anche i modelli scaricati da A.U.R.A. e la configurazione del runtime?' + #13#10 +
              ManagedStore + #13#10#13#10 +
              'I modelli GGUF esterni selezionati manualmente non verranno eliminati.',
              mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(ManagedStore, True, True, True);
  end;

  if DirExists(AppData) then
  begin
    if MsgBox('Rimuovere anche salvataggi, replay delle partite, audio e preferenze?' + #13#10 +
              AppData + #13#10#13#10 +
              'Scegliendo No potrai ritrovarli reinstallando A.U.R.A.',
              mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      DelTree(AppData, True, True, True);
  end;
end;

; Inno Setup script for Meridian. Build with build_installer.ps1, which
; compiles the release app first and passes AppVersion from pubspec.yaml.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#define AppName "Meridian"
#define AppExe "meridian.exe"
; What 1.0.0 was called, so an upgrade can clear it away.
#define OldName "AOD World Map"
#define OldExe "aod_world_map.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{6B0E3F52-9C1A-4B7E-A8D2-3F5C7E1A9B40}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
; Per-user install: no UAC prompt, lands in %LOCALAPPDATA%\Programs.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\..\build\installer
OutputBaseFilename=Meridian-Setup-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; An upgrade from AOD World Map moves to the new folder and Start menu name.
UsePreviousAppDir=no
UsePreviousGroup=no
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup"; Description: "Start the island when I sign in to Windows"; GroupDescription: "Startup:"

[InstallDelete]
Type: filesandordirs; Name: "{autopf}\{#OldName}"
Type: filesandordirs; Name: "{autoprograms}\{#OldName}"
Type: files; Name: "{autodesktop}\{#OldName}.lnk"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{#AppName} Planner"; Filename: "{app}\{#AppExe}"; Parameters: "--home"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "{#OldName}"; Flags: deletevalue dontcreatekey
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExe}"" --island"; Flags: uninsdeletevalue; Tasks: startup

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

; Your planner, notes and settings in %APPDATA%\AodWorldMap are left in place
; on uninstall, so reinstalling picks up where you left off.

[Code]
// The app, island and overlay are all this exe (or the old one); stop every copy so files
// can be replaced or removed.
procedure StopApp();
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM {#AppExe} /IM {#OldExe}', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopApp();
  Result := '';
end;

function InitializeUninstall(): Boolean;
begin
  StopApp();
  Result := True;
end;

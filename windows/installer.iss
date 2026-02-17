; PingIT Inno Setup Script
; Generates a setup.exe installer for Windows

#define MyAppName "PingIT"
#define MyAppVersion "1.2.0"
#define MyAppPublisher "PingIT"
#define MyAppURL "https://github.com/cbl508/PingIT"
#define MyAppExeName "pingit.exe"

[Setup]
AppId={{B5E2F1A0-7C3D-4E8F-9A1B-2D4F6E8A0C3E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
OutputDir=..\build\installer
OutputBaseFilename=pingit-{#MyAppVersion}-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "installnmap"; Description: "Open Nmap download page (required for Deep Scan)"; GroupDescription: "Optional Dependencies:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\Uninstall {#MyAppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent
Filename: "https://nmap.org/download.html"; Description: "Download Nmap (for Deep Scan)"; Flags: nowait postinstall shellexec skipifsilent; Tasks: installnmap

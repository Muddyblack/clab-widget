; Windows installer for the CLAB Widget tray app (Inno Setup 6).
;
; Built by desktop/build-installer.ps1 from PyInstaller's "dist\CLAB Widget" folder
; (desktop/clab-widget.spec), in .github/workflows/desktop.yml — on every push, and
; for each release, which release.yml runs that workflow for.
;
; Per user: no admin rights, installed to %LOCALAPPDATA%\Programs\CLAB Widget.
; Settings, connections and tokens live in %USERPROFILE%\.config\clab-widget
; and %USERPROFILE%\.local\state\clab-widget and survive updates and uninstalls.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
; Never change the AppId: it is how Windows knows a new version is the same app
; and updates it in place.
AppId={{F3CAD95E-CF1E-4496-93D5-F72430C845A6}
AppName=CLAB Widget
AppVersion={#AppVersion}
AppVerName=CLAB Widget {#AppVersion}
AppPublisher=Muddyblack
AppPublisherURL=https://github.com/Muddyblack/clab-widget
AppSupportURL=https://github.com/Muddyblack/clab-widget/issues
DefaultDirName={autopf}\CLAB Widget
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..
OutputBaseFilename=CLAB-Widget-Setup-{#AppVersion}
SetupIconFile=..\dist\clab-widget.ico
UninstallDisplayIcon={app}\CLAB Widget.exe
UninstallDisplayName=CLAB Widget
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; The running app is stopped in [Code] instead of by the Restart Manager, which
; would ask the user about a tray app with no window to close.
CloseApplications=no

[Tasks]
; Offered on a first install only. On an update it would apply the choice
; remembered from that install, turning autostart back on for someone who had
; switched it off in the app since; left out, the Run value stays as it is.
Name: "autostart"; Description: "Start CLAB Widget when I sign in"; Check: not IsUpgrade
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\dist\CLAB Widget\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; An update replaces the whole bundle: files a new PyInstaller build no longer
; has must not linger next to the ones it does.
Type: filesandordirs; Name: "{app}\_internal"

[Icons]
Name: "{autoprograms}\CLAB Widget"; Filename: "{app}\CLAB Widget.exe"
Name: "{autodesktop}\CLAB Widget"; Filename: "{app}\CLAB Widget.exe"; Tasks: desktopicon

[Registry]
; Autostart at sign-in (the installer's task; the app has no switch of its own).
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "CLAB Widget"; ValueData: """{app}\CLAB Widget.exe"""; Tasks: autostart
; Removed on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: none; ValueName: "CLAB Widget"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\CLAB Widget.exe"; Description: "{cm:LaunchProgram,CLAB Widget}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM ""CLAB Widget.exe"""; Flags: runhidden; RunOnceId: "StopCLABWidget"

[Code]
var
  WasRunning: Boolean;

// An earlier install is there: its uninstaller is registered under AppId (with
// the doubled brace undone) plus "_is1". Keep the GUID in step with AppId.
function IsUpgrade: Boolean;
var
  Uninstaller: String;
begin
  Result := RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{F3CAD95E-CF1E-4496-93D5-F72430C845A6}_is1', 'UninstallString', Uninstaller);
end;

// Stop a running copy before its files are replaced. taskkill exits 0 when it
// stopped something and 128 when nothing was running.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  WasRunning := Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM "CLAB Widget.exe"', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
  Result := '';
end;

// A silent update (/SILENT, winget) skips the [Run] entry's checkbox, which
// would leave the tray app stopped until the next sign-in: start it again when
// it was running before.
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if (CurStep = ssPostInstall) and WizardSilent and WasRunning then
    ExecAsOriginalUser(ExpandConstant('{app}\CLAB Widget.exe'), '', '', SW_SHOWNORMAL, ewNoWait, ResultCode);
end;

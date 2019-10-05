program OfflineInstaller;

uses
  System.StartUpCopy,
  FMX.Forms,
  OfflineInstallMainFrm in 'OfflineInstallMainFrm.pas' {OfflineInstallMainForm},
  StyleModuleUnit in 'StyleModuleUnit.pas' {StyleDataModule: TDataModule};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TStyleDataModule, StyleDataModule);
  Application.CreateForm(TOfflineInstallMainForm, OfflineInstallMainForm);
  Application.Run;
end.

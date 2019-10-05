unit OfflineInstallMainFrm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.ScrollBox, FMX.Memo, FMX.StdCtrls, FMX.Edit, FMX.Controls.Presentation,
  FMX.Layouts, FMX.ListBox,

  System.IOUtils,

  Winapi.Windows, Winapi.ShellAPI,
  System.Win.ComObj, Winapi.ActiveX, Winapi.ShlObj,
  System.Win.Registry,

  CoreClasses,
  PascalStrings,
  UnicodeMixedLib,
  MemoryStream64,
  DoStatusIO,
  CoreCipher,
  DataFrameEngine,
  ListEngine,
  ObjectData,
  ObjectDataManager,
  FileIndexPackage;

type
  TOfflineInstallMainForm = class(TForm)
    InstallButton: TButton;
    InstallPathLayout: TLayout;
    Label2: TLabel;
    InstallPathEdit: TEdit;
    BrowseIntallPathButton: TEditButton;
    fpsTimer: TTimer;
    ListBox: TListBox;
    InstallIconButton: TButton;
    UnInstallIconButton: TButton;
    ProductNameLabel: TLabel;
    installerURLLabel: TLabel;
    procedure BrowseIntallPathButtonClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure fpsTimerTimer(Sender: TObject);
    procedure installerURLLabelClick(Sender: TObject);
    procedure InstallButtonClick(Sender: TObject);
    procedure InstallIconButtonClick(Sender: TObject);
    procedure UnInstallIconButtonClick(Sender: TObject);
  private
    procedure DoInstallRun(thSender: TComputeThread);
    procedure DoStatusMethod(AText: SystemString; const ID: Integer);
  public
    procedure DisableAll;
    procedure EnabledAll;
  end;

var
  OfflineInstallMainForm: TOfflineInstallMainForm;

const
  ProductID = 'MyProduct';      // 产品ID，这也是默认安装目录名
  ProductName = 'Product Name'; // 产品名称

  // 展开安装程序包到硬盘的目标目录
function OpenInstallPackage(fileName: U_String): TObjectDataManager;
procedure ExtractInstallerPackage(packageFile, SavePath: U_String);
// 构建windows的桌面快捷方式，在安装结束时使用
procedure BuildShellLinkToDesktop(const fileName, workDirectory, shortCutName: WideString);
// 构建windows的程序文件夹快捷方式，在安装结束时使用
procedure BuildShellLinkToProgram(const fileName, workDirectory, shortCutName: WideString);
// 构建windows的开机自动启动文件夹快捷方式，在安装结束时使用
procedure BuildShellLinkToStartup(const fileName, workDirectory, param, shortCutName: WideString);
// shell运行程序，在安装中使用
procedure ShellRun(ExeFile, param: U_String);

implementation

{$R *.fmx}


uses StyleModuleUnit;

function OpenInstallPackage(fileName: U_String): TObjectDataManager;
var
  fs: TCoreClassFileStream;
  m64, stream: TMemoryStream64;
begin
  DoStatus('Prepare %s...', [umlGetFileName(fileName).Text]);
  if umlMultipleMatch('*.OXC', umlGetFileName(fileName)) then
    begin
      // oxc的解压缩方式会先解压到内存，再从内存将文件复制到硬盘
      fs := TCoreClassFileStream.Create(fileName, fmOpenRead or fmShareDenyWrite);
      stream := TMemoryStream64.Create;
      DecompressStream(fs, stream);
      DoStatus('Decompression %s %s -> %s', [umlGetFileName(fileName).Text, umlSizeToStr(fs.Size).Text, umlSizeToStr(stream.Size).Text]);
      disposeObject(fs);
      stream.Position := 0;
      Result := TObjectDataManagerOfCache.CreateAsStream(stream, '', DBMarshal.ID, true, False, true);
    end
  else if umlMultipleMatch('*.OXP', umlGetFileName(fileName)) then
    begin
      // oxp的解压缩方式会先解压到内存，再从内存将文件复制到硬盘
      fs := TCoreClassFileStream.Create(fileName, fmOpenRead or fmShareDenyWrite);
      stream := TMemoryStream64.Create;
      ParallelDecompressStream(fs, stream);
      DoStatus('Parallel Decompression %s %s -> %s', [umlGetFileName(fileName).Text, umlSizeToStr(fs.Size).Text, umlSizeToStr(stream.Size).Text]);
      disposeObject(fs);
      stream.Position := 0;
      Result := TObjectDataManagerOfCache.CreateAsStream(stream, '', DBMarshal.ID, true, False, true);
    end
  else
    begin
      // ox会直接将文件复制到硬盘，不经过内存转码
      fs := TCoreClassFileStream.Create(fileName, fmOpenRead or fmShareDenyWrite);
      Result := TObjectDataManagerOfCache.CreateAsStream(fs, '', DBMarshal.ID, true, False, true);
    end;
end;

procedure ExtractInstallerPackage(packageFile, SavePath: U_String);
var
  dbEng: TObjectDataManager;
  sr: TItemRecursionSearch;
  savePh: U_String;
  i: Integer;
  n, fn: U_String;
  itmHnd: TItemHandle;
  fs: TCoreClassFileStream;
  c: Integer;
begin
  dbEng := OpenInstallPackage(packageFile);
  DoStatus('install %s...', [umlGetFileName(packageFile).Text]);
  c := 0;
  if dbEng.RecursionSearchFirst('/', '*', sr) then
    begin
      repeat
        if sr.ReturnHeader.ID = DB_Header_Item_ID then
          begin
            savePh := umlCombinePath(SavePath, dbEng.GetFieldPath(sr.CurrentField.RHeader.CurrentHeader));
            umlCreateDirectory(savePh);
            fn := umlCombineFileName(savePh, sr.ReturnHeader.Name);
            try
              fs := TCoreClassFileStream.Create(fn, fmCreate);
              dbEng.ItemFastOpen(sr.ReturnHeader.CurrentHeader, itmHnd);
              dbEng.ItemReadToStream(itmHnd, fs);
              disposeObject(fs);
              umlSetFileTime(fn, itmHnd.CreateTime);
              dbEng.ItemClose(itmHnd);
              inc(c);
            except
                DoStatus('install Warning: %s is opened by other program.', [fn.Text]);
            end;
          end;
      until not dbEng.RecursionSearchNext(sr);
    end;
  disposeObject(dbEng);
  DoStatus('%s total installed files: %d', [umlGetFileName(packageFile).Text, c]);
end;

procedure BuildShellLinkToDesktop(const fileName, workDirectory, shortCutName: WideString);
var
  AnObj: IUnknown;
  ShLink: IShellLink;
  PFile: IPersistFile;
  WFileName: WideString;
  Reg: TRegIniFile;
begin
  AnObj := CreateComObject(CLSID_ShellLink);
  ShLink := AnObj as IShellLink;
  PFile := AnObj as IPersistFile;
  ShLink.SetPath(PWideChar(fileName));
  ShLink.SetWorkingDirectory(PWideChar(workDirectory));
  Reg := TRegIniFile.Create('Software\MicroSoft\Windows\CurrentVersion\Explorer');
  WFileName := Reg.ReadString('Shell Folders', 'Desktop', '') + '\' + shortCutName + '.lnk';
  Reg.Free;
  PFile.Save(PWideChar(WFileName), False);
  DoStatus('create shortcut: %s', [WFileName]);
  AnObj := nil;
end;

procedure BuildShellLinkToProgram(const fileName, workDirectory, shortCutName: WideString);
var
  AnObj: IUnknown;
  ShLink: IShellLink;
  PFile: IPersistFile;
  WFileName: WideString;
  Reg: TRegIniFile;
begin
  AnObj := CreateComObject(CLSID_ShellLink);
  ShLink := AnObj as IShellLink;
  PFile := AnObj as IPersistFile;
  ShLink.SetPath(PWideChar(fileName));
  ShLink.SetWorkingDirectory(PWideChar(workDirectory));
  Reg := TRegIniFile.Create('Software\MicroSoft\Windows\CurrentVersion\Explorer');
  WFileName := Reg.ReadString('Shell Folders', 'Programs', '') + '\' + shortCutName + '.lnk';
  Reg.Free;
  PFile.Save(PWideChar(WFileName), False);
  DoStatus('create shortcut: %s', [WFileName]);
  AnObj := nil;
end;

procedure BuildShellLinkToStartup(const fileName, workDirectory, param, shortCutName: WideString);
var
  AnObj: IUnknown;
  ShLink: IShellLink;
  PFile: IPersistFile;
  WFileName: WideString;
  Reg: TRegIniFile;
begin
  AnObj := CreateComObject(CLSID_ShellLink);
  ShLink := AnObj as IShellLink;
  PFile := AnObj as IPersistFile;
  ShLink.SetPath(PWideChar(fileName));
  ShLink.SetWorkingDirectory(PWideChar(workDirectory));
  ShLink.SetArguments(PWideChar(param));
  Reg := TRegIniFile.Create('Software\MicroSoft\Windows\CurrentVersion\Explorer');
  WFileName := Reg.ReadString('Shell Folders', 'Startup', '') + '\' + shortCutName + '.lnk';
  Reg.Free;
  PFile.Save(PWideChar(WFileName), False);
  DoStatus('create shortcut: %s', [WFileName]);
  AnObj := nil;
end;

procedure ShellRun(ExeFile, param: U_String);
begin
  ShellExecute(0, 'Open',
    PWideChar(ExeFile.Text),
    PWideChar(param.Text),
    PWideChar(umlGetFilePath(ExeFile).Text),
    SW_SHOW);
end;

procedure TOfflineInstallMainForm.BrowseIntallPathButtonClick(Sender: TObject);
var
  d: string;
begin
  d := InstallPathEdit.Text;
  if SelectDirectory('install directory', d, d) then
      InstallPathEdit.Text := d;
end;

procedure TOfflineInstallMainForm.FormCreate(Sender: TObject);
var
  s: TMemoryStream64;
begin
  AddDoStatusHook(Self, DoStatusMethod);

  Caption := Format(Caption, [ProductName]);
  ProductNameLabel.Text := ProductName;

  InstallPathEdit.Text := umlCombinePath(TPath.GetLibraryPath, ProductID);

  TComputeThread.RunP(procedure(thSender: TComputeThread)
    begin
      TThread.Synchronize(thSender, procedure
        begin
          // 这里可以执行一些安装程序启动时的初始化程序
        end);
    end);
end;

procedure TOfflineInstallMainForm.fpsTimerTimer(Sender: TObject);
begin
  DoStatus;
end;

procedure TOfflineInstallMainForm.installerURLLabelClick(Sender: TObject);
begin
  ShellRun(TLabel(Sender).Text, '');
end;

procedure TOfflineInstallMainForm.InstallButtonClick(Sender: TObject);
var
  i: Integer;
  n: U_String;
  li: TListBoxItem;
  FileList: TPascalStringList;
begin
  DisableAll;
  FileList := TPascalStringList.Create;
  FileList.LoadFromFile(umlCombineFileName(TPath.GetLibraryPath, 'installer.conf'));
  if (FileList <> nil) and (FileList.Count > 0) then
    begin
      // 检查安装包的正确性
      for i := 0 to FileList.Count - 1 do
        begin
          if not umlFileExists(umlCombineFileName(TPath.GetLibraryPath, FileList[i])) then
            begin
              DoStatus('Loss of Installation Pack: %s', [FileList[i].Text]);
              DoStatus('');
              disposeObject(FileList);
              EnabledAll;
              Exit;
            end;
        end;

      umlCreateDirectory(InstallPathEdit.Text);

      // 开始在后台线程中运行安装程序
      TComputeThread.RunM(nil, FileList, DoInstallRun);

      DoStatus('all done.');
    end;
end;

procedure TOfflineInstallMainForm.InstallIconButtonClick(Sender: TObject);
begin
  // 在这里实现windows快捷方式构建
  // 使用下列API即可
  (*
    procedure BuildShellLinkToDesktop(const fileName, workDirectory, shortCutName: WideString);
    procedure BuildShellLinkToProgram(const fileName, workDirectory, shortCutName: WideString);
    procedure BuildShellLinkToStartup(const fileName, workDirectory, param, shortCutName: WideString);
  *)
end;

procedure TOfflineInstallMainForm.UnInstallIconButtonClick(Sender: TObject);
begin
  // 这里将windows快捷方式文件删除
  // 直接使用API umlDeleteFile(快捷方式文件名)
end;

procedure TOfflineInstallMainForm.DoInstallRun(thSender: TComputeThread);
var
  i: Integer;
  n: U_String;
  FileList: TPascalStringList;
begin
  FileList := TPascalStringList(thSender.UserObject);
  // 逐个展开安装包
  for i := 0 to FileList.Count - 1 do
    begin
      n := umlCombineFileName(TPath.GetLibraryPath, FileList[i]);
      ExtractInstallerPackage(n, InstallPathEdit.Text);
    end;

  TThread.Synchronize(thSender, procedure
    begin
      // 安装程序完成时干的事情
      EnabledAll;
    end);
  disposeObject(FileList);
end;

procedure TOfflineInstallMainForm.DoStatusMethod(AText: SystemString; const ID: Integer);
var
  li: TListBoxItem;
begin
  li := TListBoxItem.Create(ListBox);
  li.Selectable := False;
  ListBox.AddObject(li);
  li.Text := AText;
  ListBox.ScrollToItem(li);
end;

procedure TOfflineInstallMainForm.DisableAll;
begin
  InstallButton.Enabled := False;
  InstallPathEdit.Enabled := False;

  InstallIconButton.Visible := False;
  UnInstallIconButton.Visible := False;
end;

procedure TOfflineInstallMainForm.EnabledAll;
begin
  InstallButton.Enabled := true;
  InstallPathEdit.Enabled := true;

  InstallIconButton.Visible := true;
  UnInstallIconButton.Visible := true;
end;

end.

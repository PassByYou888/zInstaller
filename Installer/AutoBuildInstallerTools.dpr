program AutoBuildInstallerTools;

{$APPTYPE CONSOLE}

{$R *.res}

{
  自动化打包程序，如果需要安装发行的文件很多，可以使用这种方式进行压缩打包
  使用方法，将AutoBuildInstallerTools.exe复制到需要打包的根目录，运行后即可完成打包
  如果打包的文件系统过于庞大，会出现内存不够用，使用x64构建即可
}

uses
  SysUtils,
  IOUtils,
  CoreClasses,
  PascalStrings,
  UnicodeMixedLib,
  CoreCipher,
  MemoryStream64,
  DoStatusIO,
  ListEngine,
  ObjectDataManager, ItemStream;

// 将一个目录批量的导入成ZDB的数据格式
// 与传统导入不同的地方是，这一步导入会将数据自动切割成小文件
procedure ImportToDB(ADirectory, SaveToFile, DBRoot: U_String; splitSiz: Int64);
var
  dbEng: TObjectDataManager;
  FastMode: Boolean;

  procedure ImpFromPath(ImpPath, DBPath: U_String);
  var
    fAry: U_StringArray;
    n: U_SystemString;
    fPos: Int64;
    fs: TCoreClassFileStream;
    itmHnd: TItemHandle;
    itmStream: TItemStream;
  begin
    DBPath := umlCharReplace(DBPath, '\', '/');
    if not dbEng.DirectoryExists(DBPath) then
        dbEng.CreateField(DBPath, '');
    fPos := dbEng.GetPathFieldPos(DBPath);

    Writeln(Format('import %s', [DBPath.Text]));

    fAry := umlGetFileListWithFullPath(ImpPath);
    for n in fAry do
      begin
        fs := TCoreClassFileStream.Create(n, fmOpenRead or fmShareDenyWrite);
        if FastMode then
            dbEng.ItemFastCreate(fPos, umlGetFileName(n), '', itmHnd)
        else
            dbEng.ItemCreate(DBPath, umlGetFileName(n), '', itmHnd);
        itmStream := TItemStream.Create(dbEng, itmHnd);
        try
            itmStream.CopyFrom(fs, fs.Size)
        except
        end;
        itmStream.CloseHandle;
        DisposeObject(fs);
        DisposeObject(itmStream);
      end;

    fAry := umlGetDirListWithFullPath(ImpPath);
    for n in fAry do
        ImpFromPath(n, umlCombinePath(DBPath, umlGetLastStr(n, '\/')));
  end;

begin
  FastMode := True;
  dbEng := TObjectDataManagerOfCache.CreateNew($FF, umlChangeFileExt(SaveToFile, '.tmp'), DBMarshal.ID);
  dbEng.OverWriteItem := False;
  ImpFromPath(ADirectory, DBRoot);
  dbEng.UpdateIO;
  dbEng.SplitToParallelCompression('/', SaveToFile, splitSiz);
  DisposeObject(dbEng);
  umlDeleteFile(umlChangeFileExt(SaveToFile, '.tmp'));
  Writeln('all import ok!');
end;

// 将根目录以多线程方式切割成小数据包，并且使用并行化方式进行压缩
procedure run(rootPh: U_String);
var
  dArry: U_StringArray;
  i: Integer;
  waitTh: Integer;

  fArry: U_StringArray;
  m64: TMemoryStream64;

  conf: TPascalStringList;
begin
  dArry := umlGetDirListPath(rootPh);

  waitTh := 0;
  for i := 0 to High(dArry) do
    begin
      AtomInc(waitTh);
      TComputeThread.RunP(@dArry[i], nil, procedure(thSender: TComputeThread)
        var
          p: PSystemString;
        begin
          p := thSender.UserData;
          ImportToDB(umlCombinePath(rootPh, p^), umlCombineFileName(rootPh, p^ + '.OXP'), p^,
            100 * 1024 * 1024 // 每个切割包的大小为100M
            );
          AtomDec(waitTh);
        end);
    end;

  // 等待并行化压缩结束
  while waitTh > 0 do
      CoreClasses.CheckThreadSynchronize(100);

  // 生成安装包配置
  fArry := umlGetFileListPath(rootPh);
  conf := TPascalStringList.Create;
  for i := Low(fArry) to high(fArry) do
    begin
      if umlMultipleMatch('*.oxp', fArry[i]) then
          conf.Add(fArry[i]);
    end;
  conf.SaveToFile(umlCombineFileName(rootPh, 'installer.conf'));
  SetLength(fArry, 0);
  DisposeObject(conf);
end;

begin
  run(TPath.GetLibraryPath);

end.

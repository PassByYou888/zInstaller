program AutoBuildInstallerTools;

{$APPTYPE CONSOLE}

{$R *.res}

{
  �Զ���������������Ҫ��װ���е��ļ��ܶ࣬����ʹ�����ַ�ʽ����ѹ�����
  ʹ�÷�������AutoBuildInstallerTools.exe���Ƶ���Ҫ����ĸ�Ŀ¼�����к󼴿���ɴ��
  ���������ļ�ϵͳ�����Ӵ󣬻�����ڴ治���ã�ʹ��x64��������
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

// ��һ��Ŀ¼�����ĵ����ZDB�����ݸ�ʽ
// �봫ͳ���벻ͬ�ĵط��ǣ���һ������Ὣ�����Զ��и��С�ļ�
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

// ����Ŀ¼�Զ��̷߳�ʽ�и��С���ݰ�������ʹ�ò��л���ʽ����ѹ��
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
            100 * 1024 * 1024 // ÿ���и���Ĵ�СΪ100M
            );
          AtomDec(waitTh);
        end);
    end;

  // �ȴ����л�ѹ������
  while waitTh > 0 do
      CoreClasses.CheckThreadSynchronize(100);

  // ���ɰ�װ������
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

program Make;
{$mode objfpc}{$H+}

uses
  Classes,
  SysUtils,
  StrUtils,
  FileUtil,
  Zipper,
  fphttpclient,
  RegExpr,
  openssl,
  opensslsockets,
  Process;

const
  Target: string = 'src';
  Dependencies: array of string = ();

type
  Output = record
    Code: boolean;
    Output: ansistring;
  end;

  function CheckModules: Output;
  begin
    if FileExists('.gitmodules') then
      if RunCommand('git', ['submodule', 'update', '--init', '--recursive',
        '--force', '--remote'], Result.Output) then
        Writeln(stderr, #27'[33m', Result.Output, #27'[0m');
  end;

  function AddPackage(Path: string): Output;
  begin
    with TRegExpr.Create do
    begin
      Expression :=
        {$IFDEF MSWINDOWS}
        '(cocoa|x11|_template)'
      {$ELSE}
        '(cocoa|gdi|_template)'
      {$ENDIF}
      ;
      if not Exec(Path) and RunCommand('lazbuild', ['--add-package-link', Path],
        Result.Output) then
        Writeln(stderr, #27'[33m', 'added ', Path, #27'[0m');
      Free;
    end;
  end;

  function BuildProject(Path: string): Output;
  var
    Line: string;
  begin
    Write(stderr, #27'[33m', 'build from ', Path, #27'[0m');
    try
      Result.Code := RunCommand('lazbuild', ['--build-all', '--recursive',
        '--no-write-project', Path], Result.Output);
      if Result.Code then
        for Line in SplitString(Result.Output, LineEnding) do
        begin
          if ContainsStr(Line, 'Linking') then
          begin
            Result.Output := SplitString(Line, ' ')[2];
            Writeln(stderr, #27'[32m', ' to ', Result.Output, #27'[0m');
            break;
          end;
        end
      else
      begin
        ExitCode += 1;
        for Line in SplitString(Result.Output, LineEnding) do
          with TRegExpr.Create do
          begin
            Expression := '(Fatal|Error):';
            if Exec(Line) then
            begin
              WriteLn(stderr);
              Writeln(stderr, #27'[31m', Line, #27'[0m');
            end;
            Free;
          end;
      end;
    except
      on E: Exception do
        WriteLn(stderr, 'Error: ' + E.ClassName + #13#10 + E.Message);
    end;
  end;

  function RunTest(Path: string): Output;
  var
    Temp: string;
  begin
    Result := BuildProject(Path);
    Temp:= Result.Output;
    if Result.Code then
        try
          if not RunCommand(Temp, ['--all', '--format=plain', '--progress'], Result.Output) then
            ExitCode += 1;
          WriteLn(stderr, Result.Output);
        except
          on E: Exception do
            WriteLn(stderr, 'Error: ' + E.ClassName + #13#10 + E.Message);
        end;
  end;

  function DownloadFile(Url: string): string;
  var
    TempFile: TStream;
  begin
      Result := GetTempFileName;
      with TFPHttpClient.Create(nil) do
      begin
        try
          AddHeader('User-Agent', 'Mozilla/5.0 (compatible; fpweb)');
          AllowRedirect := True;
          TempFile := TFileStream.Create(Result, fmCreate or fmOpenWrite);
          Get(Url, TempFile);
          TempFile.Free;
          WriteLn(stderr, 'Download from ', Url, ' to ', Result);
        finally
          Free;
        end;
      end;
  end;

  function AddOPM(Each: string): string;
  begin
    Result :=
      {$IFDEF MSWINDOWS}
      GetEnvironmentVariable('APPDATA') + '\.lazarus\onlinepackagemanager\packages\'
      {$ELSE}
      GetEnvironmentVariable('HOME') + '/.lazarus/onlinepackagemanager/packages/'
      {$ENDIF}
      + Each;
    if not DirectoryExists(Result) then
    begin
      CreateDir(Result);
      with TUnZipper.Create do
      begin
        try
          FileName := DownloadFile('https://packages.lazarus-ide.org/' + Each + '.zip');
          OutputPath := Result;
          Examine;
          UnZipAllFiles;
          WriteLn(stderr, 'Unzip from ', FileName, ' to ', Result);
          DeleteFile(FileName);
        finally
          Free;
        end;
      end;
    end;
  end;

  function Main: Output;
  var
    Each, Item: string;
    List: TStringList;
  begin
    CheckModules;
    InitSSLInterface;
    for Each in Dependencies do
    begin
      List := FindAllFiles(AddOPM(Each), '*.lpk', True);
      try
        for Item in List do
          AddPackage(Item);
      finally
        List.Free;
      end;
    end;
    List := FindAllFiles('.', '*.lpk', True);
    try
      for Each in List do
        AddPackage(Each);
    finally
      List.Free;
    end;
    List := FindAllFiles(Target, '*.lpi', True);
    try
      for Each in List do
        if ContainsStr(ReadFileToString(ReplaceStr(Each, '.lpi', '.lpr')),
          'consoletestrunner') then
          RunTest(Each)
        else
          BuildProject(Each);
    finally
      List.Free;
    end;
    WriteLn(stderr);
    if ExitCode <> 0 then
      WriteLn(stderr, #27'[31m', 'Errors: ', ExitCode, #27'[0m')
    else
      WriteLn(stderr, #27'[32m', 'Errors: ', ExitCode, #27'[0m');
  end;

begin
  Main;
end.

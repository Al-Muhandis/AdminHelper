program Make;
{$mode objfpc}{$H+}

uses
  Classes,
  SysUtils,
  StrUtils,
  FileUtil,
  fphttpclient,
  openssl,
  opensslsockets,
  Process;

const
  Src = 'src';
  Use = 'use';

var
  Client: TFPHttpClient;
  Output, Line, LPI: ansistring;
  Files: TStringList;
  Each: String;

begin
  if FileExists('.gitmodules') then
    if RunCommand('git', ['submodule', 'update', '--init', '--recursive',
      '--force', '--remote'], Output) then
      Writeln(#27'[32m', Output, #27'[0m')
    else
      Writeln(#27'[31m', Output, #27'[0m');
  Files := FindAllFiles(Use, '*.lpk', True);
  try
    for Each in Files do
      if RunCommand('lazbuild', ['--add-package-link', Each], Output) then
        Writeln(#27'[32m', 'added ', Each, #27'[0m')
      else
        Writeln(#27'[31m', 'added ', Each, #27'[0m');
  finally
    Files.Free;
  end;
  Files := FindAllFiles(Src, '*.lpi', True);
  try
    for Each in Files do
      Writeln(#27'[33m', 'build ', Each, #27'[0m');
      if RunCommand('lazbuild', ['--build-all', '--recursive',
        '--no-write-project', Each], Output) then
      begin
        for Line in SplitString(Output, LineEnding) do
        begin
          if Pos('Linking', Line) <> 0 then
            Writeln(#27'[32m', Line, #27'[0m');
        end;
      end
      else
      begin
        for Line in SplitString(Output, LineEnding) do
        begin
          if Pos('Fatal', Line) <> 0 and Pos('Error', Line) then
            Writeln(#27'[31m', Line, #27'[0m');
        end;
      end;
  finally
    Files.Free;
  end;
end.

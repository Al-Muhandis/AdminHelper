program test_runner_integration;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner, fpcunittestinsight,
  test.orm_live
  ;

type

  { TMyTestRunner }

  TMyTestRunner = class(TTestRunner)
  protected
  // override the protected methods of TTestRunner to customize its behavior
  end;

var
  Application: TMyTestRunner;

begin
  if IsTestInsightListening() then
    RunRegisteredTests('','')
  else
    begin
    DefaultRunAllTests:=True;
    DefaultFormat:=fPlain;
    Application := TMyTestRunner.Create(nil);
    Application.Initialize;
    Application.Title := 'AdminHelper Integration Tests';
    Application.Run;
    Application.Free;
    end;
end.

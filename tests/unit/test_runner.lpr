program test_runner;

{$mode objfpc}{$H+}

uses
  Classes, consoletestrunner, fpcunittestinsight,
  test.schema_entities, test.orm_errors, test.telegram_routes, test.defender_status
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
    Application.Title := 'AdminHelper Unit Tests';
    Application.Run;
    Application.Free;
    end;
end.

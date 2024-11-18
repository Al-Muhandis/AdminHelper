program adminhelperd;

{$mode objfpc}{$H+}

{$DEFINE THREADED}

uses
{$IF DEFINED(UNIX) AND DEFINED(THREADED)}
  CThreads,
{$ENDIF}
  Interfaces, BrookApplication, BrookTardigradeBroker, actionadminhelper, adminhelper_conf, brokers
  ;

{$R *.res}

begin
  {$IFDEF THREADED}
  Application.Server.Threaded := True;
  {$ENDIF}
  Application.Server.ConnectionLimit:=1000;
  Application.Initialize;
  Application.Run;
end.

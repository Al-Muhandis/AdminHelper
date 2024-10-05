program tgadminhelperd;

{$mode objfpc}{$H+}

{$DEFINE THREADED}

uses
{$IF DEFINED(UNIX) AND DEFINED(THREADED)}
  CThreads,
{$ENDIF}
  Interfaces, BrookApplication, BrookTardigradeBroker,
  brk_tg_config, actionadminhelper, adminhelper_conf
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

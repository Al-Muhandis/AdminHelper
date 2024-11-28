program adminhelperd;

{$mode objfpc}{$H+}

{$DEFINE THREADED}

uses
{$IF DEFINED(UNIX) AND DEFINED(THREADED)}
  CThreads,
{$ENDIF}
  Interfaces, BrookApplication, BrookTardigradeBroker, actionadminhelper, adminhelper_conf, brokers,
  spamfilter_implementer, telegram_cmn
  ;

{$R *.res}

begin
  {$IFDEF THREADED}
  Application.Server.Threaded := True;
  {$ENDIF}
  Application.Server.ConnectionLimit:=1000;             
  Application.Server.OnStart:=@(TSpamFilterRunner.ServerStart);
  Application.Server.OnStop:=@(TSpamFilterRunner.ServerStop);
  Application.Initialize;
  Application.Run;
end.

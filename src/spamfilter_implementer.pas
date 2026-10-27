unit spamfilter_implementer;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, eventlog, spamfilter_worker
  ;

type

  { TSpamFilterRunner }

  TSpamFilterRunner = class
  public
    class procedure ServerStart({%H-}Sender: TObject);
    class procedure ServerStop({%H-}Sender: TObject);
  end;

var
  _SpamFilterWorker: TSpamFilterThread = nil;

implementation

uses
  adminhelper_conf, global
  ;

{ TSpamFilterRunner }

class procedure TSpamFilterRunner.ServerStart(Sender: TObject);
var
  aLog: TEventLog;
begin
  _SpamFilterWorker:=TSpamFilterThread.Create;
  _SpamFilterWorker.Start;
  _SpamFilterWorker.Logger.Debug('Worker started');
  _SpamFilterWorker.Load;
  _SpamFilterWorker.Logger.Debug('Base loaded');
  { The per-request bot logger creates its file lazily on the first record:
    with debug off the file could stay absent for days, hiding the service
    state; touch it at every start }
  aLog:=TEventLog.Create(nil);
  try
    aLog.LogType:=ltFile;
    aLog.AppendContent:=True;
    aLog.FileName:=_LogDir+Conf.AdminHelperBot.Telegram.UserName+'.log';
    aLog.Info(Format('Server started, built %s %s, debug=%s', [{$I %DATE%}, {$I %TIME%}, BoolToStr(Conf.Debug.Enabled or Conf.AdminHelperBot.Debug, True)]));
  finally
    aLog.Free;
  end;
end;

class procedure TSpamFilterRunner.ServerStop(Sender: TObject);
begin
  { Terminate the worker first, then save synchronously: a queued save task
    is dropped by the worker's task cleanup on termination }
  _SpamFilterWorker.TerminateWorker;
  _SpamFilterWorker.WaitFor;
  _SpamFilterWorker.SaveBase;
  FreeAndNil(_SpamFilterWorker);
end;

end.


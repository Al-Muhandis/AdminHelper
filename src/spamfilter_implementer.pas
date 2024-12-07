unit spamfilter_implementer;

{$mode ObjFPC}{$H+}

interface

uses
  SysUtils, spamfilter_worker
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

{ TSpamFilterRunner }

class procedure TSpamFilterRunner.ServerStart(Sender: TObject);
begin
  _SpamFilterWorker:=TSpamFilterThread.Create;
  _SpamFilterWorker.Start;
  _SpamFilterWorker.Logger.Debug('Worker started');
  _SpamFilterWorker.Load;                          
  _SpamFilterWorker.Logger.Debug('Base loaded');
end;

class procedure TSpamFilterRunner.ServerStop(Sender: TObject);
begin 
  _SpamFilterWorker.Save;
  _SpamFilterWorker.TerminateWorker;
  FreeAndNil(_SpamFilterWorker);
end;

end.


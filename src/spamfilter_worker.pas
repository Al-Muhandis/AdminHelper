unit spamfilter_worker;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, taskworker, spamfilter, tgsendertypes, tgtypes, telegram_cmn
  ;

type

  TFilterTaskCommand = (ftcNone, ftcTrain, ftcClassify, ftcLoad, ftcSave);

  { TSpamFilterTask }

  TSpamFilterTask = class
  private
    FBot: TTelegramSender;
    FCurrent: TCurrentEvent;
    FIsSpam: Boolean;
    FTaskCommand: TFilterTaskCommand;
    function GetCurrent: TCurrentEvent;
    procedure SetCurrent(AValue: TCurrentEvent);
  protected
    procedure Assign(aSrc: TCurrentEvent);
    property Current: TCurrentEvent read GetCurrent write SetCurrent;
    property Bot: TTelegramSender read FBot;
  public
    constructor Create(aTaskCommand: TFilterTaskCommand; aCurrentEvent: TCurrentEvent=nil; aIsSpam: Boolean = False);
    destructor Destroy; override;
    procedure ProcessTask(aSpamFilter: TSpamFilter);
    property IsSpam: Boolean read FIsSpam write FIsSpam;
    property TaskCommand: TFilterTaskCommand read FTaskCommand;
  end;

  TCustomSpamFilterThread = specialize TgTaskWorkerThread<TSpamFilterTask>;

  { TSpamFilterThread }

  TSpamFilterThread = class(TCustomSpamFilterThread)
  private
    FSpamFilter: TSpamFilter;
  protected
    procedure ProcessTask(aTask: TSpamFilterTask); override;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Classify(aCurrentEvent: TCurrentEvent);
    procedure Load;              
    procedure Save;
    procedure Train(aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
  end;

implementation

uses
  adminhelper_conf, eventlog
  ;

{ TSpamFilterTask }

function TSpamFilterTask.GetCurrent: TCurrentEvent;
begin
  if not Assigned(FCurrent) then
  begin
    FCurrent:=TCurrentEvent.Create(Bot);
    FCurrent.LogPrefix:='Task_';
  end;
  Result:=FCurrent;
end;

procedure TSpamFilterTask.SetCurrent(AValue: TCurrentEvent);
begin
  if AValue=nil then
    FreeAndNil(FCurrent)
  else begin
    Current.Complainant:=AValue.Complainant;
    Current.InspectedChat:=AValue.InspectedChat;
    Current.InspectedMessage:=AValue.InspectedMessage;
    Current.InspectedMessageID:=AValue.InspectedMessageID;
    Current.InspectedUser:=AValue.InspectedUser;
  end;
end;

procedure TSpamFilterTask.Assign(aSrc: TCurrentEvent);
begin
  if not Assigned(aSrc) then
  begin
    Current.Complainant:=       nil;
    Current.InspectedChat:=     nil;
    Current.InspectedUser:=     nil;
    Current.InspectedMessage:=  EmptyStr;
    Current.InspectedMessageID:=0;
    Exit;
  end;
  if Assigned(aSrc.Complainant) then
    Current.Complainant:=aSrc.Complainant.Clone
  else
    Current.Complainant:=nil;
  if Assigned(aSrc.InspectedChat) then
    Current.InspectedChat:=aSrc.InspectedChat.Clone
  else
    Current.InspectedChat:=nil;       
  if Assigned(aSrc.InspectedUser) then
    Current.InspectedUser:=aSrc.InspectedUser.Clone
  else
    Current.InspectedUser:=nil;
  Current.InspectedMessage:=  aSrc.InspectedMessage;
  Current.InspectedMessageID:=aSrc.InspectedMessageID;
end;

constructor TSpamFilterTask.Create(aTaskCommand: TFilterTaskCommand; aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
begin
  FBot:=TTelegramSender.Create(Conf.AdminHelperBot.Telegram.Token);
  FBot.BotUsername:=Conf.AdminHelperBot.Telegram.UserName;
  FBot.Logger:=TEventLog.Create(nil);
  FBot.Logger.LogType:=ltFile;
  FBot.Logger.AppendContent:=True;
  FBot.Logger.FileName:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)))+'Task_spamfilter.log';
  FBot.LogDebug:=Conf.AdminHelperBot.Debug;

  Current:=aCurrentEvent;
  FIsSpam:=aIsSpam;
  FTaskCommand:=aTaskCommand;
end;

destructor TSpamFilterTask.Destroy;
begin
  FBot.Logger.Free;
  FBot.Free;
  FCurrent.Free;
  inherited Destroy;
end;

procedure TSpamFilterTask.ProcessTask(aSpamFilter: TSpamFilter);
begin
  case FTaskCommand of
    ftcTrain:    Current.TrainFromMessage(aSpamFilter, IsSpam);
    ftcClassify: Current.ClassifyMessage(aSpamFilter);
    ftcLoad:     aSpamFilter.Load;
    ftcSave:     aSpamFilter.Save;
  end;
end;

{ TSpamFilterThread }

procedure TSpamFilterThread.ProcessTask(aTask: TSpamFilterTask);
begin
  try
    try
      aTask.ProcessTask(FSpamFilter);
    except
      on E: Exception do Logger.Error('TSpamFilterThread.ProcessTask '+E.ClassName+': '+E.Message);
    end;
  finally
    aTask.Free;
  end;
end;

constructor TSpamFilterThread.Create;
begin
  inherited Create;
  FSpamFilter:=TSpamFilter.Create;
  FSpamFilter.StorageDir:=ConfDir;
  FSpamFilter.InitialSpamMessage:='crypto';
  FSpamFilter.InitialHamMessage:='lazarus and FreePascal/Pascal';
  Logger.LogType:=ltFile;
  Logger.AppendContent:=True;
  Logger.FileName:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)))+'spamfilter.log';
end;

destructor TSpamFilterThread.Destroy;
begin
  FSpamFilter.Free;
  inherited Destroy;
end;

procedure TSpamFilterThread.Classify(aCurrentEvent: TCurrentEvent);
begin
  PushTask(TSpamFilterTask.Create(ftcClassify, aCurrentEvent));
end;

procedure TSpamFilterThread.Load;
begin
  PushTask(TSpamFilterTask.Create(ftcLoad));
end;

procedure TSpamFilterThread.Save;
begin
  PushTask(TSpamFilterTask.Create(ftcSave));
end;

procedure TSpamFilterThread.Train(aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
begin
  PushTask(TSpamFilterTask.Create(ftcTrain, aCurrentEvent, aIsSpam));
end;

end.


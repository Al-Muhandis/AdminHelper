unit spamfilter_worker;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, taskworker, spamfilter, tgsendertypes, tgtypes, adminhelper_orm, telegram_cmn
  ;

const
  { The training base is saved automatically after this many trainings:
    the graceful shutdown callback is not guaranteed to run (the daemon may be
    just killed), so periodic saving bounds the possible training loss }
  AutosaveAfterTrainings = 50;

type

  TFilterTaskCommand = (ftcNone, ftcTrain, ftcClassify, ftcLoad, ftcSave);

  { TSpamFilterTask }

  TSpamFilterTask = class
  private
    FComplainant: TTelegramUserObj;
    FContentType: TContentType;
    FIsExternalReply: Boolean;
    FInspectedChat: TTelegramChatObj;
    FInspectedMessage: String;
    FInspectedMessageID: Integer;
    FInspectedUser: TTelegramUserObj;
    FIsSpam: Boolean;
    FTaskCommand: TFilterTaskCommand;
    procedure SetComplainant(AValue: TTelegramUserObj);
    procedure SetInspectedChat(AValue: TTelegramChatObj);
    procedure SetInspectedUser(AValue: TTelegramUserObj);
  protected
    procedure Assign(aSrc: TCurrentEvent);
    procedure AssignTo(aDest: TCurrentEvent);
  public
    constructor Create(aTaskCommand: TFilterTaskCommand; aCurrentEvent: TCurrentEvent=nil; aIsSpam: Boolean = False);
    destructor Destroy; override;
    property ContentType: TContentType read FContentType write FContentType;
    property IsExternalReply: Boolean read FIsExternalReply write FIsExternalReply;
    property InspectedMessage: String read FInspectedMessage write FInspectedMessage;
    property InspectedMessageID: Integer read FInspectedMessageID write FInspectedMessageID;
    { 3 properties below clone its value while assigning because asynchronous handling of the taskworker }
    property InspectedUser: TTelegramUserObj read FInspectedUser write SetInspectedUser;
    property InspectedChat: TTelegramChatObj read FInspectedChat write SetInspectedChat;
    property Complainant: TTelegramUserObj read FComplainant write SetComplainant;
    property IsSpam: Boolean read FIsSpam write FIsSpam;
    property TaskCommand: TFilterTaskCommand read FTaskCommand;
  end;

  TCustomSpamFilterThread = specialize TgTaskWorkerThread<TSpamFilterTask>;

  { TSpamFilterThread }

  TSpamFilterThread = class(TCustomSpamFilterThread)
  private
    FBot: TTelegramSender;
    FBotORM: TBotORM;
    FSpamFilter: TSpamFilter;
    FCurrent: TCurrentEvent;
    FTrainedSinceSave: Integer;
  protected
    procedure ProcessTask(aTask: TSpamFilterTask); override;
    property ORM: TBotORM read FBotORM;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Classify(aCurrentEvent: TCurrentEvent);
    procedure Load;
    procedure Save;
    { Synchronous save for the shutdown path: the worker thread must already
      be terminated, so the filter is not touched concurrently }
    procedure SaveBase;
    procedure Train(aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
  end;

implementation

uses
  SQLDB, adminhelper_conf, eventlog, global
  ;

{ TSpamFilterTask }

procedure TSpamFilterTask.SetInspectedUser(AValue: TTelegramUserObj);
begin
  if FInspectedUser=AValue then Exit;
  FreeAndNil(FInspectedUser);
  if Assigned(AValue) then
    FInspectedUser:=AValue.Clone;
end;

procedure TSpamFilterTask.Assign(aSrc: TCurrentEvent);
begin
  if not Assigned(aSrc) then
  begin
    Complainant:=       nil;
    InspectedChat:=     nil;
    InspectedUser:=     nil;
    InspectedMessage:=  EmptyStr;
    InspectedMessageID:=0;
    ContentType:=       cntUnknown;
    IsExternalReply:=False;
    Exit;
  end;
  Complainant:=       aSrc.Complainant;
  InspectedChat:=     aSrc.InspectedChat;
  InspectedUser:=     aSrc.InspectedUser;
  InspectedMessage:=  aSrc.InspectedMessage;
  InspectedMessageID:=aSrc.InspectedMessageID;
  ContentType:=       aSrc.ContentType;
  IsExternalReply:=   aSrc.IsExternalReply;
end;

procedure TSpamFilterTask.AssignTo(aDest: TCurrentEvent);
begin
  aDest.Complainant:=       Complainant;
  aDest.InspectedChat:=     InspectedChat;
  aDest.InspectedUser:=     InspectedUser;
  aDest.InspectedMessage:=  InspectedMessage;
  aDest.InspectedMessageID:=InspectedMessageID;
  aDest.ContentType:=       ContentType;
  aDest.IsExternalReply:=   IsExternalReply;
end;

constructor TSpamFilterTask.Create(aTaskCommand: TFilterTaskCommand; aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
begin
  Assign(aCurrentEvent);
  FIsSpam:=aIsSpam;
  FTaskCommand:=aTaskCommand;
end;

destructor TSpamFilterTask.Destroy;
begin
  FComplainant.Free;
  FInspectedChat.Free;
  FInspectedUser.Free;
  inherited Destroy;
end;

procedure TSpamFilterTask.SetComplainant(AValue: TTelegramUserObj);
begin
  if FComplainant=AValue then Exit;
  FreeAndNil(FComplainant);
  if Assigned(AValue) then
    FComplainant:=AValue.Clone;
end;

procedure TSpamFilterTask.SetInspectedChat(AValue: TTelegramChatObj);
begin
  if FInspectedChat=AValue then Exit;
  FreeAndNil(FInspectedChat);
  if Assigned(AValue) then
    FInspectedChat:=AValue.Clone;
end;

{ TSpamFilterThread }

procedure TSpamFilterThread.ProcessTask(aTask: TSpamFilterTask);

  procedure Execute(aTask: TSpamFilterTask);
  begin
    aTask.AssignTo(FCurrent);
    case aTask.FTaskCommand of
      ftcTrain:
        begin
          FCurrent.TrainFromMessage(FSpamFilter, aTask.IsSpam);
          Inc(FTrainedSinceSave);
          if FTrainedSinceSave>=AutosaveAfterTrainings then
          begin
            FSpamFilter.Save;
            FTrainedSinceSave:=0;
          end;
        end;
      ftcClassify: FCurrent.ClassifyMessage(FSpamFilter);
      ftcLoad:     FSpamFilter.Load;
      ftcSave:
        begin
          FSpamFilter.Save;
          FTrainedSinceSave:=0;
        end;
    end;
  end;

begin
  try
    try
      try
        Execute(aTask);
      except
        on E: ESQLDatabaseError do
          if CheckDisconnectErr(E.Message) then
          begin
            { MySQL drops idle connections and restarts: replay the task on a
              fresh connection once instead of silently dropping it. Replaying
              is safe: the stored message makes the second pass a non-first
              complaint, so no duplicate notifications go out }
            Logger.Error('ProcessTask. DB connection lost: reconnecting and replaying the task');
            ORM.Reconnect;
            Execute(aTask);
          end
          else
            raise;
      end;
    finally
      aTask.Free;
    end;
  except
    on E: Exception do Logger.Error('ProcessTask. '+E.ClassName+': '+E.Message);
  end;
end;

constructor TSpamFilterThread.Create;
begin
  inherited Create;

  FBot:=TTelegramSender.Create(Conf.AdminHelperBot.Telegram.Token);
  FBot.BotUsername:=Conf.AdminHelperBot.Telegram.UserName;
  FBot.Logger:=Logger;
  FBot.Logger.LogType:=ltFile;
  FBot.Logger.AppendContent:=True;
  FBot.BotUsername:=Conf.AdminHelperBot.Telegram.UserName;
  FBot.Logger.FileName:=_LogDir+'spamfilter.log';
  FBot.LogDebug:=Conf.AdminHelperBot.Debug or Conf.Debug.Enabled;

  FBotORM:=TBotORM.Create(Conf.AdminHelperDB);
  FBotORM.LogFileName:='worker_db_sql.log';

  FCurrent:=TCurrentEvent.Create(FBot, ORM);

  FSpamFilter:=TSpamFilter.Create;
  FSpamFilter.StorageDir:=_DataDir;
  FSpamFilter.InitialSpamMessage:='crypto';
  FSpamFilter.InitialHamMessage:='lazarus and FreePascal/Pascal';
end;

destructor TSpamFilterThread.Destroy;
begin
  FSpamFilter.Free;
  FCurrent.Free;
  FBotORM.Free;
  FBot.Free;
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

procedure TSpamFilterThread.SaveBase;
begin
  FSpamFilter.Save;
  FTrainedSinceSave:=0;
end;

procedure TSpamFilterThread.Train(aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
begin
  PushTask(TSpamFilterTask.Create(ftcTrain, aCurrentEvent, aIsSpam));
end;

end.


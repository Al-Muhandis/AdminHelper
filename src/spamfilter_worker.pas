unit spamfilter_worker;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, taskworker, spamfilter, tgsendertypes, tgtypes, adminhelper_orm, telegram_cmn
  ;

type

  TFilterTaskCommand = (ftcNone, ftcTrain, ftcClassify, ftcLoad, ftcSave);

  { TSpamFilterTask }

  TSpamFilterTask = class
  private
    FComplainant: TTelegramUserObj;
    FContentType: TContentType;
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
  protected
    procedure ProcessTask(aTask: TSpamFilterTask); override;
    property ORM: TBotORM read FBotORM;
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
    Exit;
  end;
  Complainant:=       aSrc.Complainant;
  InspectedChat:=     aSrc.InspectedChat;
  InspectedUser:=     aSrc.InspectedUser;
  InspectedMessage:=  aSrc.InspectedMessage;
  InspectedMessageID:=aSrc.InspectedMessageID;
  ContentType:=       aSrc.ContentType;
end;

procedure TSpamFilterTask.AssignTo(aDest: TCurrentEvent);
begin
  aDest.Complainant:=       Complainant;
  aDest.InspectedChat:=     InspectedChat;
  aDest.InspectedUser:=     InspectedUser;
  aDest.InspectedMessage:=  InspectedMessage;
  aDest.InspectedMessageID:=InspectedMessageID;
  aDest.ContentType:=       ContentType;
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
begin
  try
    try
      aTask.AssignTo(FCurrent);
      case aTask.FTaskCommand of
        ftcTrain:    FCurrent.TrainFromMessage(FSpamFilter, aTask.IsSpam);
        ftcClassify: FCurrent.ClassifyMessage(FSpamFilter);
        ftcLoad:     FSpamFilter.Load;
        ftcSave:     FSpamFilter.Save;
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
  FBot.Logger.FileName:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)))+'spamfilter.log';
  FBot.LogDebug:=Conf.AdminHelperBot.Debug;

  FBotORM:=TBotORM.Create(Conf.AdminHelperDB);
  FBotORM.LogFileName:='worker_db_sql.log';

  FCurrent:=TCurrentEvent.Create(FBot, ORM);

  FSpamFilter:=TSpamFilter.Create;
  FSpamFilter.StorageDir:=ConfDir;
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

procedure TSpamFilterThread.Train(aCurrentEvent: TCurrentEvent; aIsSpam: Boolean);
begin
  PushTask(TSpamFilterTask.Create(ftcTrain, aCurrentEvent, aIsSpam));
end;

end.


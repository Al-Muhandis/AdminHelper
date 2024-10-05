unit actionadminhelper;

{$mode objfpc}{$H+}

interface

uses
  BrookAction, tgtypes, tgsendertypes, brooktelegramaction, adminhelper_orm, mysql80conn, fpjson, brk_tg_config
  ;

type

  { TAdminHelper }

  TAdminHelper = class(TWebhookAction)
  private
    FBotConfig: TBotConf;
    FBotORM: TBotORM;
    FDBConfig: TDBConf;
    procedure BtClbckSpam({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtCmndSpam({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj); 
    procedure BtCmndUpdate({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    function GetBotORM: TBotORM;
    procedure Complaint(aComplainant, aInspectedChat, aInspectedUser: Int64; aInspectedMessage: Integer);
    procedure InspectForBan(aComplainant, aInspectedChat, aInspectedUser: Int64;
      aInspectedMessage: LongInt; aIsSpam: Boolean);
    procedure UpdateModeratorsForChat(aChat, aFrom: Int64);
  protected
    property BotConfig: TBotConf read FBotConfig write FBotConfig;
    property DBConfig: TDBConf read FDBConfig write FDBConfig;
    property ORM: TBotORM read GetBotORM;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Post; override;
  end;

implementation

uses
  eventlog, sysutils, StrUtils, adminhelper_conf, fgl
  ;

resourcestring
  _sInspctdMsgHsDlt=    'The message was successfully deleted and the spammer was banned';
  _sInspctdMsgIsNtSpm=  'The message is marked as NOT spam. Erroneous complaint';
  _sInspctdMsgWsChckdOt='The message has already been verified';

const
  _PowerRate = 10;
  _dSpm = 'spam';

function RouteCmdSpam(aChat: Int64; aMsg: Integer; IsSpam: Boolean): String;
begin
  Result:=_dSpm+' '+aChat.ToString+' '+aMsg.ToString+' '+IsSpam.ToString;
end;

{ TAdminHelper }

procedure TAdminHelper.BtClbckSpam(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aInspectedChat, aInspectedMessage: Int64;
  aIsSpam: Boolean;
begin
  if not TryStrToInt64(ExtractDelimited(2, ACallback.Data, [' ']), aInspectedChat) then
    Exit;
  if not TryStrToInt64(ExtractDelimited(3, ACallback.Data, [' ']), aInspectedMessage) then
    Exit;
  if not TryStrToBool(ExtractDelimited(4, ACallback.Data, [' ']), aIsSpam) then
    Exit;                                   
  if not ORM.IsModerator(aInspectedChat, ACallback.From.ID) then
    Exit;
  if ORM.GetMessage(aInspectedChat, aInspectedMessage) then
    if ORM.ModifyMessageIfNotChecked(aIsSpam) then
      InspectForBan(Bot.CurrentChatId, aInspectedChat, ORM.Message.User,  aInspectedMessage, aIsSpam)
    else
      Bot.sendMessage(_sInspctdMsgWsChckdOt)
  else
    Bot.Logger.Error(Format('There is no the message #d in the chat #d', [aInspectedMessage, aInspectedChat]));
end;

procedure TAdminHelper.BtCmndSpam(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aInspectedMessage: TTelegramMessageObj;
  aComplainant, aInspectedUser, aInspectedChat: Int64;
  aInspectedMessageID: Integer;
begin
  aInspectedMessage:=aMessage.ReplyToMessage;
  if Assigned(aInspectedMessage) then
  begin
    aComplainant:=aMessage.From.ID;
    aInspectedChat:=aInspectedMessage.ChatId;
    aInspectedUser:=aInspectedMessage.From.ID;
    aInspectedMessageID:=aInspectedMessage.MessageId;
    Bot.deleteMessage(aMessage.MessageId);                                             
    Complaint(aComplainant, aInspectedChat, aInspectedUser, aInspectedMessageID);
  end
  else
    Bot.deleteMessage(aMessage.MessageId);
end;

procedure TAdminHelper.BtCmndUpdate(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aChatID, aUserID: Int64;
  aMsgID: Integer;
begin
  aChatID:=aMessage.ChatId;
  aMsgID:=aMessage.MessageId;
  aUserID:=aMessage.From.ID;
  Bot.deleteMessage(aChatID, aMsgID);
  UpdateModeratorsForChat(aChatID, aUserID);
end;

function TAdminHelper.GetBotORM: TBotORM;
begin
  if not Assigned(FBotORM) then
    FBotORM:=TBotORM.Create(DBConfig);
  Result:=FBotORM;
end;

procedure TAdminHelper.Complaint(aComplainant, aInspectedChat, aInspectedUser: Int64; aInspectedMessage: Integer);
var
  aChatMembers: TopfChatMembers.TEntities;
  aChatMember: TChatMember;

  procedure SendToModerator(aModerator: Int64);
  var
    aReplyMarkup: TReplyMarkup;
  begin
    aReplyMarkup:=TReplyMarkup.Create;
    try
      aReplyMarkup.CreateInlineKeyBoard.Add.AddButtons(
        ['It is spam', RouteCmdSpam(aInspectedChat, aInspectedMessage, True),
        'It isn''t spam!', RouteCmdSpam(aInspectedChat, aInspectedMessage, False)]
      );
      Bot.copyMessage(aModerator, aInspectedChat, aInspectedMessage, False, aReplyMarkup);
    finally
      aReplyMarkup.Free;
    end;
  end;

begin
  if not ORM.GetOrAddMessage(aInspectedUser, aInspectedChat, aInspectedMessage) then
  begin
    aChatMembers:=TopfChatMembers.TEntities.Create;
    try
      ORM.GetModeratorsByChat(aInspectedChat, aChatMembers);
      for aChatMember in aChatMembers do
        if aChatMember.Moderator then
          SendToModerator(aChatMember.User);
    finally
      aChatMembers.Free;
    end;
  end;
  if ORM.Message.IsSpam<>0 then
    Exit;
  ORM.AddComplaint(aComplainant, aInspectedChat, aInspectedMessage);
  if ORM.UserByID(aComplainant).Rate>_PowerRate then
    InspectForBan(aComplainant, aInspectedChat, aInspectedUser, aInspectedMessage, True);
end;

procedure TAdminHelper.InspectForBan(aComplainant, aInspectedChat, aInspectedUser: Int64; aInspectedMessage: LongInt;
  aIsSpam: Boolean);
begin
  ORM.DoAfterMessageChecking(aComplainant, aInspectedChat, aInspectedMessage, aIsSpam);
  if aIsSpam then
  begin
    Bot.Logger.Debug(Format('aInspectedMessage: %d', [aInspectedMessage]));
    Bot.deleteMessage(aInspectedMessage);
    Bot.banChatMember(aInspectedChat, aInspectedUser);
    Bot.sendMessage(Bot.CurrentUser.ID, _sInspctdMsgHsDlt);
  end
  else
    Bot.sendMessage(Bot.CurrentUser.ID, _sInspctdMsgIsNtSpm);
end;

procedure TAdminHelper.UpdateModeratorsForChat(aChat, aFrom: Int64);
var
  aModerators: TJSONArray;
  aModeratorIDs: TInt64List;
  aChatMember: TTelegramChatMember;
  m: TJSONEnum;
begin
  if not Bot.getChatMember(aChat, aFrom, aChatMember) or
    not (aChatMember.StatusType in [msCreator, msAdministrator]) then
      Exit;
  ORM.ClearModeratorsForChat(aChat);
  Bot.getChatAdministrators(aChat, aModerators);
  aModeratorIDs:=TInt64List.Create;
  try                                      
    aModeratorIDs.Capacity:=aModerators.Count;
    for m in aModerators do
      with (m.Value as TJSONObject).Objects['user'] do
        if not Booleans['is_bot'] then
          aModeratorIDs.Add(Int64s['id']);
    try
      ORM.AddChatMembers(aChat, True, aModeratorIDs);
    except
      on E: Exception do
        Bot.Logger.Error('UpdateModeratorsForChat. '+e.ClassName+': '+e.Message);
    end;
  finally
    aModeratorIDs.Free;
    aModerators.Free;
  end;
end;

constructor TAdminHelper.Create;
begin
  BotConfig:=Conf.AdminHelperBot;
  DBConfig:=Conf.AdminHelperDB;
  inherited Create;
  Bot.Logger:=TEventLog.Create(nil);
  Bot.Logger.LogType:=ltFile;
  Bot.Logger.AppendContent:=True;
  Bot.BotUsername:=BotConfig.Telegram.UserName;
  Bot.Logger.FileName:=AppDir+Bot.BotUsername+'.log';

  Bot.LogDebug:=BotConfig.Debug;

  Bot.CommandHandlers['/spam']:=@BtCmndSpam;
  Bot.CallbackHandlers['spam']:=@BtClbckSpam;
  Bot.CommandHandlers['/update']:=@BtCmndUpdate;

  Bot.StartText:='Start text';
  Bot.HelpText:='Help text';
end;

destructor TAdminHelper.Destroy;
begin
  FBotORM.Free;
  Bot.Logger.Free;
  inherited Destroy;
end;

procedure TAdminHelper.Post;
begin
  try
    Bot.Token:=Variables.Values['token'];
    if SameStr(Bot.Token, BotConfig.Telegram.Token) then
      inherited Post
    else
      HttpResponse.Code:=404;
  except
    on E: Exception do
      Bot.Logger.Error('['+Self.ClassName+'] '+e.ClassName+': '+e.Message);
  end;
end;

initialization
  TAdminHelper.Register('/adminhelper/:token/');

end.

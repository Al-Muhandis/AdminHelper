unit actionadminhelper;

{$mode objfpc}{$H+}

interface

uses
  tgtypes, tgsendertypes, brooktelegramaction, adminhelper_orm, fpjson, brk_tg_config, telegram_cmn
  ;

type

  TDefenderStatus = (dsUnknown, dsStandard, dsPatrol, dsGuard);

  { TAdminHelper }

  TAdminHelper = class(TWebhookAction)
  private
    FBotConfig: TBotConf;
    FBotORM: TBotORM;
    FCurrent: TCurrentEvent;
    procedure AdminSpamVerdict(const aIsSpamStr, aCallbackID: String; aInspectedChat, aExecutor: Int64;
      aInspectedMessage: Integer);
    procedure BtClbckMessage({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtClbckSpam({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtCmndSaveFilters({%H-}aSender: TObject; const {%H-}ACommand: String; {%H-}aMessage: TTelegramMessageObj);
    procedure BtCmndSettings({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtCmndSpam({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj); 
    procedure BtCmndUpdate({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtRcvChatMemberUpdated({%H-}ASender: TTelegramSender; aChatMemberUpdated: TTelegramChatMemberUpdated);
    procedure BtRcvMessage({%H-}ASender: TObject; AMessage: TTelegramMessageObj);
    procedure ChangeKeyboardAfterCheckedOut(aIsSpam: Boolean; aInspectedUser: Int64; const aInspectedUserName: String;
      aIsUserPrivacy: Boolean = False);
    procedure ComfirmationErroneousBan(aInspectedChat: Int64; aInspectedMessage: Integer);
    function GetBotORM: TBotORM;
    function GetCurrent: TCurrentEvent;
    procedure SendComplaint;
    procedure RollbackErroneousBan(aInspectedChat, aInspectedUser, aExecutor: Int64; aInspectedMessage: Integer;
      const aInspectedUserName: String);
    procedure TryRollbackErroneousBan(aInspectedChat: Int64; aInspectedMessage: Integer; const aCallbackID: String;
      aCallbackMessageID: Integer);
    procedure UpdateModeratorsForChat(aChat, aFrom: Int64);
  protected
    property BotConfig: TBotConf read FBotConfig write FBotConfig;
    property Current: TCurrentEvent read GetCurrent;
    property ORM: TBotORM read GetBotORM;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Post; override;
  end;

implementation

uses
  eventlog, sysutils, StrUtils, adminhelper_conf, tgutils, spamfilter_implementer
  ;

resourcestring
  _sInspctdMsgWsChckdOt='The message has already been verified';
  _sBnRlbck=            'The user''s ban was rolled back: unbanning and rating returning ';
  _sBnAlrdyRlbck=       'This ban action has already been rolled back';
  _sStartText=          'Start Text for TAdminHelper';
  _sHelpText=           'Help Text for TAdminHelper';
  _sYrRtng=             'Your rating is %d';
  _sYrRghts=            'Status: %s';
  _sCnfrmtnRlbckBn=     'Do you think the ban was wrong? '+
    'If the ban is rolled back, the complainant''s rating will be downgraded and '+
    'the inspected user who sent this message will be unbanned.';
  _sCmplnntIsFldByBt=   'The complaint is filed by the bot itself';
  _sDbgSpmInf=          'Ln spam probability: %n, Ln ham probability: %n. Spam Factor: %n'; 
  _sSpmBsEmj=           'It is identified as a spam based on emojies in the message';

const
  _LvlStndrd='Standard';
  _LvlPatrol='Patrol';  
  _LvlGrd=   'Guard';

  _emjSheriff='🛡'; 
  _emjPatrol='🚓';

function BuildMsgUrl(aChat: TTelegramChatObj; aMsgID: Integer): String;
const
  _ChatIDPrefix='-100';
var
  aTpl, aChatName: String;
begin
  aChatName:=aChat.Username;
  if aChatName.IsEmpty then
  begin
    aChatName:=aChat.ID.ToString;
    if StartsStr(_ChatIDPrefix, aChatName) then
      aChatName:=RightStr(aChatName, Length(aChatName)-Length(_ChatIDPrefix))
    else
      Exit('https://t.me/'); { #todo : Maybe other handling? }
    aTpl:='https://t.me/c/%s/%d';
  end
  else
    aTpl:='https://t.me/%s/%d';
  Result:=Format(aTpl, [aChatName, aMsgID]);
end;

{ TAdminHelper }

procedure TAdminHelper.BtClbckSpam(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aInspectedChat, aCurrentUserID: Int64;
  aPar: String;
  aInspectedMessage: Longint;

  function NPar(N: Byte): String;
  begin
    Result:=ExtractDelimited(N, ACallback.Data, [' ']);
  end;

  procedure AdminVerdict;
  begin
    Current.InspectedMessage:=ACallback.Message.Text;
    AdminSpamVerdict(aPar, ACallback.ID, aInspectedChat, aCurrentUserID,  aInspectedMessage);
  end;

begin
  aPar:=NPar(2);
  if aPar='hide' then
  begin
    Bot.deleteMessage(ACallback.Message.MessageId);
    Exit;
  end;
  if not TryStrToInt64(aPar, aInspectedChat) then
    Exit;
  if not TryStrToInt(NPar(3), aInspectedMessage) then
    Exit;
  aCurrentUserID:=ACallback.From.ID;
  if not ORM.IsModerator(aInspectedChat, aCurrentUserID) then
    Exit;
  aPar:=NPar(4);
  case aPar of
    _dtRC: ComfirmationErroneousBan(aInspectedChat, aInspectedMessage);
    _dtR:  TryRollbackErroneousBan(aInspectedChat, aInspectedMessage, ACallback.ID, ACallback.Message.MessageId);
  else
    AdminVerdict;
  end;
  Bot.UpdateProcessed:=True;
end;

procedure TAdminHelper.BtCmndSaveFilters(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
begin
  if Bot.CurrentChatId=Conf.ServiceAdmin then
    _SpamFilterWorker.Save;
end;

procedure TAdminHelper.BtCmndSettings(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aRate: Integer;
  aStatus, aMsg: String;
begin
  aRate:=ORM.UserByID(aMessage.From.ID).Rate;
  if aRate<Conf.PatrolRate then
    aStatus:=_LvlStndrd
  else
    if aRate<Conf.GuardRate then
      aStatus:=_emjPatrol+' '+_LvlPatrol
    else
      aStatus:=_emjSheriff+' '+_LvlGrd;
  aMsg:=Format(_sYrRtng, [aRate])+LineEnding+Format(_sYrRghts, [aStatus]);
  Bot.sendMessage(aMsg);
  Bot.UpdateProcessed:=True;
end;

procedure TAdminHelper.BtCmndSpam(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aInspectedMessage: TTelegramMessageObj;
begin
  aInspectedMessage:=aMessage.ReplyToMessage;
  if Assigned(aInspectedMessage) then
  begin
    Current.AssignInspectedFromMsg(aInspectedMessage);
    Current.Complainant:=aMessage.From;
    Bot.deleteMessage(aMessage.MessageId);                                             
    SendComplaint;
  end
  else
    Bot.deleteMessage(aMessage.MessageId);
  Bot.UpdateProcessed:=True;
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
  Bot.UpdateProcessed:=True;
end;

procedure TAdminHelper.BtRcvChatMemberUpdated(ASender: TTelegramSender; aChatMemberUpdated: TTelegramChatMemberUpdated);
var
  aIsNew: Boolean;
  aUserID: Int64;
begin
  if aChatMemberUpdated.NewChatMember.StatusType<>msMember then
    Exit;  
  Current.InspectedUser:=aChatMemberUpdated.NewChatMember.User;
  aUserID:=Current.InspectedUser.ID;
  aIsNew:=not ORM.GetUserByID(aUserID);
  if ORM.User.Spammer=_msSpam then
  begin  
    Current.InspectedChat:=aChatMemberUpdated.Chat;
    Bot.banChatMember(Current.InspectedChat.ID, aUserID);
    Current.Complainant:=nil;
    Current.InspectedMessageID:=0;
    Current.SendMessagesToAdmins(True, True);
    Exit;
  end;
  ORM.User.Name:=CaptionFromUser(Current.InspectedUser);
  ORM.SaveUserAppearance(aIsNew);
end;

procedure TAdminHelper.BtRcvMessage(ASender: TObject; AMessage: TTelegramMessageObj);
begin
  Current.AssignInspectedFromMsg(AMessage);
  Current.Complainant:=nil;
  if not Current.IsGroup then
    Exit;
  if ORM.UserByID(AMessage.From.ID).Spammer=_msSpam then
  begin                   
    Current.SendMessagesToAdmins(True, False);
    Bot.deleteMessage(Current.InspectedChat.ID, Current.InspectedMessageID);
    Bot.banChatMember(Current.InspectedChat.ID, AMessage.From.ID);
    Exit;
  end;
  if ORM.User.IsNewbie then
    if not Current.InspectedMessage.IsEmpty then
      _SpamFilterWorker.Classify(Current)
    else
      Current.ProcessComplaint(False, _msUnknown);
end;

function TAdminHelper.GetBotORM: TBotORM;
begin
  if FBotORM=nil then
  begin
    FBotORM:=TBotORM.Create(Conf.AdminHelperDB);
    FBotORM.LogFileName:='action_sql_db.log';
  end;
  Result:=FBotORM;
end;

function TAdminHelper.GetCurrent: TCurrentEvent;
begin
  if FCurrent=nil then
    FCurrent:=TCurrentEvent.Create(Bot, ORM);
  Result:=FCurrent;
end;

procedure TAdminHelper.SendComplaint;
var
  aSpamStatus, aRate: Integer;
  aIsNewbie, aCanBeSilentBan: Boolean;
  aDefenderStatus: TDefenderStatus;
begin
  aSpamStatus:=_msUnknown;
  aIsNewbie:=ORM.UserByID(Current.InspectedUser.ID).IsNewbie;
  aRate:=ORM.UserByID(Current.Complainant.ID).Rate;
  aDefenderStatus:=dsStandard;
  if aRate>Conf.GuardRate then
    aDefenderStatus:=dsGuard
  else
    if aRate>Conf.PatrolRate then
      aDefenderStatus:=dsPatrol;
  if aDefenderStatus>=dsPatrol then
    if aIsNewbie or (aDefenderStatus>=dsGuard) then
    begin
      aSpamStatus:=_msSpam;
      if not Current.InspectedMessage.IsEmpty then
        _SpamFilterWorker.Train(Current, True);
    end;
  aCanBeSilentBan:=aIsNewbie and (aDefenderStatus>=dsGuard);
  Current.ProcessComplaint(aCanBeSilentBan, aSpamStatus);
end;

procedure TAdminHelper.RollbackErroneousBan(aInspectedChat, aInspectedUser, aExecutor: Int64;
  aInspectedMessage: Integer; const aInspectedUserName: String);
begin
  { Roll back the ratings due the eroneous user banning }
  ORM.UpdateRatings(aInspectedChat, aInspectedMessage, True, True, aExecutor);
  Bot.unbanChatMember(aInspectedChat, aInspectedUser, True);    
  Bot.sendMessage(Bot.CurrentUser.ID, _sBnRlbck);
  ORM.ModifyMessage(False, aExecutor);
  { Resave inspected user as a non spammer }
  ORM.SaveUserSpamStatus(aInspectedUser, aInspectedUserName, False);
end;

procedure TAdminHelper.TryRollbackErroneousBan(aInspectedChat: Int64; aInspectedMessage: Integer;
  const aCallbackID: String; aCallbackMessageID: Integer);
begin
  if not ORM.GetMessage(aInspectedChat, aInspectedMessage) then
    Exit; { #todo : Why no message? }
  if ORM.Message.IsSpam=_msNotSpam then
  begin
    Bot.answerCallbackQuery(aCallbackID, _sBnAlrdyRlbck, False, EmptyStr, 1000);
    Exit;
  end;
  Bot.deleteMessage(aCallbackMessageID);
  RollbackErroneousBan(aInspectedChat, ORM.Message.User, ORM.Message.Executor, aInspectedMessage, ORM.Message.UserName);
end;

procedure TAdminHelper.AdminSpamVerdict(const aIsSpamStr, aCallbackID: String; aInspectedChat, aExecutor: Int64;
  aInspectedMessage: Integer);
var
  aIsSpam: Boolean;
begin
  if not TryStrToBool(aIsSpamStr, aIsSpam) then
    Exit;
  if ORM.GetMessage(aInspectedChat, aInspectedMessage) then
  begin
    if ORM.ModifyMessageIfNotChecked(aIsSpam, aExecutor) then
    begin
      Current.BanOrNotToBan(aInspectedChat, ORM.Message.User,  ORM.Message.UserName, aInspectedMessage, aIsSpam);
      if not Current.InspectedMessage.IsEmpty then
        _SpamFilterWorker.Train(Current, aIsSpam);            
      ChangeKeyboardAfterCheckedOut(aIsSpam, ORM.Message.User, ORM.Message.UserName);
    end
    else begin
      ChangeKeyboardAfterCheckedOut(ORM.Message.IsSpam=_msSpam, ORM.Message.User, ORM.Message.UserName);
      Bot.answerCallbackQuery(aCallbackID, _sInspctdMsgWsChckdOt);
    end
  end
  else begin
    Bot.Logger.Error(Format('There is no the message #%d in the chat #%d', [aInspectedMessage, aInspectedChat]));
    if not Current.InspectedMessage.IsEmpty then
      _SpamFilterWorker.Train(Current, aIsSpam);
  end;
end;

procedure TAdminHelper.BtClbckMessage(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aMsg: String;

  function MessageProbablyItsSpam: String;
  var
    aSpamProbability, aHamProbability: Extended;
  begin
    if ExtractDelimited(5, ACallback.Data, [' '])='emj' then
      Result:=_sSpmBsEmj
    else begin
      if not TryStrToFloat(ExtractDelimited(3, ACallback.Data, [' ']), aSpamProbability) or
        not TryStrToFloat(ExtractDelimited(4, ACallback.Data, [' ']), aHamProbability) then
        Exit('Error, please write to the developer');
      Current.SpamProbability:=aSpamProbability;
      Current.HamProbability:=aHamProbability;
      Result:=Format(_sDbgSpmInf, [Current.SpamProbability, Current.HamProbability, Current.SpamFactor]);
    end;
  end;

begin
  case ExtractDelimited(2, ACallback.Data, [' ']) of
    _dtUsrPrvcy:    aMsg:='User privacy for one of the buttons restricted';  
    _dtCmplnntIsBt: aMsg:=_sCmplnntIsFldByBt;
    _dtPrbblySpm:   aMsg:=MessageProbablyItsSpam;
  else
    aMsg:='The message not defined';
  end;
  Bot.answerCallbackQuery(ACallback.ID, aMsg, True, EmptyStr, 10000);
  Bot.UpdateProcessed:=True;
end;

procedure TAdminHelper.ChangeKeyboardAfterCheckedOut(aIsSpam: Boolean; aInspectedUser: Int64;
  const aInspectedUserName: String; aIsUserPrivacy: Boolean);
var
  aReplyMarkup: TReplyMarkup;
  s: String;
begin
  aReplyMarkup:=TReplyMarkup.Create;
  try
    if aIsSpam then
      s:=Format(_sBtnPair, [_sBndUsr, aInspectedUserName])
    else
      s:=Format(_sInspctdUsr, [_sBndUsr, aInspectedUserName]);

    if aIsUserPrivacy then                                                                             
      aReplyMarkup.CreateInlineKeyBoard.Add.AddButton(s, RouteMsgUsrPrvcy)
    else
      aReplyMarkup.CreateInlineKeyBoard.Add.AddButtonUrl(s, Format(_dTgUsrUrl, [aInspectedUser]));
    Bot.editMessageReplyMarkup(Bot.CurrentMessage.ChatId, Bot.CurrentMessage.MessageId, EmptyStr, aReplyMarkup);
  finally
    aReplyMarkup.Free;
  end;
  if not aIsUserPrivacy then
  begin
    aIsUserPrivacy:=(Bot.LastErrorCode=400) and ContainsStr(Bot.LastErrorDescription, _tgErrBtnUsrPrvcyRstrctd);
    if aIsUserPrivacy then
      ChangeKeyboardAfterCheckedOut(aIsSpam, aInspectedUser, aInspectedUserName, True);
  end;
end;

procedure TAdminHelper.ComfirmationErroneousBan(aInspectedChat: Int64; aInspectedMessage: Integer);
var
  aReplyMarkup: TReplyMarkup;
begin
  aReplyMarkup:=TReplyMarkup.Create;
  try
    aReplyMarkup.CreateInlineKeyBoard.Add.AddButtons([
        'Yes, rollback ban action', RouteCmdSpamLastChecking(aInspectedChat, aInspectedMessage, False),
        'Close: ban was correct', 'spam hide'
      ]);
    Bot.sendMessage(_sCnfrmtnRlbckBn, pmMarkdown, False, aReplyMarkup);
  finally             
    AReplyMarkup.Free;
  end;
end;

procedure TAdminHelper.UpdateModeratorsForChat(aChat, aFrom: Int64);
var
  aModerators: TJSONArray;
  aModeratorIDs: TInt64List;
  aChatMember: TTelegramChatMember;
  m: TJSONEnum;
  aUserID: Int64;
begin
  if not Bot.getChatMember(aChat, aFrom, aChatMember) or
    not (aChatMember.StatusType in [msCreator, msAdministrator]) then
      Exit;
  ORM.ClearModeratorsForChat(aChat);
  Bot.getChatAdministrators(aChat, aModerators);
  try
    aModeratorIDs:=TInt64List.Create;
    try
      aModeratorIDs.Capacity:=aModerators.Count;
      for m in aModerators do
        with (m.Value as TJSONObject).Objects['user'] do
          if not Booleans['is_bot'] then
          begin
            aUserID:=Int64s['id'];
            aModeratorIDs.Add(aUserID);
            ORM.SaveUserSpamStatus(aUserID, Strings['first_name'], False);
          end;
      try
        ORM.AddChatMembers(aChat, True, aModeratorIDs);
      except
        on E: Exception do
          Bot.Logger.Error('UpdateModeratorsForChat. '+e.ClassName+': '+e.Message);
      end;
    finally
      aModeratorIDs.Free;
    end;
  finally  
    aModerators.Free;
  end;
end;

constructor TAdminHelper.Create;
begin
  BotConfig:=Conf.AdminHelperBot;
  inherited Create;
  Bot.Logger:=TEventLog.Create(nil);
  Bot.Logger.LogType:=ltFile;
  Bot.Logger.AppendContent:=True;
  Bot.BotUsername:=BotConfig.Telegram.UserName;
  Bot.Logger.FileName:=AppDir+Bot.BotUsername+'.log';

  Bot.LogDebug:=BotConfig.Debug;

  Bot.OnReceiveChatMemberUpdated:=@BtRcvChatMemberUpdated;
  Bot.OnReceiveMessage:=@BtRcvMessage;
  Bot.CommandHandlers['/'+_dSpm]:=@BtCmndSpam;
  Bot.CallbackHandlers['m']:=@BtClbckMessage;
  Bot.CallbackHandlers[_dSpm]:=@BtClbckSpam;
  Bot.CommandHandlers['/update']:=@BtCmndUpdate;
  Bot.CommandHandlers['/settings']:=@BtCmndSettings;
  Bot.CommandHandlers['/savefilter']:=@BtCmndSaveFilters;

  Bot.StartText:=_sStartText;
  Bot.HelpText:=_sHelpText;

end;

destructor TAdminHelper.Destroy;
begin
  FCurrent.Free;
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

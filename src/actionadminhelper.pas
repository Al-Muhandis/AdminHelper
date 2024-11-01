unit actionadminhelper;

{$mode objfpc}{$H+}

interface

uses
  BrookAction, tgtypes, tgsendertypes, brooktelegramaction, adminhelper_orm, mysql80conn, fpjson, brk_tg_config
  ;

type

  TDefenderStatus = (dsUnknown, dsStandard, dsPatrol, dsGuard);

  { TAdminHelper }

  TAdminHelper = class(TWebhookAction)
  private
    FBotConfig: TBotConf;
    FBotORM: TBotORM;
    FDBConfig: TDBConf;                             
    procedure BanOrNotToBan(aInspectedChat, aInspectedUser: Int64; aInspectedMessage: LongInt; aIsSpam: Boolean);
    procedure BtClbckMessage({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtClbckSpam({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);                     
    procedure BtCmndSettings({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtCmndSpam({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj); 
    procedure BtCmndUpdate({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtRcvChatMemberUpdated({%H-}ASender: TTelegramSender; aChatMemberUpdated: TTelegramChatMemberUpdated);
    procedure ChangeKeyboardAfterCheckedOut(aIsSpam: Boolean; aInspectedUser: Int64; aIsUserPrivacy: Boolean = False);
    function GetBotORM: TBotORM;
    procedure SendComplaint(aComplainant, aInspectedUser: TTelegramUserObj; aInspectedChat: TTelegramChatObj;
      aInspectedMessage: Integer);
    procedure SendMessagesToAdmins(aInspectedMessage: Int64; aInspectedChat: TTelegramChatObj; aInspectedUser,
      aComplainant: TTelegramUserObj; aIsSpam: Boolean; aIsPreventively: Boolean = False);
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
  eventlog, sysutils, StrUtils, adminhelper_conf, fgl, tgutils
  ;

resourcestring
  _sInspctdMsgHsDlt=    'The message was successfully deleted and the spammer was banned';
  _sInspctdMsgIsNtSpm=  'The message is marked as NOT spam. Erroneous complaint';
  _sInspctdMsgWsChckdOt='The message has already been verified';
  _sPrvntvlyBnd=        'The user #`%0:d` [%1:s](tg://user?id=%0:d) was preventively banned';
  _sStartText=          'Start Text for TAdminHelper';
  _sHelpText=           'Help Text for TAdminHelper';
  _sYrRtng=             'Your rating is %d';
  _sYrRghts=            'Status: %s';

const
  _PowerRatePatrol = 11;
  _PowerRateGuard = _PowerRatePatrol*3;
  _dSpm = 'spam';
  _LvlStndrd='Standard';
  _LvlPatrol='Patrol';  
  _LvlGrd=   'Guard';

  _emjSheriff='🛡'; 
  _emjPatrol='🚓';

  _tgErrBtnUsrPrvcyRstrctd='Bad Request: BUTTON_USER_PRIVACY_RESTRICTED';

  _dtUsrPrvcy='UsrPrvcy';

function RouteCmdSpam(aChat: Int64; aMsg: Integer; IsSpam: Boolean): String;
begin
  Result:=_dSpm+' '+aChat.ToString+' '+aMsg.ToString+' '+IsSpam.ToString;
end;

function RouteMsgUsrPrvcy: String;
begin
  Result:='m'+' '+_dtUsrPrvcy;
end;

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
  begin
    if ORM.ModifyMessageIfNotChecked(aIsSpam) then
    begin
      BanOrNotToBan(aInspectedChat, ORM.Message.User,  aInspectedMessage, aIsSpam);
      ChangeKeyboardAfterCheckedOut(aIsSpam, ORM.Message.User);
    end
    else begin
      ChangeKeyboardAfterCheckedOut(ORM.Message.IsSpam=1, ORM.Message.User);
      Bot.answerCallbackQuery(ACallback.ID, _sInspctdMsgWsChckdOt);
    end
  end
  else
    Bot.Logger.Error(Format('There is no the message #%d in the chat #%d', [aInspectedMessage, aInspectedChat]));
end;

procedure TAdminHelper.BtCmndSettings(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aRate: Integer;
  aStatus, aMsg: String;
begin
  aRate:=ORM.UserByID(aMessage.From.ID).Rate;
  if aRate<_PowerRatePatrol then
    aStatus:=_LvlStndrd
  else
    if aRate<_PowerRateGuard then
      aStatus:=_emjPatrol+' '+_LvlPatrol
    else
      aStatus:=_emjSheriff+' '+_LvlGrd;
  aMsg:=Format(_sYrRtng, [aRate])+LineEnding+Format(_sYrRghts, [aStatus]);
  Bot.sendMessage(aMsg);
end;

procedure TAdminHelper.BtCmndSpam(aSender: TObject; const ACommand: String; aMessage: TTelegramMessageObj);
var
  aInspectedMessage: TTelegramMessageObj;
  aInspectedMessageID: Integer;
  aComplainant, aInspectedUser: TTelegramUserObj;
  aInspectedChat: TTelegramChatObj;
begin
  aInspectedMessage:=aMessage.ReplyToMessage;
  if Assigned(aInspectedMessage) then
  begin
    aComplainant:=aMessage.From;
    aInspectedChat:=aInspectedMessage.Chat;
    aInspectedUser:=aInspectedMessage.From;
    aInspectedMessageID:=aInspectedMessage.MessageId;
    Bot.deleteMessage(aMessage.MessageId);                                             
    SendComplaint(aComplainant, aInspectedUser, aInspectedChat, aInspectedMessageID);
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

procedure TAdminHelper.BtRcvChatMemberUpdated(ASender: TTelegramSender; aChatMemberUpdated: TTelegramChatMemberUpdated);
var
  aIsNew: Boolean;
  aUserID: Int64;
begin
  if aChatMemberUpdated.NewChatMember.StatusType<>msMember then
    Exit;
  aUserID:=aChatMemberUpdated.NewChatMember.User.ID;
  aIsNew:=not ORM.GetUserByID(aUserID);
  if ORM.User.Spammer=1 then
  begin
    Bot.banChatMember(aChatMemberUpdated.Chat.ID, aUserID);
    SendMessagesToAdmins(0, aChatMemberUpdated.Chat, aChatMemberUpdated.NewChatMember.User, nil, True, True);
    Exit;
  end;
  ORM.SaveUserAppearance(aIsNew);
end;

function TAdminHelper.GetBotORM: TBotORM;
begin
  if FBotORM=nil then
    FBotORM:=TBotORM.Create(DBConfig);
  Result:=FBotORM;
end;

procedure TAdminHelper.SendComplaint(aComplainant, aInspectedUser: TTelegramUserObj; aInspectedChat: TTelegramChatObj;
  aInspectedMessage: Integer);
var
  aSpamStatus, aRate: Integer;
  aIsNotifyAdmins, aIsNewbie: Boolean;
  aDefenderStatus: TDefenderStatus;
begin
  aSpamStatus:=_msUnknown;
  aIsNewbie:=ORM.UserByID(aInspectedUser.ID).IsNewbie;
  aRate:=ORM.UserByID(aComplainant.ID).Rate;
  aDefenderStatus:=dsStandard;
  if aRate>_PowerRateGuard then
    aDefenderStatus:=dsGuard
  else
    if aRate>_PowerRatePatrol then
      aDefenderStatus:=dsPatrol;
  if aDefenderStatus>=dsPatrol then
    if aIsNewbie or (aDefenderStatus>=dsGuard) then
      aSpamStatus:=_msSpam;
  ORM.SaveMessage(aInspectedUser.ID, aInspectedChat.ID, aInspectedMessage, aIsNotifyAdmins, aSpamStatus);
  if aIsNotifyAdmins then
    if (aRate<=_PowerRateGuard) or aIsNewbie then
      SendMessagesToAdmins(aInspectedMessage, aInspectedChat, aInspectedUser, aComplainant, aSpamStatus=_msSpam);
  ORM.AddComplaint(aComplainant.ID, aInspectedChat.ID, aInspectedMessage); 
  if aSpamStatus=_msSpam then
    BanOrNotToBan(aInspectedChat.ID, aInspectedUser.ID, aInspectedMessage, True);
end;

procedure TAdminHelper.SendMessagesToAdmins(aInspectedMessage: Int64; aInspectedChat: TTelegramChatObj; aInspectedUser,
  aComplainant: TTelegramUserObj; aIsSpam: Boolean; aIsPreventively: Boolean);
var
  aChatMembers: TopfChatMembers.TEntities;
  aIsUserPrivacy: Boolean;
  aChatMember: TChatMember;

  procedure SendToModerator(aModerator: Int64; aIsDefinitelySpam: Boolean);
  var
    aReplyMarkup: TReplyMarkup;
    aKB: TInlineKeyboard;
    aBndUsr, aCmplnnt: String;
  begin
    aReplyMarkup:=TReplyMarkup.Create;
    try
      aKB:=aReplyMarkup.CreateInlineKeyBoard;
      if aIsDefinitelySpam then
      begin
        aBndUsr:= 'Banned user: '+CaptionFromUser(aInspectedUser);
        if not aIsPreventively then
          aCmplnnt:='Complainant: '+CaptionFromUser(aComplainant);
        if aIsUserPrivacy  then
        begin
          aKB.Add.AddButton(aBndUsr,   RouteMsgUsrPrvcy);
          if not aIsPreventively then
            aKB.Add.AddButton(aCmplnnt,  RouteMsgUsrPrvcy);
        end
        else begin
          aKB.Add.AddButtonUrl(aBndUsr,  Format('tg://user?id=%d', [aInspectedUser.ID]));
          if not aIsPreventively then
            aKB.Add.AddButtonUrl(aCmplnnt, Format('tg://user?id=%d', [aComplainant.ID]));
        end;
      end
      else begin
        aKB.Add.AddButtons(
          ['It is spam', RouteCmdSpam(aInspectedChat.ID, aInspectedMessage, True),
          'It isn''t spam!', RouteCmdSpam(aInspectedChat.ID, aInspectedMessage, False)]
        );
        aKB.Add.AddButtonUrl('Inspected message', BuildMsgUrl(aInspectedChat, aInspectedMessage));
      end;
      if aIsPreventively then
        Bot.sendMessage(aModerator, Format(_sPrvntvlyBnd, [aInspectedUser.ID, CaptionFromUser(aInspectedUser)]),
          pmMarkdown, aIsDefinitelySpam, aReplyMarkup)
      else
        Bot.copyMessage(aModerator, aInspectedChat.ID, aInspectedMessage, aIsDefinitelySpam, aReplyMarkup);
    finally
      aReplyMarkup.Free;
    end;
    if not aIsUserPrivacy then
    begin
      aIsUserPrivacy:=(Bot.LastErrorCode=400) and ContainsStr(Bot.LastErrorDescription, _tgErrBtnUsrPrvcyRstrctd);
      if aIsUserPrivacy then
        SendToModerator(aModerator, aIsDefinitelySpam);
    end;
  end;

begin
  aChatMembers:=TopfChatMembers.TEntities.Create;
  try
    ORM.GetModeratorsByChat(aInspectedChat.ID, aChatMembers);
    aIsUserPrivacy:=False;
    for aChatMember in aChatMembers do
      if aChatMember.Moderator then
        SendToModerator(aChatMember.User, aIsSpam);
  finally
    aChatMembers.Free;
  end;
end;

procedure TAdminHelper.BanOrNotToBan(aInspectedChat, aInspectedUser: Int64; aInspectedMessage: LongInt; aIsSpam: Boolean
  );
begin
  ORM.UpdateRatings(aInspectedChat, aInspectedMessage, aIsSpam);
  if aIsSpam then
  begin
    Bot.deleteMessage(aInspectedChat, aInspectedMessage);
    Bot.banChatMember(aInspectedChat, aInspectedUser);
    Bot.sendMessage(Bot.CurrentUser.ID, _sInspctdMsgHsDlt);
    ORM.SaveUserSpamStatus(aInspectedUser);
  end
  else
    Bot.sendMessage(Bot.CurrentUser.ID, _sInspctdMsgIsNtSpm);
end;

procedure TAdminHelper.BtClbckMessage(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aMsg: String;
begin
  case ExtractDelimited(2, ACallback.Data, [' ']) of
    _dtUsrPrvcy: aMsg:='User privacy for one of the buttons restricted';
  else
    aMsg:='The message not defined';
  end;
  Bot.answerCallbackQuery(ACallback.ID, aMsg, True, EmptyStr, 1000);
end;

procedure TAdminHelper.ChangeKeyboardAfterCheckedOut(aIsSpam: Boolean; aInspectedUser: Int64; aIsUserPrivacy: Boolean);
var
  aReplyMarkup: TReplyMarkup;
  s: String;
begin
  aReplyMarkup:=TReplyMarkup.Create;
  try
    if aIsSpam then
      s:='Banned user'
    else
      s:='Inspected user';
    if aIsUserPrivacy then                                                                             
      aReplyMarkup.CreateInlineKeyBoard.Add.AddButton(s, RouteMsgUsrPrvcy)
    else
      aReplyMarkup.CreateInlineKeyBoard.Add.AddButtonUrl(s, Format('tg://user?id=%d', [aInspectedUser]));
    Bot.editMessageReplyMarkup(Bot.CurrentMessage.ChatId, Bot.CurrentMessage.MessageId, EmptyStr, aReplyMarkup);
  finally
    aReplyMarkup.Free;
  end;
  if not aIsUserPrivacy then
  begin
    aIsUserPrivacy:=(Bot.LastErrorCode=400) and ContainsStr(Bot.LastErrorDescription, _tgErrBtnUsrPrvcyRstrctd);
    if aIsUserPrivacy then
      ChangeKeyboardAfterCheckedOut(aIsSpam, aInspectedUser, True);
  end;
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
  try
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
    end;
  finally  
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

  Bot.OnReceiveChatMemberUpdated:=@BtRcvChatMemberUpdated;
  Bot.CommandHandlers['/spam']:=@BtCmndSpam;
  Bot.CallbackHandlers['m']:=@BtClbckMessage;
  Bot.CallbackHandlers['spam']:=@BtClbckSpam;
  Bot.CommandHandlers['/update']:=@BtCmndUpdate;
  Bot.CommandHandlers['/settings']:=@BtCmndSettings;

  Bot.StartText:=_sStartText;
  Bot.HelpText:=_sHelpText;
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

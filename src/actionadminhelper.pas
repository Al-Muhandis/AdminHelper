unit actionadminhelper;

{$mode objfpc}{$H+}

interface

uses
  tgtypes, tgsendertypes, brooktelegramaction, adminhelper_orm, fpjson, brk_tg_config, telegram_cmn
  ;

type

  { TAdminHelper }

  TAdminHelper = class(TWebhookAction)
  private
    FBotConfig: TBotConf;
    FBotORM: TBotORM;
    FCommandsSet: Boolean;
    FCurrent: TCurrentEvent;
    procedure AdminSpamVerdict(const aIsSpamStr, aCallbackID: String; aInspectedChat, aExecutor: Int64;
      aInspectedMessage: Integer);
    procedure AdminReactionVerdict(const aIsSpamStr: String; aInspectedChat, aInspectedUser: Int64);
    procedure BtClbckMessage({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtClbckSettings({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtClbckSpam({%H-}ASender: TObject; {%H-}ACallback: TCallbackQueryObj);
    procedure BtCmndSaveFilters({%H-}aSender: TObject; const {%H-}ACommand: String; {%H-}aMessage: TTelegramMessageObj);
    procedure BtCmndSettings({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtCmndSpam({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtCmndUpdate({%H-}aSender: TObject; const {%H-}ACommand: String; aMessage: TTelegramMessageObj);
    procedure BtRcvChatMemberUpdated({%H-}ASender: TTelegramSender; aChatMemberUpdated: TTelegramChatMemberUpdated);
    procedure BtRcvMessage({%H-}ASender: TObject; AMessage: TTelegramMessageObj);
    procedure BtRcvReaction({%H-}aSender: TObject; aMessageReaction: TTelegramMessageReactionUpdated);
    procedure ChangeKeyboardAfterCheckedOut(aIsSpam: Boolean; aInspectedUser: Int64; const aInspectedUserName: String;
      aIsUserPrivacy: Boolean = False);
    procedure ComfirmationErroneousBan(aInspectedChat: Int64; aInspectedMessage: Integer);
    function GetBotORM: TBotORM;
    function GetCurrent: TCurrentEvent;
    { The inline keyboard of /settings: one row per moderated chat with the
      jump link and the notification flag; appends the section text (header,
      legend or the no-groups note) to aMsg }
    function NotifySettingsMarkup(aUser: Int64; var aMsg: String): TReplyMarkup;
    procedure SendComplaint;
    { Registers the command menu (setMyCommands) in English and Russian;
      True on success, the caller retries on the next request otherwise }
    function SetBotCommands: Boolean;
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
  eventlog, Classes, sysutils, StrUtils, adminhelper_conf, tgutils, spamfilter_implementer, global
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
  _sUndeliverableAdmins= 'These admins do not receive moderation notifications because they never opened the chat with the bot (or blocked it):' + LineEnding + '%s' + LineEnding +
    'After they open the chat, run /update to retry.';
  _sYrGrps=             'Groups you receive moderation notifications for:';
  _sNtfLgnd=            '🔔 — on, 🔕 — off; tap the flag to toggle. '+
    'The bot also turns the notifications off itself when it cannot deliver a message to you';
  _sNoGrps=             'You are not receiving moderation notifications in any group yet';

const
  { setMyCommands descriptions: plain literals because the resourcestring
    machinery translates lazily per-user on incoming updates, while the
    command menu is registered once per language on the Telegram side }
  _CmdSpamDscrEn=    'Report spam: send as a reply to the spam message';
  _CmdSpamDscrRu=    'Пожаловаться на спам: отправьте в ответ на сообщение спамера';
  _CmdUpdTxDscrEn=   'Refresh the chat administrators list (for admins)';
  _CmdUpdTxDscrRu=   'Обновить список администраторов чата (для админов)';
  _CmdSttngsDscrEn=  'Show your rating, status and notification settings';
  _CmdSttngsDscrRu=  'Показать ваш рейтинг, статус и настройки уведомлений';
  _CmdHlpDscrEn=     'How the bot works';
  _CmdHlpDscrRu=     'Как устроен бот';

  _emjNtfOn = '🔔';
  _emjNtfOff= '🔕';

{ TAdminHelper }

procedure TAdminHelper.BtClbckSpam(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aInspectedChat, aCurrentUserID, aPar3: Int64;
  aPar: String;
  aIsReaction: Boolean;

  function NPar(N: Byte): String;
  begin
    Result:=ExtractDelimited(N, ACallback.Data, [' ']);
  end;

  procedure AdminVerdict;
  begin
    if aIsReaction then
      AdminReactionVerdict(aPar, aInspectedChat, aPar3)
    else begin
      Current.InspectedMessage:=ACallback.Message.Text;
      AdminSpamVerdict(aPar, ACallback.ID, aInspectedChat, aCurrentUserID,  aPar3);
    end;
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
  aIsReaction:=(NPar(5)='r');
  if not TryStrToInt64(NPar(3), aPar3) then
    Exit;
  aCurrentUserID:=ACallback.From.ID;
  if not ORM.IsModerator(aInspectedChat, aCurrentUserID) then
    Exit;
  aPar:=NPar(4);
  case aPar of
    _dtRC: ComfirmationErroneousBan(aInspectedChat, aPar3);
    _dtR:  TryRollbackErroneousBan(aInspectedChat, aPar3, ACallback.ID, ACallback.Message.MessageId);
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
  aHint, aMsg: String;
  aRate: Integer;
  aMarkup: TReplyMarkup;
begin
  { Keep groups silent as /spam and /update do: remove the command,
    the answer always goes to the private chat with the member }
  if aMessage.Chat.ChatType<>ctPrivate then
    Bot.deleteMessage(aMessage.ChatId, aMessage.MessageId)
  else
    { The member demonstrably receives our messages: stale "undeliverable"
      marks from earlier failed notifications are cleared }
    ORM.ResetNotifyErrors(aMessage.From.ID);
  aRate:=ORM.UserByID(aMessage.From.ID).Rate;
  aMsg:=Format(_sYrRtng, [aRate])+LineEnding+
    Format(_sYrRghts, [DefenderStatusText(DefenderStatusOf(aRate, Conf.PatrolRate, Conf.GuardRate))]);
  aHint:=NextRankHint(aRate, Conf.PatrolRate, Conf.GuardRate);
  if not aHint.IsEmpty then
    aMsg+=LineEnding+aHint;
  aMarkup:=NotifySettingsMarkup(aMessage.From.ID, aMsg);
  try
    Bot.sendMessage(aMessage.From.ID, aMsg, pmDefault, False, aMarkup);
  finally
    aMarkup.Free;
  end;
  Bot.UpdateProcessed:=True;
end;

procedure TAdminHelper.BtClbckSettings(ASender: TObject; ACallback: TCallbackQueryObj);
var
  aChat: Int64;
  aMarkup: TReplyMarkup;
  aDummy: String;
  aOn: Boolean;
begin
  { RouteCmdNotify: 'set <chat> <1|0>' }
  if not TryStrToInt64(ExtractDelimited(2, ACallback.Data, [' ']), aChat) then
    Exit;
  if not ORM.IsModerator(aChat, ACallback.From.ID) then
    Exit;
  aOn:=ExtractDelimited(3, ACallback.Data, [' '])='1';
  ORM.SetUserNotify(aChat, ACallback.From.ID, aOn);
  { The flags live in the keyboard only: the text stays, redraw the markup }
  if Assigned(ACallback.Message) then
  begin
    aDummy:=EmptyStr;
    aMarkup:=NotifySettingsMarkup(ACallback.From.ID, aDummy);
    try
      Bot.editMessageReplyMarkup(ACallback.Message.ChatId, ACallback.Message.MessageId, EmptyStr, aMarkup);
    finally
      aMarkup.Free;
    end;
  end;
  Bot.UpdateProcessed:=True;
end;

function TAdminHelper.NotifySettingsMarkup(aUser: Int64; var aMsg: String): TReplyMarkup;
var
  aChats: TopfChatMembers.TEntities;
  aChatMember: TChatMember;
  aChatObj: TTelegramChatObj;
  aKB: TInlineKeyboard;
  aRow: TInlineKeyboardButtons;
  aName, aURL: String;
  aHasChats: Boolean;

  { Falls back to what the chat ID alone can tell when the bot is no longer
    in the chat and getChat fails: t.me/c/ links open for members anyway }
  procedure GroupButtonData(aChat: Int64; out aName, aURL: String);
  begin
    aName:=EmptyStr;
    aChatObj:=nil;
    if Bot.getChat(aChat, aChatObj) then
      try
        aName:=aChatObj.Title;
        if aName.IsEmpty then
          aName:='@'+aChatObj.Username;
        aURL:=BuildMsgUrl(aChatObj);
      finally
        aChatObj.Free;
      end
    else begin
      aName:=aChat.ToString;
      if StartsStr('-100', aName) then
        aURL:='https://t.me/c/'+RightStr(aName, Length(aName)-4)
      else
        aURL:='https://t.me/';
      aName:='#'+aName;
    end;
    if aName.IsEmpty then
      aName:='#'+aChat.ToString;
  end;

begin
  Result:=TReplyMarkup.Create;
  aChats:=TopfChatMembers.TEntities.Create;
  try
    ORM.GetModeratedChats(aUser, aChats);
    aHasChats:=False;
    for aChatMember in aChats do
      if aChatMember.Moderator then
      begin
        if not aHasChats then
        begin
          aHasChats:=True;
          aMsg+=LineEnding+_sYrGrps+LineEnding+_sNtfLgnd;
          aKB:=Result.CreateInlineKeyBoard;
        end;
        GroupButtonData(aChatMember.Chat, aName, aURL);
        aRow:=aKB.Add;
        aRow.AddButtonUrl(aName, aURL);
        { The flag shows the effective state; the callback carries the new
          NotifyOn value: off for a shown bell, on for a crossed one }
        if aChatMember.NotifyOn and aChatMember.NotifyOk then
          aRow.AddButton(_emjNtfOn, RouteCmdNotify(aChatMember.Chat, False))
        else
          aRow.AddButton(_emjNtfOff, RouteCmdNotify(aChatMember.Chat, True));
      end;
    if not aHasChats then
      aMsg+=LineEnding+_sNoGrps;
  finally
    aChats.Free;
  end;
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
    Bot.Logger.Info(Format('Spam report: chat #%d, reported message #%d by #%d, complainant #%d',
      [Current.InspectedChat.ID, aInspectedMessage.MessageId, Current.InspectedUser.ID, aMessage.From.ID]));
    SendComplaint;
  end
  else begin
    { The command reached us but Telegram omitted reply_to_message: the target
      is either deleted already or not visible to the bot. Log enough to
      diagnose - without it the command just disappears silently }
    Bot.Logger.Info(Format('Spam report dropped: chat #%d, command #%d by #%d has no reply_to_message',
      [aMessage.ChatId, aMessage.MessageId, aMessage.From.ID]));
    Bot.deleteMessage(aMessage.MessageId);
  end;
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
  ORM.SaveMembershipAppearance(aChatMemberUpdated.Chat.ID, aUserID);
end;

procedure TAdminHelper.BtRcvMessage(ASender: TObject; AMessage: TTelegramMessageObj);
begin
  Current.AssignInspectedFromMsg(AMessage);
  Current.Complainant:=nil;
  if not Current.IsGroup then
    Exit;
  { Check if there is a service message (without text or media) }
  if Current.ContentType=cntUnknown then
    Exit;
  if not Assigned(Current.InspectedUser) then
    Exit;
  if ORM.UserByID(AMessage.From.ID).Spammer=_msSpam then
  begin
    Current.AddMessage;
    Current.SendMessagesToAdmins(True, False);
    Bot.deleteMessage(Current.InspectedChat.ID, Current.InspectedMessageID);
    Bot.banChatMember(Current.InspectedChat.ID, Current.InspectedUser.ID);
    Exit;
  end;
  if not Conf.SpamFilter.Enabled then
    Exit;
  if ORM.IsNewbieInChat(Current.InspectedChat.ID, AMessage.From.ID) then
    if not Current.InspectedMessage.IsEmpty then
      _SpamFilterWorker.Classify(Current)
    else
      Current.ProcessComplaint(False, _msUnknown);
end;

procedure TAdminHelper.BtRcvReaction(aSender: TObject; aMessageReaction: TTelegramMessageReactionUpdated);
var
  aChatMember: TTelegramChatMember;
begin
  Current.AssignInspectedFromRctn(aMessageReaction);
  Current.Complainant:=nil;
  if not Current.IsGroup then
    Exit;
  if not Assigned(Current.InspectedUser) then
    Exit;
  if ORM.UserByID(Current.InspectedUser.ID).Spammer=_msSpam then
  begin
    Current.AddMessage(True);
    Current.SendMessagesToAdmins(True, False, True);
    Bot.banChatMember(Current.InspectedChat.ID, Current.InspectedUser.ID);
    Exit;
  end;
  if not Conf.SpamFilter.Enabled then
    Exit;
  if ORM.IsNewbieInChat(Current.InspectedChat.ID, Current.InspectedUser.ID) and
    Bot.getChatMember(Current.InspectedChat.ID, Current.InspectedUser.ID, aChatMember) then
    try
      if aChatMember.StatusType<>msMember then
        Current.ProcessSpamReaction(False, _msUnknown);
    finally                                         
      aChatMember.Free;
    end;
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
  aIsNewbie:=ORM.IsNewbieInChat(Current.InspectedChat.ID, Current.InspectedUser.ID);
  aRate:=ORM.UserByID(Current.Complainant.ID).Rate;
  aDefenderStatus:=DefenderStatusOf(aRate, Conf.PatrolRate, Conf.GuardRate);
  if aDefenderStatus>=dsPatrol then
    if aIsNewbie or (aDefenderStatus>=dsGuard) then
    begin
      aSpamStatus:=_msSpam;
      if not Current.InspectedMessage.IsEmpty then
        _SpamFilterWorker.Train(Current, True);
    end;
  aCanBeSilentBan:=aIsNewbie and (aDefenderStatus>=dsGuard);
  Current.ComplainantRate:=aRate;
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

procedure TAdminHelper.AdminReactionVerdict(const aIsSpamStr: String; aInspectedChat, aInspectedUser: Int64);
var
  aIsSpam: Boolean;
begin
  if not TryStrToBool(aIsSpamStr, aIsSpam) then
    Exit;
  if ORM.GetReaction(aInspectedChat, aInspectedUser) then
  begin
    Current.BanReactionSpam(aInspectedChat, ORM.Reaction.User,  ORM.Reaction.UserName, aIsSpam);
    ChangeKeyboardAfterCheckedOut(aIsSpam, ORM.Reaction.User, ORM.Reaction.UserName);
  end
  else
    Bot.Logger.Error(Format('There is no the reaction user #%d in the chat #%d', [aInspectedUser, aInspectedChat]));
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
  aUndeliverable: TInt64List;
  aChatMember: TTelegramChatMember;
  aNames: TStringList;
  m: TJSONEnum;
  aUserID: Int64;
begin
  if not Bot.getChatMember(aChat, aFrom, aChatMember) or
    not (aChatMember.StatusType in [msCreator, msAdministrator]) then
      Exit;
  aModerators:=nil;
  { Fetch the fresh list first: on API failure keep the stored moderators,
    otherwise the chat would be left without any notification receiver }
  if not Bot.getChatAdministrators(aChat, aModerators) then
  begin
    Bot.Logger.Error('UpdateModeratorsForChat. Getting the chat administrators failed');
    Exit;
  end;
  aUndeliverable:=TInt64List.Create;
  try
    { Snapshot who was unreachable before the refresh: their rows are
      recreated below with a clean flag }
    ORM.GetUndeliverableModerators(aChat, aUndeliverable);
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
        ORM.ClearModeratorsForChat(aChat);
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
    { Tell the invoker which admins will still not receive anything until
      they open the chat with the bot }
    if aUndeliverable.Count>0 then
    begin
      aNames:=TStringList.Create;
      try
        for aUserID in aUndeliverable do
          aNames.Add(Format('%s (#%d)', [ORM.UserByID(aUserID).Name, aUserID]));
        Bot.sendMessage(aFrom, Format(_sUndeliverableAdmins, [aNames.Text]));
      finally
        aNames.Free;
      end;
    end;
  finally
    aUndeliverable.Free;
  end;
end;

function TAdminHelper.SetBotCommands: Boolean;

  procedure SetScope(const aCmds, aCmdsRu: TBotCommandArray; aScopeType: TCommandScopeType);
  var
    aScope: TBotCommandScope;
  begin
    aScope:=TBotCommandScope.Create;
    try
      aScope.ScopeType:=aScopeType;
      Result:=Bot.setMyCommands(aCmds, aScope) and Bot.setMyCommands(aCmdsRu, aScope, 'ru');
    finally
      aScope.Free;
    end;
  end;

var
  aGroupCmds, aGroupCmdsRu, aPrivateCmds, aPrivateCmdsRu: TBotCommandArray;
begin
  Result:=False;
  aGroupCmds:=TBotCommandArray.Create;
  aGroupCmdsRu:=TBotCommandArray.Create;
  aPrivateCmds:=TBotCommandArray.Create;
  aPrivateCmdsRu:=TBotCommandArray.Create;
  try
    aGroupCmds.AddCommand(_dSpm, _CmdSpamDscrEn);
    aGroupCmds.AddCommand('update', _CmdUpdTxDscrEn);
    aGroupCmdsRu.AddCommand(_dSpm, _CmdSpamDscrRu);
    aGroupCmdsRu.AddCommand('update', _CmdUpdTxDscrRu);
    aPrivateCmds.AddCommand('settings', _CmdSttngsDscrEn);
    aPrivateCmds.AddCommand('help', _CmdHlpDscrEn);
    aPrivateCmdsRu.AddCommand('settings', _CmdSttngsDscrRu);
    aPrivateCmdsRu.AddCommand('help', _CmdHlpDscrRu);
    SetScope(aGroupCmds, aGroupCmdsRu, stAllGroupChats);
    if Result then
      SetScope(aPrivateCmds, aPrivateCmdsRu, stAllPrivateChats);
    if not Result then
      Bot.Logger.Error('setMyCommands failed: '+Bot.LastErrorDescription);
  finally
    aGroupCmds.Free;
    aGroupCmdsRu.Free;
    aPrivateCmds.Free;
    aPrivateCmdsRu.Free;
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
  Bot.Logger.FileName:=_LogDir+Bot.BotUsername+'.log';

  Bot.LogDebug:=BotConfig.Debug or Conf.Debug.Enabled;

  Bot.OnReceiveChatMemberUpdated:=@BtRcvChatMemberUpdated;
  Bot.OnReceiveMessage:=@BtRcvMessage;
  Bot.OnReceiveMessageReaction:=@BtRcvReaction;
  Bot.CommandHandlers['/'+_dSpm]:=@BtCmndSpam;
  Bot.CallbackHandlers['m']:=@BtClbckMessage;
  Bot.CallbackHandlers[_dSpm]:=@BtClbckSpam;
  Bot.CallbackHandlers[_dSttngs]:=@BtClbckSettings;
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
    begin
      if not FCommandsSet then
        FCommandsSet:=SetBotCommands;
      inherited Post
    end
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

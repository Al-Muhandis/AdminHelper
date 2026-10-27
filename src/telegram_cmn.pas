unit telegram_cmn;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, tgtypes, tgsendertypes, adminhelper_orm, spamfilter
  ;

type

  TDefenderStatus = (dsUnknown, dsStandard, dsPatrol, dsGuard);

  { TCurrentEvent }

  TCurrentEvent = class
  private
    FBot: TTelegramSender;
    FComplainant: TTelegramUserObj;
    FBotORM: TBotORM;
    FComplainantRate: Integer;
    FContentType: TContentType;
    FEmojiMarker: Boolean;
    FInspectedIsNewbie: Boolean;
    FIsExternalReply: Boolean;
    FInspectedChat: TTelegramChatObj;
    FInspectedMessage: String;
    FInspectedMessageID: Integer;
    FInspectedUser: TTelegramUserObj;
    FNewReactions: TTelegramReactionTypeList;
    FNewbieKnown: Boolean;
    FSpamProbability, FHamProbability: Double;
    function GetInspectedIsNewbie: Boolean;
  protected
    property Bot: TTelegramSender read FBot;
    property ORM: TBotORM read FBotORM;
  public
    procedure AddMessage(aIsReaction: Boolean = False);
    procedure AssignInspectedFromMsg(aMessage: TTelegramMessageObj);
    procedure AssignInspectedFromRctn(aReactionUpdated: TTelegramMessageReactionUpdated);
    procedure BanOrNotToBan(aInspectedChat, aInspectedUser: Int64; const aInspectedUserName: String;
      aInspectedMessage: LongInt; aIsSpam: Boolean);
    procedure BanReactionSpam(aInspectedChat, aInspectedUser: Int64; const aInspectedUserName: String;
      aIsSpam: Boolean);
    constructor Create(aBot: TTelegramSender; aBotORM: TBotORM);
    procedure ProcessComplaint(aCanBeSilentBan: Boolean; aSpamStatus: Integer);
    procedure ProcessSpamReaction(aCanBeSilentBan: Boolean; aSpamStatus: Integer);
    function IsGroup: Boolean;
    procedure ClassifyMessage(aSpamFilter: TSpamFilter);
    procedure TrainFromMessage(aSpamFilter: TSpamFilter; aIsSpam: Boolean);
    function SpamFactor: Double;
    procedure SendMessagesToAdmins(aIsDefinitlySpam: Boolean; aIsPreventively: Boolean = False;
      aIsReaction: Boolean = False);
    procedure SendToModerator(aModerator: Int64; aIsDefinitelySpam, aIsPreventively: Boolean;
      var aIsUserPrivacy: Boolean; aIsReaction: Boolean = False);
    property ContentType: TContentType read FContentType write FContentType;
    property IsExternalReply: Boolean read FIsExternalReply write FIsExternalReply;
    property InspectedChat: TTelegramChatObj read FInspectedChat write FInspectedChat;
    property InspectedUser: TTelegramUserObj read FInspectedUser write FInspectedUser;
    { The inspected user joined this chat within NewbieDays; resolved by ORM
      on the first use and cached for the whole event }
    property InspectedIsNewbie: Boolean read GetInspectedIsNewbie;
    property InspectedMessage: String read FInspectedMessage write FInspectedMessage;
    property InspectedMessageID: Integer read FInspectedMessageID write FInspectedMessageID;
    property Complainant: TTelegramUserObj read FComplainant write FComplainant;
    { The complainant rating for the moderation card; negative = not known }
    property ComplainantRate: Integer read FComplainantRate write FComplainantRate;
    property SpamProbability: Double read FSpamProbability write FSpamProbability;
    property HamProbability: Double read FHamProbability write FHamProbability;
{ If the message seems to be spam due mass emojies in it }
    property EmojiMarker: Boolean read FEmojiMarker write FEmojiMarker;
{ The propery stores emojies list from a TelegramMessageRection update.
  Do not frees the list in this class. This is just pointer from the telegram update object}
    property NewReactions: TTelegramReactionTypeList read FNewReactions write FNewReactions;
  end;

function RouteCmdSpam(aChat: Int64; aMsg: Integer; IsSpam: Boolean): String;
function RouteCmdReaction(aChat, aUser: Int64; IsSpam: Boolean): String;
function RouteCmdSpamLastChecking(aChat: Int64; aMsg: Integer; IsConfirmation: Boolean): String;
function RouteMsgUsrPrvcy: String;
function RouteMsgCmplnntIsBt(): String;
function RouteMsgPrbblySpm(aSpamProbability, aHamProbability: Double; aIsEmojiMarker: Boolean = False): String;
function BuildMsgUrl(aChat: TTelegramChatObj; aMsgID: Integer = 0): String;
function DefenderStatusOf(aRate, aPatrolRate, aGuardRate: Integer): TDefenderStatus;
function DefenderMark(aStatus: TDefenderStatus): String;
function DefenderStatusText(aStatus: TDefenderStatus): String;
{ Short caption suffix showing the rank mark and the rate; empty for ordinary members }
function DefenderTag(aRate, aPatrolRate, aGuardRate: Integer): String;
{ Human-readable text about the points left to the next rank; empty for Guards }
function NextRankHint(aRate, aPatrolRate, aGuardRate: Integer): String;

const
  _sBtnPair='%s: %s';
  _dTgUsrUrl='tg://user?id=%d';
  _tgErrBtnUsrPrvcyRstrctd='Bad Request: BUTTON_USER_PRIVACY_RESTRICTED';  
  _dtUsrPrvcy=   'UsrPrvcy';
  _dtCmplnntIsBt='CmplnntIsBt'; 
  _dtPrbblySpm=  'PrbblySpm';
  _dSpm =        'spam';
  _dRctn =       'reaction';
  _dtR=          'r';  // rollback ban action
  _dtRC=         'rc'; // confirmation of rollback ban action

resourcestring
  _sInspctdUsr='Inspected user';
  _sBndUsr=    'Banned user';
  _sLvlStndrd= 'Standard';
  _sLvlPatrol= 'Patrol';
  _sLvlGrd=    'Guard';
  _sNxtRnk=    'Points to the next status %s: %d';

implementation

uses
  StrUtils, tgutils, adminhelper_conf, emojiutils
  ;

resourcestring
  _sPrvntvlyBnd= 'The user #`%0:d` [%1:s](tg://user?id=%0:d) was preventively banned';
  _sSpmRctn=     'Spam reaction';
  _sIsThsRctnSpm='Is this reaction spam? Emojies: %s';
  _sInspctdMsg=  'Inspected message';
  _sCmplnnt=     'Complainant';
  _sIsErnsBn=    'Is this erroneous ban?';
  _sMybItsSpm=   '"Probably it''s a spam". More info...';
  _sMybItsNtSpm= '"Probably it''s not a spam". More info...';
  _sInspctdMsgHsDlt=    'The message was successfully deleted and the spammer was banned';
  _sInspctdMsgIsNtSpm=  'The message is marked as NOT spam. Erroneous complaint';
  _sSpmRctnBnd=         'The reaction author has been banned';
  _sSpmRctnIsNtSpm=     'The reaction is marked as NOT spam. The user was unbanned';

const
  _emjbot='🤖';
  _emjInfrmtn='ℹ️';
  _emjMonocle='🧐';
  _emjSheriff='🛡';
  _emjPatrol='🚓';
  _emjNewbie='🆕';

  _tgErrChatNotFound='chat not found';
  _tgErrBotBlocked='blocked by the user';
  _tgErrBotCantInit='can''t initiate conversation';

{ The moderator never opened the chat with the bot or blocked it:
  sending to him fails and will keep failing until he opens the chat }
function MessageUnreachable(aBot: TTelegramSender): Boolean;
begin
  { Explicit comparisons: FPC sets hold only 0..255, "[400,403]" is not usable }
  Result:=((aBot.LastErrorCode=400) or (aBot.LastErrorCode=403)) and
    (ContainsStr(aBot.LastErrorDescription, _tgErrChatNotFound) or
     ContainsStr(aBot.LastErrorDescription, _tgErrBotBlocked) or
     ContainsStr(aBot.LastErrorDescription, _tgErrBotCantInit));
end;

var
  _sBtnBtCmplnnt: String;


function RouteCmdSpam(aChat: Int64; aMsg: Integer; IsSpam: Boolean): String;
begin
  Result:=_dSpm+' '+aChat.ToString+' '+aMsg.ToString+' '+IsSpam.ToString;
end;

function RouteCmdReaction(aChat, aUser: Int64; IsSpam: Boolean): String;
begin
  Result:=_dSpm+' '+aChat.ToString+' '+aUser.ToString+' '+IsSpam.ToString+' '+'r';
end;

function RouteCmdSpamLastChecking(aChat: Int64; aMsg: Integer; IsConfirmation: Boolean): String;
var
  aSym: String;
begin
  if IsConfirmation then
    aSym:=_dtRC
  else
    aSym:=_dtR;
  Result:=_dSpm+' '+aChat.ToString+' '+aMsg.ToString+' '+aSym;
end;

function RouteMsgUsrPrvcy: String;
begin
  Result:='m'+' '+_dtUsrPrvcy;
end;

function RouteMsgCmplnntIsBt(): String;
begin
  Result:='m'+' '+_dtCmplnntIsBt;
end;

function RouteMsgPrbblySpm(aSpamProbability, aHamProbability: Double; aIsEmojiMarker: Boolean): String;
begin
  Result:='m'+' '+_dtPrbblySpm+' '+aSpamProbability.ToString+' '+aHamProbability.ToString;
  if aIsEmojiMarker then
    Result+=' '+'emj';
end;

function BuildMsgUrl(aChat: TTelegramChatObj; aMsgID: Integer = 0): String;
const
  _ChatIDPrefix='-100';
var
  aTpl, aChatName, aMsgIDStr: String;
begin
  aChatName:=aChat.Username;
  if aChatName.IsEmpty then
  begin
    aChatName:=aChat.ID.ToString;
    if StartsStr(_ChatIDPrefix, aChatName) then
      aChatName:=RightStr(aChatName, Length(aChatName)-Length(_ChatIDPrefix))
    else
      Exit('https://t.me/'); { #todo : Maybe other handling? }
    aTpl:='https://t.me/c/%s/%s';
  end
  else
    aTpl:='https://t.me/%s/%s';
  if aMsgID<>0 then
    aMsgIDStr:=aMsgID.ToString
  else
    aMsgIDStr:=EmptyStr;
  Result:=Format(aTpl, [aChatName, aMsgIDStr]);
end;

{ The thresholds are inclusive, as /settings shows them: a member with the
  exact PatrolRate is already a Patrol }
function DefenderStatusOf(aRate, aPatrolRate, aGuardRate: Integer): TDefenderStatus;
begin
  if aRate>=aGuardRate then
    Result:=dsGuard
  else
    if aRate>=aPatrolRate then
      Result:=dsPatrol
    else
      Result:=dsStandard;
end;

function DefenderMark(aStatus: TDefenderStatus): String;
begin
  case aStatus of
    dsPatrol: Result:=_emjPatrol;
    dsGuard:  Result:=_emjSheriff;
  else
    Result:=EmptyStr;
  end;
end;

function DefenderStatusText(aStatus: TDefenderStatus): String;
begin
  case aStatus of
    dsPatrol: Result:=DefenderMark(aStatus)+' '+_sLvlPatrol;
    dsGuard:  Result:=DefenderMark(aStatus)+' '+_sLvlGrd;
  else
    Result:=_sLvlStndrd;
  end;
end;

function DefenderTag(aRate, aPatrolRate, aGuardRate: Integer): String;
var
  aStatus: TDefenderStatus;
begin
  aStatus:=DefenderStatusOf(aRate, aPatrolRate, aGuardRate);
  if aStatus>=dsPatrol then
    Result:=' '+DefenderMark(aStatus)+aRate.ToString
  else
    Result:=EmptyStr;
end;

function NextRankHint(aRate, aPatrolRate, aGuardRate: Integer): String;
begin
  case DefenderStatusOf(aRate, aPatrolRate, aGuardRate) of
    dsStandard: Result:=Format(_sNxtRnk, [DefenderStatusText(dsPatrol), aPatrolRate-aRate]);
    dsPatrol:   Result:=Format(_sNxtRnk, [DefenderStatusText(dsGuard), aGuardRate-aRate]);
  else
    Result:=EmptyStr;
  end;
end;

{ TCurrentEvent }

procedure TCurrentEvent.AddMessage(aIsReaction: Boolean);
var
  aInspectedUserName: String;
  aComplainant: Int64;
begin
  aInspectedUserName:=CaptionFromUser(InspectedUser);
  if Assigned(Complainant) then
    aComplainant:=Complainant.ID
  else
    aComplainant:=0;
  ORM.AddMessage(aInspectedUserName, InspectedUser.ID, InspectedChat.ID, aComplainant, InspectedMessageID, _msSpam,
    aIsReaction);
end;

procedure TCurrentEvent.AssignInspectedFromMsg(aMessage: TTelegramMessageObj);
var
  aMedia: String;
begin
  FContentType:=aMessage.ContentFromMessage(FInspectedMessage, aMedia);
  FIsExternalReply:=Assigned(aMessage.ExternalReply);
  if FIsExternalReply and Assigned(aMessage.Quote) then
      FInspectedMessage+=LineEnding+aMessage.Quote.Text;
  FInspectedChat:=aMessage.Chat;
  FInspectedUser:=aMessage.From;
  FInspectedMessageID:=aMessage.MessageId;
end;

procedure TCurrentEvent.AssignInspectedFromRctn(aReactionUpdated: TTelegramMessageReactionUpdated);
begin
  FInspectedChat:=aReactionUpdated.Chat;
  FInspectedUser:=aReactionUpdated.User;
  FInspectedMessageID:=aReactionUpdated.MessageID;
  FNewReactions:=aReactionUpdated.NewReactions;
end;

function TCurrentEvent.GetInspectedIsNewbie: Boolean;
begin
  if not FNewbieKnown then
  begin
    FInspectedIsNewbie:=Assigned(FInspectedUser) and Assigned(FInspectedChat) and
      ORM.IsNewbieInChat(FInspectedChat.ID, FInspectedUser.ID);
    FNewbieKnown:=True;
  end;
  Result:=FInspectedIsNewbie;
end;

procedure TCurrentEvent.BanOrNotToBan(aInspectedChat, aInspectedUser: Int64; const aInspectedUserName: String;
  aInspectedMessage: LongInt; aIsSpam: Boolean);
var
  aMsg: String;
begin
  ORM.UpdateRatings(aInspectedChat, aInspectedMessage, aIsSpam);
  if aIsSpam then
  begin
    Bot.deleteMessage(aInspectedChat, aInspectedMessage);
    Bot.banChatMember(aInspectedChat, aInspectedUser);
    ORM.SaveUserSpamStatus(aInspectedUser, aInspectedUserName);
    aMsg:=_sInspctdMsgHsDlt;
  end
  else begin
    ORM.SaveUserSpamStatus(aInspectedUser, aInspectedUserName, False);
    aMsg:=_sInspctdMsgIsNtSpm;
  end;                                      
  if Assigned(Bot.CurrentUser) then
    Bot.sendMessage(Bot.CurrentUser.ID, aMsg);
end;

constructor TCurrentEvent.Create(aBot: TTelegramSender; aBotORM: TBotORM);
begin
  FBot:=aBot;
  FBotORM:=aBotORM;
  FComplainantRate:=-1;
  inherited Create;
end;

procedure TCurrentEvent.ProcessComplaint(aCanBeSilentBan: Boolean; aSpamStatus: Integer);
var
  aInspectedUserName: String;
  aIsFirstComplaint: Boolean;
  aComplainant: Int64;
begin
  aInspectedUserName:=CaptionFromUser(InspectedUser);
  if Assigned(Complainant) then
    aComplainant:=Complainant.ID
  else
    aComplainant:=0;
  ORM.GetNSaveMessage(aInspectedUserName, InspectedUser.ID, InspectedChat.ID, aComplainant, InspectedMessageID,
    aIsFirstComplaint, aSpamStatus);
  if aIsFirstComplaint then
    if not aCanBeSilentBan then
      SendMessagesToAdmins(aSpamStatus=_msSpam);
  if Assigned(Complainant) then
    ORM.AddComplaint(aComplainant, InspectedChat.ID, InspectedMessageID);
  if aSpamStatus=_msSpam then
    BanOrNotToBan(InspectedChat.ID, InspectedUser.ID, aInspectedUserName, InspectedMessageID, True);
end;

procedure TCurrentEvent.ProcessSpamReaction(aCanBeSilentBan: Boolean; aSpamStatus: Integer);
var
  aInspectedUserName: String;
  aIsFirstReaction: Boolean;
  aComplainant: Int64;
begin
  aInspectedUserName:=CaptionFromUser(InspectedUser);
  if Assigned(Complainant) then
    aComplainant:=Complainant.ID
  else
    aComplainant:=0;
  ORM.GetNSaveReaction(aInspectedUserName, InspectedUser.ID, InspectedChat.ID, aComplainant, InspectedMessageID,
    aIsFirstReaction, aSpamStatus);
  if aIsFirstReaction then
    if not aCanBeSilentBan then
      SendMessagesToAdmins(aSpamStatus=_msSpam, False, True);
  if Assigned(Complainant) then
    ORM.AddComplaint(aComplainant, InspectedChat.ID, InspectedMessageID);
  if aSpamStatus=_msSpam then
    BanReactionSpam(InspectedChat.ID, InspectedUser.ID, aInspectedUserName, True);
end;

function TCurrentEvent.IsGroup: Boolean;
begin
  Result:=Assigned(FInspectedUser) and (FInspectedUser.ID<>FInspectedChat.ID)
end;

procedure TCurrentEvent.ClassifyMessage(aSpamFilter: TSpamFilter);
var
  aSpamStatus: Integer;
  aAdditionalFactor: Double;
begin
  FEmojiMarker:=False;
  if CountEmojis(InspectedMessage)<Conf.SpamFilter.EmojiLimit then
  begin
    aSpamFilter.Classify(InspectedMessage, FHamProbability, FSpamProbability);
    case FContentType of
      { Reducing the spam factor threshold for auto ban }
      cntPhoto, cntVideo, cntAudio, cntVoice: aAdditionalFactor:=Conf.SpamFilter.MediaRatio;
    else
      aAdditionalFactor:=1
    end;
    if FIsExternalReply then
      aAdditionalFactor*=0.2;
    if SpamFactor>Conf.SpamFilter.DefinitelySpam*aAdditionalFactor then
      aSpamStatus:=_msSpam
    else
      if SpamFactor<Conf.SpamFilter.DefinitelyHam then
        { Definitely ham: nothing to store and no reason to bother administrators }
        Exit
      else
        aSpamStatus:=_msUnknown;
  end
  else begin
    FHamProbability:=0;
    FSpamProbability:=0;
    FEmojiMarker:=True;
    aSpamStatus:=_msSpam;
  end;
  ProcessComplaint(False, aSpamStatus);
end;

procedure TCurrentEvent.TrainFromMessage(aSpamFilter: TSpamFilter; aIsSpam: Boolean);
begin
  aSpamFilter.Train(InspectedMessage, aIsSpam);
end;

function TCurrentEvent.SpamFactor: Double;
begin
  Result:=FSpamProbability-FHamProbability;
end;

procedure TCurrentEvent.BanReactionSpam(aInspectedChat, aInspectedUser: Int64; const aInspectedUserName: String;
  aIsSpam: Boolean);
var
  aMsg: String;
begin
  if aIsSpam then
  begin
    Bot.banChatMember(aInspectedChat, aInspectedUser);
    ORM.SaveUserSpamStatus(aInspectedUser, aInspectedUserName);
    aMsg:=_sSpmRctnBnd;
  end
  else begin
    ORM.SaveUserSpamStatus(aInspectedUser, aInspectedUserName, False);
    Bot.unbanChatMember(aInspectedChat, aInspectedUser, True);
    aMsg:=_sSpmRctnIsNtSpm;
  end;
  if Assigned(Bot.CurrentUser) then
    Bot.sendMessage(Bot.CurrentUser.ID, aMsg);
end;

procedure TCurrentEvent.SendMessagesToAdmins(aIsDefinitlySpam: Boolean; aIsPreventively: Boolean; aIsReaction: Boolean);
var
  aChatMembers: TopfChatMembers.TEntities;
  aFailed: TInt64List;
  aIsUserPrivacy: Boolean;
  aChatMember: TChatMember;
  aUserID: Int64;
begin
  aChatMembers:=TopfChatMembers.TEntities.Create;
  aFailed:=TInt64List.Create;
  try
    ORM.GetModeratorsByChat(FInspectedChat.ID, aChatMembers);
    aIsUserPrivacy:=False;
    for aChatMember in aChatMembers do
      if aChatMember.Moderator then
      begin
        { Skip moderators marked unreachable by a previous attempt }
        if not aChatMember.NotifyOk then
          Continue;
        SendToModerator(aChatMember.User, aIsDefinitlySpam, aIsPreventively, aIsUserPrivacy, aIsReaction);
        if MessageUnreachable(Bot) then
          aFailed.Add(aChatMember.User);
      end;
    { Mark only after the iteration: reusing the ORM entity mid-iteration
      invalidates the list being walked (access violation) }
    for aUserID in aFailed do
    begin
      ORM.MarkModeratorUndeliverable(FInspectedChat.ID, aUserID);
      Bot.Logger.Error(Format('Moderator #%d does not receive notifications (chat not opened or bot blocked); skipped until the next /update', [aUserID]));
    end;
  finally
    aFailed.Free;
    aChatMembers.Free;
  end;
end;

{ aModerator - The one to whom the message is being sent from the bot
  aIsDefinitelySpam - True is considered to be a spammer.
    If not the moderator will be offered the choice to click: is the spammer being inspected or not?
  aIsPreventively - Means that the user was preemptively banned based on the available information.
  aIsUserPrivacy - If installed, then someone (the inspected person or the complainant) has strict privacy tg settings.
  }
procedure TCurrentEvent.SendToModerator(aModerator: Int64; aIsDefinitelySpam, aIsPreventively: Boolean;
  var aIsUserPrivacy: Boolean; aIsReaction: Boolean);
var
  aReplyMarkup: TReplyMarkup;
  aKB: TInlineKeyboard;
  aInspctdUsr, aCmplnnt, s: String;

  procedure AddVerdictBtnPair(const aSpmCmd, aHmCmd: String);
  var
    aBtn: TInlineKeyboardButton;
    aLine: TInlineKeyboardButtons;
  begin
    aLine:=aKB.Add;
    aBtn:=TInlineKeyboardButton.Create('Spam');
    aBtn.Style:='danger';
    aBtn.callback_data:=aSpmCmd;
    aLine.Add(aBtn);
    aBtn:=TInlineKeyboardButton.Create('Not Spam');
    aBtn.Style:='success';
    aBtn.callback_data:=aHmCmd;
    aLine.Add(aBtn);
  end;

  function InspctdCaption(const aLabel: String): String;
  begin
    if InspectedIsNewbie then
      Result:=_emjNewbie+' '+aLabel
    else
      Result:=aLabel;
  end;

begin
  aReplyMarkup:=TReplyMarkup.Create;
  try
    aKB:=aReplyMarkup.CreateInlineKeyBoard;
    if aIsDefinitelySpam then
    begin
      aInspctdUsr:= Format(_sBtnPair, [InspctdCaption(_sBndUsr), CaptionFromUser(InspectedUser)]);
      if Assigned(Complainant) then
        aCmplnnt:=Format(_sBtnPair, [_sCmplnnt, CaptionFromUser(Complainant)])+
          DefenderTag(FComplainantRate, Conf.PatrolRate, Conf.GuardRate)
      else
        aCmplnnt:=_sBtnBtCmplnnt;
      if aIsUserPrivacy  then
      begin
        aKB.Add.AddButton(aInspctdUsr, RouteMsgUsrPrvcy);
        if Assigned(Complainant) then
          aKB.Add.AddButton(aCmplnnt,  RouteMsgUsrPrvcy)
        else
          aKB.Add.AddButton(aCmplnnt, RouteMsgCmplnntIsBt);
      end
      else begin
        aKB.Add.AddButtonUrl(aInspctdUsr,  Format(_dTgUsrUrl, [FInspectedUser.ID]));
        if Assigned(Complainant) then
          aKB.Add.AddButtonUrl(aCmplnnt, Format(_dTgUsrUrl, [FComplainant.ID]))
        else
          aKB.Add.AddButton(aCmplnnt, RouteMsgCmplnntIsBt);
      end;
      if not aIsPreventively then
        aKB.Add.AddButton(_sIsErnsBn,
          RouteCmdSpamLastChecking(InspectedChat.ID, InspectedMessageID, True))
    end
    else begin
      if aIsReaction then
        AddVerdictBtnPair(RouteCmdReaction(InspectedChat.ID, InspectedUser.ID, True),
          RouteCmdReaction(InspectedChat.ID, InspectedUser.ID, False))
      else
        AddVerdictBtnPair(RouteCmdSpam(InspectedChat.ID, InspectedMessageID, True),
          RouteCmdSpam(InspectedChat.ID, InspectedMessageID, False));
      aKB.Add.AddButtonUrl(_sInspctdMsg, BuildMsgUrl(InspectedChat, InspectedMessageID));
      aInspctdUsr:=Format(_sBtnPair, [InspctdCaption(_sInspctdUsr), CaptionFromUser(InspectedUser)]);
      if aIsUserPrivacy then
        aKB.Add.AddButton(aInspctdUsr, RouteMsgUsrPrvcy)
      else
        aKB.Add.AddButtonUrl(aInspctdUsr,  Format(_dTgUsrUrl, [InspectedUser.ID]));
      if not Assigned(Complainant) then
        aKB.Add.AddButton(_sBtnBtCmplnnt, RouteMsgCmplnntIsBt);
    end;
    if Assigned(InspectedChat) then
      aKB.Add.AddButtonUrl(_emjMonocle+' '+InspectedChat.Username, BuildMsgUrl(InspectedChat));
    if not (aIsReaction or Assigned(Complainant) or aIsPreventively) then
    begin
      s:=_emjInfrmtn+' ';
      if (SpamFactor>0) or EmojiMarker then
        s+= _sMybItsSpm
      else
        s+=_sMybItsNtSpm;
      aKB.Add.AddButton(s, RouteMsgPrbblySpm(SpamProbability, HamProbability, EmojiMarker));
    end;
    if aIsReaction then
    begin
      if aIsDefinitelySpam then
        Bot.sendMessage(aModerator, Format(_sSpmRctn+LineEnding+_sPrvntvlyBnd,
          [InspectedUser.ID, CaptionFromUser(InspectedUser)]), pmMarkdown, aIsDefinitelySpam, aReplyMarkup)
      else
        Bot.sendMessage(aModerator, Format(_sIsThsRctnSpm, [NewReactions.CommaString]), pmDefault, False,
          aReplyMarkup);
    end
    else begin
      if aIsPreventively then
        Bot.sendMessage(aModerator, Format(_sPrvntvlyBnd, [InspectedUser.ID, CaptionFromUser(InspectedUser)]),
          pmMarkdown, aIsDefinitelySpam, aReplyMarkup)
      else
          Bot.copyMessage(aModerator, InspectedChat.ID, InspectedMessageID, aIsDefinitelySpam, aReplyMarkup);
    end;
  finally
    aReplyMarkup.Free;
  end;
  if not aIsUserPrivacy then
  begin
    aIsUserPrivacy:=(Bot.LastErrorCode=400) and ContainsStr(Bot.LastErrorDescription, _tgErrBtnUsrPrvcyRstrctd);
    if aIsUserPrivacy then
      SendToModerator(aModerator, aIsDefinitelySpam, aIsPreventively, aIsUserPrivacy, aIsReaction);
  end;
end;

initialization
  _sBtnBtCmplnnt:=Format(_emjbot+' '+_sBtnPair, [_sCmplnnt, 'the bot']);

end.


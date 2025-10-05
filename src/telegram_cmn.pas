unit telegram_cmn;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, tgtypes, tgsendertypes, adminhelper_orm, spamfilter
  ;

type

  { TCurrentEvent }

  TCurrentEvent = class
  private
    FBot: TTelegramSender;
    FComplainant: TTelegramUserObj;
    FBotORM: TBotORM;
    FEmojiMarker: Boolean;
    FInspectedChat: TTelegramChatObj;
    FInspectedMessage: String;
    FInspectedMessageID: Integer;
    FInspectedUser: TTelegramUserObj;
    FSpamProbability, FHamProbability: Double;
  protected
    property Bot: TTelegramSender read FBot;
    property ORM: TBotORM read FBotORM;
  public
    procedure AddMessage;
    procedure AssignInspectedFromMsg(aMessage: TTelegramMessageObj);
    procedure BanOrNotToBan(aInspectedChat, aInspectedUser: Int64; const aInspectedUserName: String;
      aInspectedMessage: LongInt; aIsSpam: Boolean);
    constructor Create(aBot: TTelegramSender; aBotORM: TBotORM);
    procedure ProcessComplaint(aCanBeSilentBan: Boolean; aSpamStatus: Integer);
    function IsGroup: Boolean;
    procedure ClassifyMessage(aSpamFilter: TSpamFilter);
    procedure TrainFromMessage(aSpamFilter: TSpamFilter; aIsSpam: Boolean);
    function SpamFactor: Double;
    procedure SendMessagesToAdmins(aIsDefinitlySpam: Boolean; aIsPreventively: Boolean = False);
    procedure SendToModerator(aModerator: Int64; aIsDefinitelySpam, aIsPreventively: Boolean;
      var aIsUserPrivacy: Boolean);
    property InspectedChat: TTelegramChatObj read FInspectedChat write FInspectedChat;
    property InspectedUser: TTelegramUserObj read FInspectedUser write FInspectedUser;
    property InspectedMessage: String read FInspectedMessage write FInspectedMessage;
    property InspectedMessageID: Integer read FInspectedMessageID write FInspectedMessageID;
    property Complainant: TTelegramUserObj read FComplainant write FComplainant;
    property SpamProbability: Double read FSpamProbability write FSpamProbability;
    property HamProbability: Double read FHamProbability write FHamProbability;
    property EmojiMarker: Boolean read FEmojiMarker write FEmojiMarker;
  end;

function RouteCmdSpamLastChecking(aChat: Int64; aMsg: Integer; IsConfirmation: Boolean): String; 
function RouteMsgUsrPrvcy: String;                        
function RouteMsgCmplnntIsBt(): String;   
function RouteMsgPrbblySpm(aSpamProbability, aHamProbability: Double; aIsEmojiMarker: Boolean = False): String;

const
  _sBtnPair='%s: %s';
  _dTgUsrUrl='tg://user?id=%d';
  _tgErrBtnUsrPrvcyRstrctd='Bad Request: BUTTON_USER_PRIVACY_RESTRICTED';  
  _dtUsrPrvcy='UsrPrvcy';      
  _dtCmplnntIsBt='CmplnntIsBt'; 
  _dtPrbblySpm='PrbblySpm'; 
  _dSpm = 'spam';
  _dtR= 'r';  // rollback ban action
  _dtRC='rc'; // confirmation of rollback ban action

resourcestring
  _sInspctdUsr='Inspected user';
  _sBndUsr=    'Banned user';

implementation

uses
  StrUtils, tgutils, adminhelper_conf, emojiutils
  ;

resourcestring
  _sPrvntvlyBnd= 'The user #`%0:d` [%1:s](tg://user?id=%0:d) was preventively banned';
  _sInspctdMsg=  'Inspected message';
  _sCmplnnt=     'Complainant';
  _sIsErnsBn=    'Is this erroneous ban?';
  _sMybItsSpm=   '"Probably it''s a spam". More info...';
  _sMybItsNtSpm= '"Probably it''s not a spam". More info...';
  _sInspctdMsgHsDlt=    'The message was successfully deleted and the spammer was banned';
  _sInspctdMsgIsNtSpm=  'The message is marked as NOT spam. Erroneous complaint';

const
  _emjbot='🤖'; 
  _emjInfrmtn='ℹ️';

var
  _sBtnBtCmplnnt: String;


function RouteCmdSpam(aChat: Int64; aMsg: Integer; IsSpam: Boolean): String;
begin
  Result:=_dSpm+' '+aChat.ToString+' '+aMsg.ToString+' '+IsSpam.ToString;
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

{ TCurrentEvent }

procedure TCurrentEvent.AddMessage;
var
  aInspectedUserName: String;
  aComplainant: Int64;
begin
  aInspectedUserName:=CaptionFromUser(InspectedUser);
  if Assigned(Complainant) then
    aComplainant:=Complainant.ID
  else
    aComplainant:=0;
  ORM.AddMessage(aInspectedUserName, InspectedUser.ID, InspectedChat.ID, aComplainant, InspectedMessageID, _msSpam);
end;

procedure TCurrentEvent.AssignInspectedFromMsg(aMessage: TTelegramMessageObj);
begin
  FInspectedMessage:=aMessage.Text;
  if FInspectedMessage.IsEmpty then
    FInspectedMessage:=aMessage.Caption;
  FInspectedChat:=aMessage.Chat;
  FInspectedUser:=aMessage.From;
  FInspectedMessageID:=aMessage.MessageId;
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

function TCurrentEvent.IsGroup: Boolean;
begin
  Result:=Assigned(FInspectedUser) and (FInspectedUser.ID<>FInspectedChat.ID)
end;

procedure TCurrentEvent.ClassifyMessage(aSpamFilter: TSpamFilter);
var
  aSpamStatus: Integer;
begin
  FEmojiMarker:=False;
  if CountEmojis(InspectedMessage)<Conf.SpamFilter.EmojiLimit then
  begin
    aSpamFilter.Classify(InspectedMessage, FHamProbability, FSpamProbability);
    if SpamFactor>Conf.SpamFilter.DefinitelySpam then
      aSpamStatus:=_msSpam
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

procedure TCurrentEvent.SendMessagesToAdmins(aIsDefinitlySpam: Boolean; aIsPreventively: Boolean);
var
  aChatMembers: TopfChatMembers.TEntities;
  aIsUserPrivacy: Boolean;
  aChatMember: TChatMember;
begin
  aChatMembers:=TopfChatMembers.TEntities.Create;
  try
    ORM.GetModeratorsByChat(FInspectedChat.ID, aChatMembers);
    aIsUserPrivacy:=False;
    for aChatMember in aChatMembers do
      if aChatMember.Moderator then
        SendToModerator(aChatMember.User, aIsDefinitlySpam, aIsPreventively, aIsUserPrivacy);
  finally
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
  var aIsUserPrivacy: Boolean);
var
  aReplyMarkup: TReplyMarkup;
  aKB: TInlineKeyboard;
  aInspctdUsr, aCmplnnt, s: String;
begin
  aReplyMarkup:=TReplyMarkup.Create;
  try
    aKB:=aReplyMarkup.CreateInlineKeyBoard;
    if aIsDefinitelySpam then
    begin
      aInspctdUsr:= Format(_sBtnPair, [_sBndUsr, CaptionFromUser(InspectedUser)]);
      if Assigned(Complainant) then
        aCmplnnt:=Format(_sBtnPair, [_sCmplnnt, CaptionFromUser(Complainant)])
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
      aKB.Add.AddButtons(
        ['It is spam', RouteCmdSpam(InspectedChat.ID, InspectedMessageID, True),
        'It isn''t spam!', RouteCmdSpam(InspectedChat.ID, InspectedMessageID, False)]
      );
      aKB.Add.AddButtonUrl(_sInspctdMsg, BuildMsgUrl(InspectedChat, InspectedMessageID));
      aInspctdUsr:=Format(_sBtnPair, [_sInspctdUsr, CaptionFromUser(InspectedUser)]);
      if aIsUserPrivacy then
        aKB.Add.AddButton(aInspctdUsr, RouteMsgUsrPrvcy)
      else
        aKB.Add.AddButtonUrl(aInspctdUsr,  Format(_dTgUsrUrl, [InspectedUser.ID]));
      if not Assigned(Complainant) then
        aKB.Add.AddButton(_sBtnBtCmplnnt, RouteMsgCmplnntIsBt);
    end;
    if not (Assigned(Complainant) or aIsPreventively) then
    begin
      s:=_emjInfrmtn+' ';
      if (SpamFactor>0) or EmojiMarker then
        s+= _sMybItsSpm
      else
        s+=_sMybItsNtSpm;
      aKB.Add.AddButton(s, RouteMsgPrbblySpm(SpamProbability, HamProbability, EmojiMarker));
    end;
    if aIsPreventively then
      Bot.sendMessage(aModerator, Format(_sPrvntvlyBnd, [InspectedUser.ID,
        CaptionFromUser(InspectedUser)]), pmMarkdown, aIsDefinitelySpam, aReplyMarkup)
    else
      Bot.copyMessage(aModerator, InspectedChat.ID, InspectedMessageID, aIsDefinitelySpam, aReplyMarkup);
  finally
    aReplyMarkup.Free;
  end;
  if not aIsUserPrivacy then
  begin
    aIsUserPrivacy:=(Bot.LastErrorCode=400) and ContainsStr(Bot.LastErrorDescription, _tgErrBtnUsrPrvcyRstrctd);
    if aIsUserPrivacy then
      SendToModerator(aModerator, aIsDefinitelySpam, aIsPreventively, aIsUserPrivacy);
  end;
end;

initialization
  _sBtnBtCmplnnt:=Format(_emjbot+' '+_sBtnPair, [_sCmplnnt, 'the bot']);

end.


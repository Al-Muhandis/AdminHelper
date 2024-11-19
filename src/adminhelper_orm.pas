unit adminhelper_orm;

{$mode ObjFPC}{$H+}

interface

uses
  dSQLdbBroker, SysUtils, classes, fgl, mysql80conn, brk_tg_config, fpjson, adminhelper_conf
  ;

type
  THelperObjctRoot = class(TObject)
  public
    procedure Clear; virtual; abstract;
  end;

  { TBotUser }

  TBotUser = class(THelperObjctRoot)
  private
    FAppearance: Int64;
    FName: String;
    FRate: Integer;
    FId: Int64;
    FSpammer: Integer;
    function GetAppearanceAsDateTime: TDateTime;
    procedure SetAppearanceAsDateTime(AValue: TDateTime);
  public
    procedure Clear; override;
    function IsNewbie: Boolean;
    property AppearanceAsDateTime: TDateTime read GetAppearanceAsDateTime write SetAppearanceAsDateTime;
  published
    property ID: Int64 read FId write FId;
    property Name: String read FName write FName;
    property Rate: Integer read FRate write FRate;
    property Spammer: Integer read FSpammer write FSpammer;
    property Appearance: Int64 read FAppearance write FAppearance;
  end;

  { TChatMember }

  TChatMember = class(THelperObjctRoot)
  private
    FChat: Int64;
    FModerator: Boolean;
    FUser: Int64;
  public
    procedure Clear; override;
  published
    property Chat: Int64 read FChat write FChat;
    property User: Int64 read FUser write FUser;
    property Moderator: Boolean read FModerator write FModerator;
  end;

  { TTelegramMessage }

  TTelegramMessage = class(THelperObjctRoot)
  private
    FChat: Int64;
    FExecutor: Int64;
    FUser: Int64;
    FIsSpam: Integer;
    FMessage: Integer;
    FUserName: String;
  public
    procedure Clear; override;
  published
    property Chat: Int64 read FChat write FChat;
    property Message: Integer read FMessage write FMessage;
    property User: Int64 read FUser write FUser;
    property IsSpam: Integer read FIsSpam write FIsSpam;
    property Executor: Int64 read FExecutor write FExecutor;  
    property UserName: String read FUserName write FUserName;
  end;

  { TComplaint }

  TComplaint = class(THelperObjctRoot)
  private
    FChat: Int64;
    FComplainant: Int64;
    FID: Integer;
    FMessage: Integer;
  public
    procedure Clear; override;
  published
    property ID: Integer read FID write FID;
    property Chat: Int64 read FChat write FChat;
    property Message: Integer read FMessage write FMessage;
    property Complainant: Int64 read FComplainant write FComplainant;
  end;

  TopfBotUsers = specialize TdGSQLdbEntityOpf<TBotUser>;  
  TopfMessages = specialize TdGSQLdbEntityOpf<TTelegramMessage>;  
  TopfComplaints = specialize TdGSQLdbEntityOpf<TComplaint>;      
  TopfChatMembers = specialize TdGSQLdbEntityOpf<TChatMember>;

  TInt64List = specialize TFPGList<Int64>;

  { TBotORM }

  TBotORM = class
  private
    FCon: TdSQLdbConnector;
    FDBConfig: TDBConf;
    FopChatMembers: TopfChatMembers;
    FopComplaints: TopfComplaints;
    FopMessages: TopfMessages;
    FopUsers: TopfBotUsers;                       
    procedure AddChatMember(aChat, aUser: Int64; aModerator: Boolean); // Without Apply table
    function Con: TdSQLdbConnector;
    class procedure CreateDB({%H-}aConnection: TdSQLdbConnector);
    function GetMessage: TTelegramMessage;
    function GetopChatMembers: TopfChatMembers;
    function GetopComplaints: TopfComplaints;
    function GetopMessages: TopfMessages;
    function GetopUsers: TopfBotUsers;                           
    function GetUser: TBotUser;
  protected
    property opMessages: TopfMessages read GetopMessages;
    property opComplaints: TopfComplaints read GetopComplaints; 
    property opChatMembers: TopfChatMembers read GetopChatMembers;   
    property opUsers: TopfBotUsers read GetopUsers;
  public
    procedure AddChatMembers(aChat: Int64; aModerator: Boolean; aUsers: TInt64List);
    procedure AddComplaint(aComplainant, aInspectedChat: Int64; aInspectedMessage: Integer);
    procedure ClearModeratorsForChat(aChat: Int64);
    constructor Create(aDBConf: TDBConf);
    destructor Destroy; override;
    function GetMessage(aInspectedChat: Int64; aInspectedMessage: Integer): Boolean;
    procedure GetModeratorsByChat(aChat: Int64; aModerators: TopfChatMembers.TEntities);
    procedure SaveMessage(const aInspectedUserName: String; aInspectedUser, aInspectedChat, aExecutor: Int64;
      aInspectedMessage: Integer; out aIsNotifyAdmins: Boolean; aSpamStatus: Integer = 0);
    function GetUserByID(aUserID: Int64): Boolean;
    function IsModerator(aChat, aUser: Int64): Boolean;
    function ModifyMessageIfNotChecked(aIsSpam: Boolean; aExecutor: Int64 = 0): Boolean;
    procedure UpdateRatings(aChatID: Int64; aMsgID: LongInt; aIsSpam: Boolean; aIsRollback: Boolean = False;
      aExecutor: Int64 = 0);
    procedure SaveUserAppearance(aIsNew: Boolean);
    procedure SaveUserSpamStatus(aUserID: Int64; const aUserName: String; aIsSpammer: Boolean = True);
    procedure SaveUser(aIsNew: Boolean);
    function UserByID(aUserID: Int64): TBotUser;
    property DBConfig: TDBConf read FDBConfig write FDBConfig;
    property Message: TTelegramMessage read GetMessage;
    property User: TBotUser read GetUser;
  end;

const
    _msUnknown = 0;
    _msSpam    = 1;
    _msNotSpam = -1;

    _Penalty = 6;

implementation

uses
  dOpf, DateUtils
  ;

{ TBotUser }

procedure TBotUser.SetAppearanceAsDateTime(AValue: TDateTime);
begin
  FAppearance:=DateTimeToUnix(AValue, False);
end;

function TBotUser.GetAppearanceAsDateTime: TDateTime;
begin
  Result:=UnixToDateTime(FAppearance, False);
end;

procedure TBotUser.Clear;
begin
  FName:=EmptyStr;
  FRate:=0;
  FAppearance:=0;
  FSpammer:=_msUnknown;
end;

function TBotUser.IsNewbie: Boolean;
begin
  Result:=((Now-AppearanceAsDateTime)<=Conf.NewbieDays) and (Rate<1)
end;

{ TChatMember }

procedure TChatMember.Clear;
begin
  FChat:=0;
  FUser:=0;
  FModerator:=False;
end;

{ TTelegramMessage }

procedure TTelegramMessage.Clear;
begin
  FMessage:=0;
  FChat:=0;
  FUser:=0;
  FIsSpam:=0;
  FExecutor:=0;
  FUserName:=EmptyStr;
end;

{ TComplaint }

procedure TComplaint.Clear;
begin
  FChat:=0;
  FComplainant:=0;
  FMessage:=0;
end;

{ TBotORM }

function TBotORM.GetopUsers: TopfBotUsers;
begin
  if not Assigned(FopUsers) then
  begin
    FopUsers:=TopfBotUsers.Create(Con, 'users');
    FopUsers.Table.PrimaryKeys.Text:='id';
    FopUsers.FieldQuote:='`';
  end;
  Result:=FopUsers;
end;

function TBotORM.GetopMessages: TopfMessages;
begin
  if not Assigned(FopMessages) then
  begin
    FopMessages:=TopfMessages.Create(Con, 'messages');
    FopMessages.Table.PrimaryKeys.DelimitedText:='chat,message';
    FopMessages.FieldQuote:='`';
  end;
  Result:=FopMessages;
end;

function TBotORM.GetopComplaints: TopfComplaints;
begin
  if not Assigned(FopComplaints) then
  begin
    FopComplaints:=TopfComplaints.Create(Con, 'complaints');
    FopComplaints.Table.PrimaryKeys.DelimitedText:='id';
    FopComplaints.FieldQuote:='`';
  end;
  Result:=FopComplaints;
end;

function TBotORM.GetMessage: TTelegramMessage;
begin
  Result:=opMessages.Entity;
end;

function TBotORM.GetopChatMembers: TopfChatMembers;
begin
  if not Assigned(FopChatMembers) then
  begin
    FopChatMembers:=TopfChatMembers.Create(Con, 'chatmembers');
    FopChatMembers.Table.PrimaryKeys.DelimitedText:='chat,user';
    FopChatMembers.FieldQuote:='`';
  end;
  Result:=FopChatMembers;
end;

function TBotORM.Con: TdSQLdbConnector;
var
  aDir: String;

  procedure DBConnect;
  begin
    FCon.Database:= FDBConfig.Database;
    FCon.User:=     FDBConfig.User;
    FCon.Host:=     FDBConfig.Host;
    FCon.Password:= FDBConfig.Password;
    FCon.Driver :=  FDBConfig.Driver;
  end;

begin
  if not Assigned(FCon) then
  begin
    FCon := TdSQLdbConnector.Create(nil);
    aDir:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));
    FCon.Logger.Active := FDBConfig.Logger.Active;
    DBConnect;
    if FDBConfig.Logger.FileName.IsEmpty then
      FCon.Logger.FileName := aDir+'db_sql.log'
    else
      FCon.Logger.FileName := aDir+FDBConfig.Logger.FileName;
  end;
  Result := FCon;
end;

class procedure TBotORM.CreateDB(aConnection: TdSQLdbConnector);
begin
  { #todo : Create tables }
end;

function TBotORM.GetUser: TBotUser;
begin
  Result:=opUsers.Entity;
end;

procedure TBotORM.AddChatMember(aChat, aUser: Int64; aModerator: Boolean);
begin
  opChatMembers.Entity.Chat:=aChat;
  opChatMembers.Entity.User:=aUser;
  opChatMembers.Entity.Moderator:=aModerator;
  opChatMembers.Add(False);
end;

procedure TBotORM.AddChatMembers(aChat: Int64; aModerator: Boolean; aUsers: TInt64List);
var
  aUserID: Int64;
begin
  for aUserID in aUsers do
    AddChatMember(aChat, aUserID, aModerator);
  opChatMembers.Apply;
end;

procedure TBotORM.AddComplaint(aComplainant, aInspectedChat: Int64; aInspectedMessage: Integer);
begin
  with opComplaints do
  begin
    Entity.Chat:=       aInspectedChat;
    Entity.Message:=    aInspectedMessage;
    Entity.Complainant:=aComplainant;
    if Find('chat=:chat AND message=:message AND complainant=:complainant') then
      Exit;
    Add(True);
    Apply;
    Con.Logger.LogFmt(ltCustom, '#DebugInfo: сomplaint (chat #%d, message #%d, complainant #%d) has been added',
      [aInspectedChat, aInspectedMessage, aComplainant]);
  end;
end;

procedure TBotORM.ClearModeratorsForChat(aChat: Int64);
var
  aChatMembers: TopfChatMembers.TEntities;
  aChatMember: TChatMember;
begin
  aChatMembers:=TopfChatMembers.TEntities.Create();
  try
    GetModeratorsByChat(aChat, aChatMembers);
    for aChatMember in aChatMembers do
      opChatMembers.Remove(aChatMember);
    opChatMembers.Apply;
  finally
    aChatMembers.Free;
  end;
end;

  { You must to notify administrators if there is no yet the inspected message
    or if a spam command is sending by patrol member }
procedure TBotORM.SaveMessage(const aInspectedUserName: String; aInspectedUser, aInspectedChat, aExecutor: Int64;
  aInspectedMessage: Integer; out aIsNotifyAdmins: Boolean; aSpamStatus: Integer);
begin
  aIsNotifyAdmins:=not GetMessage(aInspectedChat, aInspectedMessage); // Notify if there is a first complaint
  { No need to save message if there is not a first complaint and SpamStatus is unknown }
  if not aIsNotifyAdmins and (aSpamStatus=_msUnknown) then
    Exit;
  Message.User:=aInspectedUser;
  Message.IsSpam:=aSpamStatus;
  Message.Executor:=aExecutor;
  Message.UserName:=aInspectedUserName;
  if aIsNotifyAdmins then
    opMessages.Add(False)
  else
    opMessages.Modify(False);
  opMessages.Apply;
end;

constructor TBotORM.Create(aDBConf: TDBConf);
begin
  FDBConfig:=aDBConf;
end;

destructor TBotORM.Destroy;
begin
  FopChatMembers.Free;
  FopComplaints.Free;
  FopMessages.Free;
  FopUsers.Free;
  FCon.Free;
  inherited Destroy;
end;

procedure TBotORM.UpdateRatings(aChatID: Int64; aMsgID: LongInt; aIsSpam: Boolean; aIsRollback: Boolean;
  aExecutor: Int64);
var
  aComplaints: TopfComplaints.TEntities;
  aComplaint: TComplaint;
  aRate: Integer;
  aIsNew: Boolean;
begin
  opComplaints.Entity.Chat:=   aChatId;
  opComplaints.Entity.Message:=aMsgID;
  aComplaints:=TopfComplaints.TEntities.Create();
  try
    if opComplaints.Find(aComplaints, 'chat=:chat AND message=:message') then
      for aComplaint in aComplaints do
      begin
        aIsNew:=not GetUserByID(aComplaint.Complainant);
        aRate:=opUsers.Entity.Rate;
        if opUsers.Entity.Appearance=0 then
          opUsers.Entity.AppearanceAsDateTime:=Now;
        if aIsSpam then
        begin
          if not aIsRollback then
            Inc(aRate)
          else begin
            Dec(aRate);
            { Zeroing guard rating }
            if aExecutor=aComplaint.Complainant then
              aRate:=0;
          end;
        end
        else begin
          if not aIsRollback then
            Dec(aRate, _Penalty)
          else
            Inc(aRate, _Penalty);
        end;
        opUsers.Entity.Rate:=aRate;
        SaveUser(aIsNew);
      end;
  finally
    aComplaints.Free;
  end;
end;
   { We assign an Appearance only if it is 0 (not defined yet) }
procedure TBotORM.SaveUserAppearance(aIsNew: Boolean);
begin
  if opUsers.Entity.Appearance=0 then
    opUsers.Entity.AppearanceAsDateTime:=Now
  else
    Exit;
  SaveUser(aIsNew);
end;

procedure TBotORM.SaveUserSpamStatus(aUserID: Int64; const aUserName: String; aIsSpammer: Boolean);
var
  aIsNew: Boolean;
begin
  aIsNew:=not GetUserByID(aUserID);
  User.Name:=aUserName;
  if aIsSpammer then
    opUsers.Entity.Spammer:=_msSpam
  else                       
    opUsers.Entity.Spammer:=_msNotSpam;
  SaveUser(aIsNew);
end;

procedure TBotORM.SaveUser(aIsNew: Boolean);
begin
  if aIsNew then
    opUsers.Add(False)
  else
    opUsers.Modify(False);
  opUsers.Apply;
end;

function TBotORM.GetUserByID(aUserID: Int64): Boolean;
begin
  opUsers.Entity.ID:=aUserID;
  Result:=opUsers.Get();
  if not Result then
    opUsers.Entity.Clear;
end;

function TBotORM.IsModerator(aChat, aUser: Int64): Boolean;
begin
  Result:=False;
  opChatMembers.Entity.Chat:=aChat;
  opChatMembers.Entity.User:=aUser;
  if opChatMembers.Get() then
    Result:=opChatMembers.Entity.Moderator;
end;

function TBotORM.ModifyMessageIfNotChecked(aIsSpam: Boolean; aExecutor: Int64): Boolean;
begin
  Result:=Message.IsSpam=_msUnknown;
  if Result then
  begin
    if aIsSpam then
      Message.IsSpam:=_msSpam
    else
      Message.IsSpam:=_msNotSpam;
    Message.Executor:=aExecutor;
    opMessages.Modify(False);
    opMessages.Apply;
  end;
end;

function TBotORM.GetMessage(aInspectedChat: Int64; aInspectedMessage: Integer): Boolean;
begin
  Message.Chat:=   aInspectedChat;
  Message.Message:=aInspectedMessage;
  Result:= opMessages.Get();
end;

procedure TBotORM.GetModeratorsByChat(aChat: Int64; aModerators: TopfChatMembers.TEntities);
begin
  opChatMembers.Entity.Chat:=aChat;
  opChatMembers.Find(aModerators, 'chat=:chat');
end;

function TBotORM.UserByID(aUserID: Int64): TBotUser;
begin
  GetUserByID(aUserID);
  Result:=opUsers.Entity;
end;

end.


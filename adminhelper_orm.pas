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
    FName: String;
    FRate: Integer;
    FId: Int64;
  public
    procedure Clear; override;
  published
    property ID: Int64 read FId write FId;
    property Name: String read FName write FName;
    property Rate: Integer read FRate write FRate;
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
    FUser: Int64;
    FIsSpam: Integer;
    FMessage: Integer;
  public
    procedure Clear; override;
  published
    property Chat: Int64 read FChat write FChat;
    property Message: Integer read FMessage write FMessage;
    property User: Int64 read FUser write FUser;
    property IsSpam: Integer read FIsSpam write FIsSpam;
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
    function GetMessage: TTelegramMessage;
    function GetopChatMembers: TopfChatMembers;
    function GetopComplaints: TopfComplaints;
    function GetopMessages: TopfMessages;
    function GetopUsers: TopfBotUsers;
    function Con: TdSQLdbConnector;
    class procedure CreateDB({%H-}aConnection: TdSQLdbConnector);
  protected
    property opUsers: TopfBotUsers read GetopUsers;
    property opMessages: TopfMessages read GetopMessages;
    property opComplaints: TopfComplaints read GetopComplaints; 
    property opChatMembers: TopfChatMembers read GetopChatMembers;
  public
    procedure AddChatMembers(aChat: Int64; aModerator: Boolean; aUsers: TInt64List);
    procedure AddComplaint(aComplainant, aInspectedChat: Int64; aInspectedMessage: Integer);
    procedure ClearModeratorsForChat(aChat: Int64);
    constructor Create(aDBConf: TDBConf);
    destructor Destroy; override;
    function GetMessage(aInspectedChat: Int64; aInspectedMessage: Integer): Boolean;
    procedure GetModeratorsByChat(aChat: Int64; aModerators: TopfChatMembers.TEntities);
    procedure SaveMessage(aInspectedUser, aInspectedChat: Int64; aInspectedMessage: Integer;
      out aIsNotifyAdmins: Boolean; aSpamStatus: Integer = 0);
    function GetUserByID(aUserID: Int64): Boolean;
    function IsModerator(aChat, aUser: Int64): Boolean;
    function ModifyMessageIfNotChecked(aIsSpam: Boolean): Boolean;   
    procedure UpdateRatings(aInspectorID, aChatID: Int64; aMsgID: LongInt; aIsSpam: Boolean);
    function UserByID(aUserID: Int64): TBotUser;
    property DBConfig: TDBConf read FDBConfig write FDBConfig;
    property Message: TTelegramMessage read GetMessage;
  end;

const
    _msUnknown = 0;
    _msSpam    = 1;
    _msNotSpam = -1;

    _Penalty = 6;

implementation

uses
  dOpf
  ;

{ TBotUser }

procedure TBotUser.Clear;
begin
  FName:=EmptyStr;
  FRate:=0;
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
procedure TBotORM.SaveMessage(aInspectedUser, aInspectedChat: Int64; aInspectedMessage: Integer; out
  aIsNotifyAdmins: Boolean; aSpamStatus: Integer);
begin
  aIsNotifyAdmins:=not GetMessage(aInspectedChat, aInspectedMessage);
  if aIsNotifyAdmins then
  begin
    opMessages.Entity.User:=aInspectedUser;
    opMessages.Entity.IsSpam:=aSpamStatus;
    opMessages.Add(False);
    opMessages.Apply;
  end;
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

procedure TBotORM.UpdateRatings(aInspectorID, aChatID: Int64; aMsgID: LongInt; aIsSpam: Boolean);
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
      begin                    {
        if aInspectorID=aComplaint.Complainant then
          Continue;               }
        aIsNew:=not GetUserByID(aComplaint.Complainant);
        aRate:=opUsers.Entity.Rate;
        if aIsSpam then
          Inc(aRate)
        else
          Dec(aRate, _Penalty);
        opUsers.Entity.Rate:=aRate;
        if not aIsNew then
          opUsers.Modify(False)
        else
          opUsers.Add(False);
        opUsers.Apply;
        Con.Logger.LogFmt(ltCustom, '#DebugInfo: the member (#%d) rating (now: %d p.) has been updated. Inspector: #%d',
          [aComplaint.Complainant, aRate, aInspectorID]);
      end;
  finally
    aComplaints.Free;
  end;
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

function TBotORM.ModifyMessageIfNotChecked(aIsSpam: Boolean): Boolean;
begin
  Result:=Message.IsSpam=0;
  if Result then
  begin
    if aIsSpam then
      Message.IsSpam:=1
    else
      Message.IsSpam:=-1;
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
  if not GetUserByID(aUserID) then
    opUsers.Entity.Clear;
  Result:=opUsers.Entity;
end;

end.


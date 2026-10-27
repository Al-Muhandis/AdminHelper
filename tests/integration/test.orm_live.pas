unit test.orm_live;
{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, SQLDB, fpcunit, testutils, testregistry,
  adminhelper_orm, brk_tg_config;

type
  { Integration tests against a real MySQL. They run only when
    TGADMIN_TEST_DB_USER (and optionally TGADMIN_TEST_DB_HOST / _NAME /
    _PASSWORD / _DRIVER) point to a DISPOSABLE schema: SetUp drops and
    recreates every table from src/db_schema.sql. Without the variables the
    tests exit vacuously, so a plain unit-test run stays green }
  TTestORMLive = class(TTestCase)
  private
    FConf: TDBConf;
    function Enabled: Boolean;
    function MakeConn: TSQLConnection;
    procedure RecreateSchema;
    procedure KillOtherConnections(aConn: TSQLConnection);
    function NewORM: TBotORM;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SaveAndReadBackMessage;
    procedure SecondComplaintIsNotFirst;
    procedure ComplaintNotDuplicated;
    procedure ModeratorRoundtripKeepsNotifyOk;
    procedure MembershipNewbieDetection;
    procedure GetMessageReconnectsAfterKill;
  end;

implementation

uses
  mysql80conn;

function TTestORMLive.Enabled: Boolean;
begin
  Result:=GetEnvironmentVariable('TGADMIN_TEST_DB_USER')<>EmptyStr;
end;

function TTestORMLive.MakeConn: TSQLConnection;
begin
  { TSQLConnector.ConnectorType lookup does not resolve mysql80: FPC 3.2.2's
    mysql80conn registers no TConnectionDef, so the class is used directly }
  Result:=TMySQL80Connection.Create(nil);
  Result.HostName:=FConf.Host;
  Result.DatabaseName:=FConf.Database;
  Result.UserName:=FConf.User;
  Result.Password:=FConf.Password;
  Result.Transaction:=TSQLTransaction.Create(Result);
  Result.Connected:=True;
end;

procedure TTestORMLive.RecreateSchema;
var
  Conn: TSQLConnection;
  Lines, Stmts: TStringList;
  s: String;
  i, j, p: Integer;
  aTables: array[0..5] of String = ('chatmembers','complaints','memberships',
    'messages','reactions','users');

  function FindSchemaFile: String;
  const
    Candidates: array[0..4] of String = (
      '', { reserved for TGADMIN_SCHEMA_PATH }
      'db_schema.sql',
      '..\..\src\db_schema.sql',
      '../../src/db_schema.sql',
      '..\src\db_schema.sql'
    );
  var
    k: Integer;
    aEnv: String;
  begin
    aEnv:=GetEnvironmentVariable('TGADMIN_SCHEMA_PATH');
    for k:=Low(Candidates) to High(Candidates) do
    begin
      if k=Low(Candidates) then
      begin
        if aEnv=EmptyStr then
          Continue;
        Result:=aEnv;
      end
      else
        Result:=Candidates[k];
      if FileExists(Result) then
        Exit;
    end;
    Result:=EmptyStr;
  end;

begin
  Conn:=MakeConn;
  try
    for i:=Low(aTables) to High(aTables) do
      Conn.ExecuteDirect('DROP TABLE IF EXISTS `'+aTables[i]+'`');
    { The schema file has no strings with a semicolon inside, so splitting on
      ';' is safe }
    Lines:=TStringList.Create;
    Stmts:=TStringList.Create;
    try
      Lines.LoadFromFile(FindSchemaFile);
      s:=EmptyStr;
      for i:=0 to Lines.Count-1 do
      begin
        s:=s+' '+Trim(Lines[i]);
        if s.EndsWith(';') then
        begin
          Stmts.Add(s);
          s:=EmptyStr;
        end;
      end;
      for i:=0 to Stmts.Count-1 do
      begin
        p:=Pos(';', Stmts[i]);
        Conn.ExecuteDirect(Copy(Stmts[i], 1, p-1));
      end;
    finally
      Stmts.Free;
      Lines.Free;
    end;
  finally
    Conn.Free;
  end;
end;

procedure TTestORMLive.KillOtherConnections(aConn: TSQLConnection);
var
  Q: TSQLQuery;
  aVictims: TStringList;
  i, aID: Integer;
begin
  aVictims:=TStringList.Create;
  try
    Q:=TSQLQuery.Create(nil);
    try
      Q.Database:=aConn;
      Q.Transaction:=aConn.Transaction;
      Q.SQL.Text:='SELECT id FROM information_schema.PROCESSLIST '+
        'WHERE db='''+FConf.Database+''' AND id<>CONNECTION_ID()';
      Q.Open;
      while not Q.EOF do
      begin
        aVictims.Add(Q.Fields[0].AsString);
        Q.Next;
      end;
      Q.Close;
    finally
      Q.Free;
    end;
    for i:=0 to aVictims.Count-1 do
    begin
      aID:=StrToIntDef(aVictims[i], 0);
      if aID<>0 then
        aConn.ExecuteDirect('KILL '+IntToStr(aID));
    end;
  finally
    aVictims.Free;
  end;
end;

function TTestORMLive.NewORM: TBotORM;
begin
  Result:=TBotORM.Create(FConf);
  Result.LogFileName:='test_orm.log';
end;

procedure TTestORMLive.SetUp;
begin
  if not Enabled then
    Exit;
  FConf:=TDBConf.Create;
  FConf.Host:=GetEnvironmentVariable('TGADMIN_TEST_DB_HOST');
  if FConf.Host=EmptyStr then
    FConf.Host:='localhost'; { matches the tgadmin'@'localhost' grant }

  FConf.Database:=GetEnvironmentVariable('TGADMIN_TEST_DB_NAME');
  if FConf.Database=EmptyStr then
    FConf.Database:='tgadmin_test';
  FConf.User:=GetEnvironmentVariable('TGADMIN_TEST_DB_USER');
  FConf.Password:=GetEnvironmentVariable('TGADMIN_TEST_DB_PASSWORD');
  FConf.Driver:=GetEnvironmentVariable('TGADMIN_TEST_DB_DRIVER');
  if FConf.Driver=EmptyStr then
    FConf.Driver:='mysql 8.0';
  RecreateSchema;
end;

procedure TTestORMLive.TearDown;
begin
  FreeAndNil(FConf);
end;

procedure TTestORMLive.SaveAndReadBackMessage;
var
  ORM: TBotORM;
  aFirst: Boolean;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    ORM.GetNSaveMessage('Spam Bot', 777, -100500, 42, 1001, aFirst, _msSpam);
    AssertTrue('first complaint must be reported as first', aFirst);
    AssertTrue('the saved message must be found', ORM.GetMessage(-100500, 1001));
    AssertTrue('user must be stored', ORM.Message.User=777);
    AssertTrue('spam status must be stored', ORM.Message.IsSpam=_msSpam);
    AssertTrue('executor must be stored', ORM.Message.Executor=42);
    AssertTrue('username must be stored', ORM.Message.UserName='Spam Bot');
    AssertTrue('createdat must be stamped', ORM.Message.CreatedAt>0);
  finally
    ORM.Free;
  end;
end;

procedure TTestORMLive.SecondComplaintIsNotFirst;
var
  ORM: TBotORM;
  aFirst: Boolean;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    ORM.GetNSaveMessage('Spam Bot', 777, -100500, 42, 1001, aFirst, _msSpam);
    ORM.GetNSaveMessage('Spam Bot', 777, -100500, 43, 1001, aFirst, _msSpam);
    AssertFalse('second complaint must not be reported as first', aFirst);
    AssertTrue('original executor must survive the second complaint',
      ORM.Message.Executor=42);
  finally
    ORM.Free;
  end;
end;

procedure TTestORMLive.ComplaintNotDuplicated;
var
  ORM: TBotORM;
  Conn: TSQLConnection;
  Q: TSQLQuery;
  aFirst: Boolean;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    ORM.GetNSaveMessage('Spam Bot', 777, -100500, 42, 1001, aFirst, _msSpam);
    ORM.AddComplaint(42, -100500, 1001);
    ORM.AddComplaint(42, -100500, 1001);
    Conn:=MakeConn;
    try
      Q:=TSQLQuery.Create(nil);
      try
        Q.Database:=Conn;
        Q.Transaction:=Conn.Transaction;
        Q.SQL.Text:='SELECT COUNT(*) FROM complaints '+
          'WHERE chat=-100500 AND message=1001 AND complainant=42';
        Q.Open;
        AssertTrue('duplicate complaint must not be stored twice',
          Q.Fields[0].AsInteger=1);
        Q.Close;
      finally
        Q.Free;
      end;
    finally
      Conn.Free;
    end;
  finally
    ORM.Free;
  end;
end;

procedure TTestORMLive.ModeratorRoundtripKeepsNotifyOk;
var
  ORM: TBotORM;
  aUsers: TInt64List;
  aMembers: TopfChatMembers.TEntities;
  aMember: TChatMember;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    aUsers:=TInt64List.Create;
    try
      aUsers.Add(888);
      ORM.AddChatMembers(-100501, True, aUsers);
    finally
      aUsers.Free;
    end;
    aMembers:=TopfChatMembers.TEntities.Create;
    try
      ORM.GetModeratorsByChat(-100501, aMembers);
      AssertTrue('one moderator expected', aMembers.Count=1);
      for aMember in aMembers do
      begin
        AssertTrue('moderator id must roundtrip', aMember.User=888);
        AssertTrue('moderator flag must roundtrip', aMember.Moderator);
        AssertTrue('notifyok must default to reachable', aMember.NotifyOk);
      end;
    finally
      aMembers.Free;
    end;
  finally
    ORM.Free;
  end;
end;

procedure TTestORMLive.MembershipNewbieDetection;
var
  ORM: TBotORM;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    AssertFalse('unknown user cannot be a newbie', ORM.IsNewbieInChat(-100502, 999));
    { The production flow stores the user before the membership: create him
      with neutral rate and spammer status }
    ORM.User.ID:=999;
    ORM.User.Name:='Newbie';
    ORM.SaveUser(True);
    ORM.SaveMembershipAppearance(-100502, 999);
    AssertTrue('just joined user must be a newbie', ORM.IsNewbieInChat(-100502, 999));
  finally
    ORM.Free;
  end;
end;

procedure TTestORMLive.GetMessageReconnectsAfterKill;
var
  ORM: TBotORM;
  Conn: TSQLConnection;
  aFirst: Boolean;
begin
  if not Enabled then Exit;
  ORM:=NewORM;
  try
    { Warm the connection up and store a known row }
    ORM.GetNSaveMessage('Warm', 55, -100503, 0, 2001, aFirst, _msSpam);
    { Kill the ORM connection server-side, as MySQL wait_timeout does }
    Conn:=MakeConn;
    try
      KillOtherConnections(Conn);
    finally
      Conn.Free;
    end;
    { GetMessage must detect the disconnect, reconnect and retry }
    AssertTrue('killed connection must be transparently recovered',
      ORM.GetMessage(-100503, 2001));
    AssertTrue('row content must survive the reconnect', ORM.Message.IsSpam=_msSpam);
  finally
    ORM.Free;
  end;
end;

initialization
  RegisterTest(TTestORMLive);

end.

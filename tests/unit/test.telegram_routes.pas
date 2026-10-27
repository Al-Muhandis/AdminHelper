unit test.telegram_routes;
{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpjson, fpcunit, testutils, testregistry,
  tgtypes, telegram_cmn;

type
  TTestTelegramRoutes = class(TTestCase)
  private
    function SplitRoute(const aRoute: String): TStringList;
  published
    procedure SpamRouteFormat;
    procedure ReactionRouteFormat;
    procedure RollbackRoutesUseDistinctSymbols;
    procedure ServiceRoutesFormat;
    procedure ProbablySpamRouteFormat;
    procedure MessageUrlForPublicChat;
    procedure MessageUrlForPrivateChat;
    procedure MessageUrlForUnresolvableChat;
  end;

implementation

function TTestTelegramRoutes.SplitRoute(const aRoute: String): TStringList;
begin
  Result:=TStringList.Create;
  Result.StrictDelimiter:=True;
  Result.Delimiter:=' ';
  Result.DelimitedText:=aRoute;
end;

procedure TTestTelegramRoutes.SpamRouteFormat;
var
  aParts: TStringList;
begin
  aParts:=SplitRoute(RouteCmdSpam(-1001149179557, 456119, True));
  try
    CheckEquals(4, aParts.Count, 'spam route must have 4 tokens');
    CheckEquals('spam', aParts[0], 'route prefix');
    CheckEquals('-1001149179557', aParts[1], 'chat id token');
    CheckEquals('456119', aParts[2], 'message id token');
    CheckEquals('-1', aParts[3], 'verdict token (FPC BoolToStr form)');
  finally
    aParts.Free;
  end;
end;

procedure TTestTelegramRoutes.ReactionRouteFormat;
var
  aParts: TStringList;
begin
  aParts:=SplitRoute(RouteCmdReaction(-1001149179557, 8863364797, False));
  try
    CheckEquals(5, aParts.Count, 'reaction route must have 5 tokens');
    CheckEquals('spam', aParts[0], 'route prefix');
    CheckEquals('8863364797', aParts[2], 'user id token');
    CheckEquals('0', aParts[3], 'verdict token (FPC BoolToStr form)');
    CheckEquals('r', aParts[4], 'reaction marker');
  finally
    aParts.Free;
  end;
end;

procedure TTestTelegramRoutes.RollbackRoutesUseDistinctSymbols;
var
  aParts: TStringList;
begin
  aParts:=SplitRoute(RouteCmdSpamLastChecking(-1001, 42, True));
  try
    CheckEquals('rc', aParts[3], 'confirmation marker');
  finally
    aParts.Free;
  end;
  aParts:=SplitRoute(RouteCmdSpamLastChecking(-1001, 42, False));
  try
    CheckEquals('r', aParts[3], 'rollback marker');
  finally
    aParts.Free;
  end;
end;

procedure TTestTelegramRoutes.ServiceRoutesFormat;
begin
  CheckEquals('m UsrPrvcy', RouteMsgUsrPrvcy);
  CheckEquals('m CmplnntIsBt', RouteMsgCmplnntIsBt);
end;

procedure TTestTelegramRoutes.ProbablySpamRouteFormat;
var
  aParts: TStringList;
  aSpam, aHam: Double;
begin
  aParts:=SplitRoute(RouteMsgPrbblySpm(0.5, 0.25, False));
  try
    CheckEquals(4, aParts.Count, 'probability route must have 4 tokens');
    CheckEquals('m', aParts[0], 'route prefix');
    CheckEquals('PrbblySpm', aParts[1], 'probable-spam marker');
    AssertTrue('spam probability must survive the roundtrip',
      TryStrToFloat(aParts[2], aSpam) and (Abs(aSpam-0.5)<1e-9));
    AssertTrue('ham probability must survive the roundtrip',
      TryStrToFloat(aParts[3], aHam) and (Abs(aHam-0.25)<1e-9));
  finally
    aParts.Free;
  end;
  aParts:=SplitRoute(RouteMsgPrbblySpm(1, 0, True));
  try
    CheckEquals(5, aParts.Count, 'emoji marker adds one token');
    CheckEquals('emj', aParts[4], 'emoji marker token');
  finally
    aParts.Free;
  end;
end;

procedure TTestTelegramRoutes.MessageUrlForPublicChat;
var
  Json: TJSONObject;
  Chat: TTelegramChatObj;
begin
  Json:=TJSONObject.Create;
  try
    Json.Add('id', Int64(-1001149179557));
    Json.Add('username', 'Delphi_Lazarus');
    Json.Add('type', 'supergroup');
    Chat:=TTelegramChatObj.Create(Json);
    try
      CheckEquals('https://t.me/Delphi_Lazarus/', BuildMsgUrl(Chat));
      CheckEquals('https://t.me/Delphi_Lazarus/456119', BuildMsgUrl(Chat, 456119));
    finally
      Chat.Free;
    end;
  finally
    Json.Free;
  end;
end;

procedure TTestTelegramRoutes.MessageUrlForPrivateChat;
var
  Json: TJSONObject;
  Chat: TTelegramChatObj;
begin
  Json:=TJSONObject.Create;
  try
    Json.Add('id', Int64(-1001234567890));
    Json.Add('username', '');
    Json.Add('type', 'supergroup');
    Chat:=TTelegramChatObj.Create(Json);
    try
      CheckEquals('https://t.me/c/1234567890/777', BuildMsgUrl(Chat, 777));
      CheckEquals('https://t.me/c/1234567890/', BuildMsgUrl(Chat));
    finally
      Chat.Free;
    end;
  finally
    Json.Free;
  end;
end;

procedure TTestTelegramRoutes.MessageUrlForUnresolvableChat;
var
  Json: TJSONObject;
  Chat: TTelegramChatObj;
begin
  Json:=TJSONObject.Create;
  try
    Json.Add('id', 123);
    Json.Add('username', '');
    Json.Add('type', 'group');
    Chat:=TTelegramChatObj.Create(Json);
    try
      CheckEquals('https://t.me/', BuildMsgUrl(Chat, 1));
    finally
      Chat.Free;
    end;
  finally
    Json.Free;
  end;
end;

initialization
  RegisterTest(TTestTelegramRoutes);

end.

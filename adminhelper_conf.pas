unit adminhelper_conf;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, brk_tg_config
  ;

type

  EWSWConfig = class(Exception);

  { TConf }

  TConf = class
  private
    FAdminHelperBot: TBotConf;
    FAdminHelperDB: TDBConf;
    FDebug: TDebugInfo;
    FPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Debug: TDebugInfo read FDebug write FDebug;
    property AdminHelperBot: TBotConf read FAdminHelperBot write FAdminHelperBot;
    property AdminHelperDB: TDBConf read FAdminHelperDB write FAdminHelperDB;
    property Port: Integer read FPort write FPort;

  end;

var
  Conf: TConf;

implementation

uses
  RUtils, dateutils, jsonparser, jsonscanner, tgsendertypes
  ;

procedure SaveConfig(aConf: TConf);
begin
  SaveToJSON(aConf, ChangeFileExt(ParamStr(0), '.json'));
end;

function LoadJSONObjectFromFile(const AFileName: String): TJSONObject;
var
  AJSON: TStringList;
begin
  if not FileExists(AFileName) then
    Exit;
  AJSON:=TStringList.Create;
  try
    AJSON.LoadFromFile(AFileName);
    Result:=StringToJSONObject(AJSON.Text);
  finally
    AJSON.Free;
  end;
end;

{ TConf }

constructor TConf.Create;
begin
  FDebug:=TDebugInfo.Create;
  FAdminHelperBot:=TBotConf.Create;
  FAdminHelperDB:=TDBConf.Create;
end;

destructor TConf.Destroy;
begin
  FAdminHelperDB.Free;
  FAdminHelperBot.Free;
  FDebug.Free;
  inherited Destroy;
end;

initialization
  Conf:=TConf.Create;
  LoadFromJSON(Conf, 'adminhelper.json');
  SaveToJSON(Conf, 'adminhelper.bak.json');

finalization
  FreeAndNil(Conf);

end.


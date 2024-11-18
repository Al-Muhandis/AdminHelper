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
    FGuardRate: Integer;
    FPatrolRate: Integer;
    FPort: Integer;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Debug: TDebugInfo read FDebug write FDebug;
    property AdminHelperBot: TBotConf read FAdminHelperBot write FAdminHelperBot;
    property AdminHelperDB: TDBConf read FAdminHelperDB write FAdminHelperDB;
    property Port: Integer read FPort write FPort;
    property PatrolRate: Integer read FPatrolRate write FPatrolRate;
    property GuardRate: Integer read FGuardRate write FGuardRate;

  end;

var
  Conf: TConf;

implementation

uses
  dateutils, jsonparser, jsonscanner, tgsendertypes
  ;

{ TConf }

constructor TConf.Create;
begin
  FDebug:=TDebugInfo.Create;
  FAdminHelperBot:=TBotConf.Create;
  FAdminHelperDB:=TDBConf.Create;
  FPatrolRate:=11;
  FGuardRate:=FPatrolRate*3;
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


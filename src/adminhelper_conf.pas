unit adminhelper_conf;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, brk_tg_config
  ;

type

  EWSWConfig = class(Exception);

  { Raised during the startup when mandatory settings are missing }

  EConfError = class(EWSWConfig);

  { TSpamFilterConfig }

  TSpamFilterConfig = class
  private
    FDefinitelyHam: Double;
    FDefinitelySpam: Double;
    FEmojiLimit: Integer;
    FEnabled: Boolean;
    FMediaRatio: Double;
  public
    constructor Create;
  published
    property Enabled: Boolean read FEnabled write FEnabled;
    property DefinitelySpam: Double read FDefinitelySpam write FDefinitelySpam;
    property DefinitelyHam: Double read FDefinitelyHam write FDefinitelyHam;
    property EmojiLimit: Integer read FEmojiLimit write FEmojiLimit;
    property MediaRatio: Double read FMediaRatio write FMediaRatio;
  end;

  { TConf }

  TConf = class
  private
    FAdminHelperBot: TBotConf;
    FAdminHelperDB: TDBConf;
    FBindAddress: String;
    FDebug: TDebugInfo;
    FGuardRate: Integer;
    FNewbieDays: Integer;
    FPatrolRate: Integer;
    FPort: Integer;
    FServiceAdmin: Int64;
    FSpamFilter: TSpamFilterConfig;
  public
    constructor Create;
    destructor Destroy; override;
  published
    property Debug: TDebugInfo read FDebug write FDebug;
    property AdminHelperBot: TBotConf read FAdminHelperBot write FAdminHelperBot;
    property AdminHelperDB: TDBConf read FAdminHelperDB write FAdminHelperDB;
    property SpamFilter: TSpamFilterConfig read FSpamFilter write FSpamFilter;
    property Port: Integer read FPort write FPort;
    { Local address to bind to; empty = all interfaces }
    property BindAddress: String read FBindAddress write FBindAddress;
    property PatrolRate: Integer read FPatrolRate write FPatrolRate;
    property GuardRate: Integer read FGuardRate write FGuardRate;
    property NewbieDays: Integer read FNewbieDays write FNewbieDays;
    property ServiceAdmin: Int64 read FServiceAdmin write FServiceAdmin;

  end;

var
  Conf: TConf;

implementation

uses
  global;

{ TSpamFilterConfig }

constructor TSpamFilterConfig.Create;
begin
  FEnabled:=True;
  FDefinitelySpam:=30;
  FDefinitelyHam:=-15;
  FEmojiLimit:=15;
  FMediaRatio:=0.5;
end;

{ TConf }

constructor TConf.Create;
begin
  FDebug:=TDebugInfo.Create;
  FAdminHelperBot:=TBotConf.Create;
  FAdminHelperDB:=TDBConf.Create;
  FSpamFilter:=TSpamFilterConfig.Create;
  FPatrolRate:=11;
  FGuardRate:=FPatrolRate*3;
  FNewbieDays:=7;
end;

destructor TConf.Destroy;
begin
  FSpamFilter.Free;
  FAdminHelperDB.Free;
  FAdminHelperBot.Free;
  FDebug.Free;
  inherited Destroy;
end;

initialization
  Conf:=TConf.Create;
  LoadFromJSON(Conf, _ConfFileName);
  { The startup config backup is kept in the data directory:
    the daemon usually runs unprivileged and cannot write next to the config }
  SaveToJSON(Conf, _DataDir+ExtractFileName(_ConfFileName)+'.bak');
  {$IFDEF UNIX}
  { A missing or truncated file silently yields defaults; without these
    checks the daemon starts with an empty token and answers 404 forever }
  if Conf.AdminHelperBot.Telegram.Token.IsEmpty then
    raise EConfError.CreateFmt('Telegram bot token is empty: fix %s', [_ConfFileName]);
  if (Conf.Port<1) or (Conf.Port>65535) then
    raise EConfError.CreateFmt('Port %d is not usable: fix %s', [Conf.Port, _ConfFileName]);
  {$ENDIF}

finalization
  FreeAndNil(Conf);

end.


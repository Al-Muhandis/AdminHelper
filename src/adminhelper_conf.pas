unit adminhelper_conf;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, brk_tg_config
  ;

type

  EWSWConfig = class(Exception);

  { TSpamFilterConfig }

  TSpamFilterConfig = class
  private
    FDefinitelyHam: Double;
    FDefinitelySpam: Double;
    FEmojiLimit: Integer;
    FEnabled: Boolean;
  public
    constructor Create;
  published
    property Enabled: Boolean read FEnabled write FEnabled;
    property DefinitelySpam: Double read FDefinitelySpam write FDefinitelySpam;
    property DefinitelyHam: Double read FDefinitelyHam write FDefinitelyHam;
    property EmojiLimit: Integer read FEmojiLimit write FEmojiLimit;
  end;

  { TConf }

  TConf = class
  private
    FAdminHelperBot: TBotConf;
    FAdminHelperDB: TDBConf;
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
    property PatrolRate: Integer read FPatrolRate write FPatrolRate;
    property GuardRate: Integer read FGuardRate write FGuardRate;
    property NewbieDays: Integer read FNewbieDays write FNewbieDays;
    property ServiceAdmin: Int64 read FServiceAdmin write FServiceAdmin;

  end;

var
  Conf: TConf;
  ConfDir: String;

implementation

{ TSpamFilterConfig }

constructor TSpamFilterConfig.Create;
begin
  FEnabled:=True;
  FDefinitelySpam:=30;
  FDefinitelyHam:=-15;
  FEmojiLimit:=15;
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
  LoadFromJSON(Conf, 'adminhelper.json');
  SaveToJSON(Conf, 'adminhelper.bak.json');
  ConfDir:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));

finalization
  FreeAndNil(Conf);

end.


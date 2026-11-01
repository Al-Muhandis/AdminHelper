unit global;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, DateUtils
  ;

var
  _appAlias: String = 'tgadmin';
  _AppName, _AppDir, _ConfFileName, _LogDir, _ConfDir, _DataDir: String;

const
  { The daemon serves corrupted memory only until these are exceeded }
  _MemoryFaultLimit = 2;
  _MemoryFaultWindowSec = 600;

{ Registers a fatal fault (access violation, invalid pointer) together with
  the hex address of the raise: it resolves to file:line offline via
  addr2line against the deployed, unstripped binary. When more than
  _MemoryFaultLimit occur within the window, the process is killed so systemd
  (Restart=on-failure) starts a clean instance: a corrupted heap keeps
  crashing every request until restarted }
procedure MemoryFaultRegistered(const aContext, aTrace: String);

implementation

{$IFDEF UNIX}
uses
  baseunix, lnfodwrf
  ;
{$ENDIF}

var
  _FaultTimes: array of TDateTime;
  _FaultLock: TRTLCriticalSection;

procedure MemoryFaultRegistered(const aContext, aTrace: String);
var
  aNow, aOldest: TDateTime;
  aDump: Text;
  aDumpName: String;
  I, aKept: Integer;
begin
  aNow:=Now;
  aOldest:=IncSecond(aNow, -_MemoryFaultWindowSec);
  EnterCriticalSection(_FaultLock);
  try
    aKept:=0;
    for I:=0 to High(_FaultTimes) do
      if _FaultTimes[I]>=aOldest then
      begin
        _FaultTimes[aKept]:=_FaultTimes[I];
        Inc(aKept);
      end;
    SetLength(_FaultTimes, aKept+1);
    _FaultTimes[aKept]:=aNow;
    { The call stack of the first fault carries the evidence: lnfodwrf
      resolves the frames to file:line while dumping, so the corrupted call
      site can be found without reproducing anything. Dumped inside the
      critical section: concurrent faults must not interleave the dumps }
    aDumpName:=_DataDir+'fault_backtrace.log';
    AssignFile(aDump, aDumpName);
    try
      if FileExists(aDumpName) then
        Append(aDump)
      else
        Rewrite(aDump);
      WriteLn(aDump, '=== ', FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', aNow), ' ', aContext, ' at ', aTrace, ' ===');
      DumpExceptionBackTrace(aDump);
      Flush(aDump);
    finally
      CloseFile(aDump);
    end;
    WriteLn(Format('%s [memory fault] %s at %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', aNow), aContext, aTrace]));
    if aKept+1>=_MemoryFaultLimit then
    begin
      WriteLn(Format('%s [%s] %d memory faults in %d seconds: halting for a systemd restart',
        [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', aNow), aContext, aKept+1, _MemoryFaultWindowSec]));
      {$IFDEF UNIX}
      { Halt from a secondary thread does not reliably terminate the process:
        the daemon kept serving after Halt(75). SIGABRT's default action kills
        the process from any thread and counts as a failure for the service
        unit (Restart=on-failure) }
      fpKill(SIGABRT, fpGetPid);
      {$ENDIF}
      { Nonzero exit code: the service unit restarts on failure }
      Halt(75);
    end;
  finally
    LeaveCriticalSection(_FaultLock);
  end;
end;

initialization
  _AppName:=ExtractFileName(ChangeFileExt(ParamStr(0), EmptyStr));
  _AppDir:=IncludeTrailingPathDelimiter(ExtractFileDir(ParamStr(0)));{$IFDEF UNIX}
  _ConfFileName:=Format('/etc/%s/%s.json', [_appAlias, _appAlias]);
  _LogDir:=Format('/var/log/%s/', [_appAlias]);
  ForceDirectories(_LogDir);
  _DataDir:=Format('/var/lib/%s/', [_appAlias]);
  ForceDirectories(_DataDir);{$ENDIF}{$IFDEF MSWINDOWS}
  _ConfFileName:=_AppDir+'adminhelper.json';
  _LogDir:=_AppDir;
  _DataDir:=_AppDir;{$ENDIF}
  if not FileExists(_ConfFileName) then
    _ConfFileName:=ChangeFileExt(ParamStr(0), '.json');
  _ConfDir:=IncludeTrailingPathDelimiter(ExtractFileDir(_ConfFileName));
  InitCriticalSection(_FaultLock);

finalization
  DoneCriticalSection(_FaultLock);

end.


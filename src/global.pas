unit global;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils
  ;

var
  _appAlias: String = 'tgadmin';
  _AppName, _AppDir, _ConfFileName, _LogDir, _ConfDir, _DataDir: String;

implementation

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

end.


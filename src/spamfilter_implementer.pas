unit spamfilter_implementer;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, spamfilter, adminhelper_conf
  ;

var
  _SpamFilter: TSpamFilter;

implementation

initialization
  _SpamFilter:=TSpamFilter.Create;
  _SpamFilter.StorageDir:=ConfDir;
  _SpamFilter.Load;

finalization
  _SpamFilter.Save;
  _SpamFilter.Free;

end.


unit spamfilter_implementer;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, spamfilter, adminhelper_conf
  ;

type

  { TServerSpamFilter }

  TServerSpamFilter = class(TSpamFilter)
  public
    procedure ServerStop({%H-}Sender: TObject);
  end;

var
  _SpamFilter: TServerSpamFilter;

implementation

{ TServerSpamFilter }

procedure TServerSpamFilter.ServerStop(Sender: TObject);
begin
  Save;
end;

initialization
  _SpamFilter:=TServerSpamFilter.Create;
  _SpamFilter.StorageDir:=ConfDir;
  if not _SpamFilter.Load then
  begin
    _SpamFilter.Train('crypto', True);
    _SpamFilter.Train('lazarus', False);
  end;

finalization
  _SpamFilter.Free;

end.


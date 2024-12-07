unit brokers;

{$mode objfpc}{$H+}

interface

uses
  BrookTardigradeBroker, BrookUtils, BrookFCLEventLogBroker, sysutils, mysql80conn
  ;

implementation

uses
  BrookHttpConsts, adminhelper_conf
  ;

initialization
  BrookSettings.Port := Conf.Port;
  BrookSettings.Charset := BROOK_HTTP_CHARSET_UTF_8;
  BrookSettings.LogActive:=True;

end.

program testgui;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, GuiTestRunner, testfilter
  ;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TGuiTestRunner, TestRunner);
  Application.Run;
end.


program testgui;

{$mode objfpc}{$H+}

uses
  Interfaces, Forms, GuiTestRunner, testemojies
  ;

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TGuiTestRunner, TestRunner);
  Application.Run;
end.


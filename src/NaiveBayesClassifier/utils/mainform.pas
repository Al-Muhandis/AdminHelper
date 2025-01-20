unit mainform;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Grids, EditBtn, StdCtrls, ComCtrls, spamfilter
  ;

type

  { TForm1 }

  TVisualSpamFilter = class(TSpamFilter)
  public
    property Words;
    property SpamCount;
    property HamCount;
    property TotalSpamWords;
    property TotalHamWords;
  end;

  TForm1 = class(TForm)
    BtnClassify: TButton;
    BtnSpam: TButton;
    BtnHam: TButton;
    DrctryEdtWords: TDirectoryEdit;
    GrpBxMessage: TGroupBox;
    GrpBxBase: TGroupBox;
    Memo1: TMemo;
    SttsBrMessage: TStatusBar;
    StringGrid1: TStringGrid;
    procedure BtnClassifyClick(Sender: TObject);
    procedure BtnHamClick(Sender: TObject);
    procedure BtnSpamClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure DrctryEdtWordsAcceptDirectory(Sender: TObject; var Value: String);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure Memo1Change(Sender: TObject);
  private
    FSpamFilter: TVisualSpamFilter;
    procedure OpenBase(const aDir: String);
  public

  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.DrctryEdtWordsAcceptDirectory(Sender: TObject; var Value: String);
begin
  OpenBase(Value);
end;

procedure TForm1.BtnClassifyClick(Sender: TObject);
var
  aSpamProbability, aHamProbability: Double;
begin
  FSpamFilter.Classify(Memo1.Lines.Text, aHamProbability, aSpamProbability);
  SttsBrMessage.SimpleText:=Format('Spam prob.: %n, Ham prob. %n. Factor: %n', [aSpamProbability, aHamProbability,
    aSpamProbability-aHamProbability]);
end;

procedure TForm1.BtnHamClick(Sender: TObject);
begin 
  FSpamFilter.Train(Memo1.Lines.Text, False);
  FSpamFilter.Save;
  OpenBase(DrctryEdtWords.Directory);
end;

procedure TForm1.BtnSpamClick(Sender: TObject);
begin
  FSpamFilter.Train(Memo1.Lines.Text, True);
  FSpamFilter.Save;
  OpenBase(DrctryEdtWords.Directory);
end;

procedure TForm1.BtnSaveClick(Sender: TObject);
begin
  FSpamFilter.StorageDir:=DrctryEdtWords.Directory;
  FSpamFilter.Save;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  FSpamFilter:=TVisualSpamFilter.Create;
  OpenBase(EmptyStr);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  FSpamFilter.Free;
end;

procedure TForm1.Memo1Change(Sender: TObject);
begin
  SttsBrMessage.Panels.Clear;
end;

procedure TForm1.OpenBase(const aDir: String);
var
  i: Integer;
begin
  StringGrid1.Clear;
  FSpamFilter.StorageDir:=IncludeTrailingPathDelimiter(aDir);
  FSpamFilter.Load;
  StringGrid1.RowCount:=FSpamFilter.Words.Count+1;
  for i:=0 to FSpamFilter.Words.Count-1 do
  begin
    StringGrid1.Cells[0, i+1]:=FSpamFilter.Words.Keys[i];
    StringGrid1.Cells[1, i+1]:=FSpamFilter.Words.Data[i].Ham.ToString;
    StringGrid1.Cells[2, i+1]:=FSpamFilter.Words.Data[i].Spam.ToString;
  end;
end;

end.


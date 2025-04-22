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
    BtnSave: TButton;
    DrctryEdtWords: TDirectoryEdit;
    GrpBxMessage: TGroupBox;
    GrpBxBase: TGroupBox;
    MmMessage: TMemo;
    SttsBrMessage: TStatusBar;
    StrngGrdWordBase: TStringGrid;
    procedure BtnClassifyClick(Sender: TObject);
    procedure BtnHamClick(Sender: TObject);
    procedure BtnSpamClick(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure DrctryEdtWordsAcceptDirectory(Sender: TObject; var Value: String);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure MmMessageChange(Sender: TObject);
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
  FSpamFilter.Classify(MmMessage.Lines.Text, aHamProbability, aSpamProbability);
  SttsBrMessage.SimpleText:=Format('Spam prob.: %n, Ham prob. %n. Factor: %n', [aSpamProbability, aHamProbability,
    aSpamProbability-aHamProbability]);
end;

procedure TForm1.BtnHamClick(Sender: TObject);
begin 
  FSpamFilter.Train(MmMessage.Lines.Text, False);
  FSpamFilter.Save;
  OpenBase(DrctryEdtWords.Directory);
end;

procedure TForm1.BtnSpamClick(Sender: TObject);
begin
  FSpamFilter.Train(MmMessage.Lines.Text, True);
  FSpamFilter.Save;
  OpenBase(DrctryEdtWords.Directory);
end;

procedure TForm1.BtnSaveClick(Sender: TObject);
begin
  FSpamFilter.StorageDir:=IncludeTrailingPathDelimiter(DrctryEdtWords.Directory);
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

procedure TForm1.MmMessageChange(Sender: TObject);
begin
  SttsBrMessage.Panels.Clear;
end;

procedure TForm1.OpenBase(const aDir: String);
var
  i: Integer;
begin
  StrngGrdWordBase.Clear;
  FSpamFilter.StorageDir:=IncludeTrailingPathDelimiter(aDir);
  FSpamFilter.LoadJSON(True);
  StrngGrdWordBase.RowCount:=FSpamFilter.Words.Count+1;
  for i:=0 to FSpamFilter.Words.Count-1 do
  begin
    StrngGrdWordBase.Cells[0, i+1]:=FSpamFilter.Words.Keys[i];
    StrngGrdWordBase.Cells[1, i+1]:=FSpamFilter.Words.Data[i].Ham.ToString;
    StrngGrdWordBase.Cells[2, i+1]:=FSpamFilter.Words.Data[i].Spam.ToString;
  end;
end;

end.


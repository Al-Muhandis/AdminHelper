unit testfilter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, spamfilter
  ;

type

  { TTestFilter }

  TTestFilter= class(TTestCase)
  private
    FSpamFilter: TSpamFilter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TrainNClassify;
    procedure Save;   
    procedure Load;
  end;

implementation

procedure TTestFilter.TrainNClassify;
begin
  FSpamFilter.Train('Congratulations! You have won a free loan!', True);
  FSpamFilter.Train('How do I learn to program in Lazarus?', False);

  if not FSpamFilter.Classify('Win a new phone now!') then
    Fail('Wrong classify. Must be a spam');

  if FSpamFilter.Classify('I wrote Hello world on Lazarus') then
    Fail('Wrong classify. Must be not a spam');
end;

procedure TTestFilter.Save;
begin
  TrainNClassify;
  FSpamFilter.Save;
end;

procedure TTestFilter.Load;
begin
  //Save;
  FSpamFilter.Load;
  if not FSpamFilter.Classify('You have a free phone') then
    Fail('Wrong classify. Must be a spam');

  if FSpamFilter.Classify('I learn') then
    Fail('Wrong classify. Must be not a spam');
end;

procedure TTestFilter.SetUp;
begin
  FSpamFilter:=TSpamFilter.Create;
end;

procedure TTestFilter.TearDown;
begin
  FSpamFilter.Free;
end;

initialization

  RegisterTest(TTestFilter);
end.


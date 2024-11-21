unit spamfilter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, IniFiles
  ;

type

  TWordPairs = specialize TFPGMap<String, Integer>;

  { TSpamFilter }

  TSpamFilter = class
  private
    FSpamWords: TWordPairs;
    FHamWords: TWordPairs;
    FSpamCount: Integer;
    FHamCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Train(Message: string; IsSpam: Boolean);
    function Classify(const aMessage: string; out aHamProbability, aSpamProbability: Double): Boolean;  
    function Classify(const aMessage: string): Boolean;
    procedure Load;
    procedure Save;
  end;

implementation

const
  _HamFile='hamwords.lst';
  _SpamFile='spamwords.lst'; 
  _FilterIni='messages.ini';

constructor TSpamFilter.Create;
begin
  FSpamWords := TWordPairs.Create;
  FSpamWords.Sorted:=True;
  FHamWords := TWordPairs.Create; 
  FHamWords.Sorted:=True;
  FSpamCount := 0;
  FHamCount := 0;
end;

destructor TSpamFilter.Destroy;
begin
  FSpamWords.Free;
  FHamWords.Free;
  inherited Destroy;
end;

procedure TSpamFilter.Train(Message: string; IsSpam: Boolean);
var
  aWords: TStringList;
  aWord, w: string;
  i: Integer;
begin
  aWords := TStringList.Create;
  try
    ExtractStrings([' ', '.', ',', '!', '?'], [], PChar(Message), aWords);
    if IsSpam then
      Inc(FSpamCount)
    else
      Inc(FHamCount);

    for w in aWords do
    begin
      aWord := LowerCase(w);
      if IsSpam then
      begin
        if FSpamWords.Find(aWord, i) then
          FSpamWords.Data[i] := FSpamWords.Data[i] + 1
        else
          FSpamWords.Add(aWord, 1);
      end
      else
      begin
        if FHamWords.Find(aWord, i) then
          FHamWords.Data[i] := FHamWords.Data[i] + 1
        else
          FHamWords.Add(aWord, 1);
      end;
    end;
  finally
    aWords.Free;
  end;
end;

function TSpamFilter.Classify(const aMessage: string; out aHamProbability, aSpamProbability: Double): Boolean;
var
  aWords: TStringList;
  aWord, w: string;
  i: Integer;
begin
  aWords := TStringList.Create;
  try
    ExtractStrings([' ', '.', ',', '!', '?'], [], PChar(aMessage), aWords);

    aSpamProbability := FSpamCount / (FSpamCount + FHamCount);
    aHamProbability := FHamCount / (FSpamCount + FHamCount);

    for w in aWords do
    begin
      aWord := LowerCase(w);
      if FSpamWords.Find(aWord, i) then
        aSpamProbability := aSpamProbability * (FSpamWords.Data[i] / FSpamCount)
      else
        aSpamProbability := aSpamProbability * (1 / (FSpamCount + 1));


      if FHamWords.Find(aWord, i) then
        aHamProbability := aHamProbability * (FHamWords.Data[i] / FHamCount)
      else
        aHamProbability := aHamProbability * (1 / (FHamCount + 1));
    end;

    Result := aSpamProbability > aHamProbability;

  finally
    aWords.Free;
  end;
end;

function TSpamFilter.Classify(const aMessage: string): Boolean;
var
  aHamProbability, aSpamProbability: Double;
begin
  Result:=Classify(aMessage, aHamProbability, aSpamProbability);
end;

procedure TSpamFilter.Load;
var
  aIni: TMemIniFile;
  aWordPairs: TStringList;
  w, s: String;
  i: Integer;
begin
  if not (FileExists(_HamFile) and FileExists(_SpamFile)) then
    Exit;
  aIni:=TMemIniFile.Create(_FilterIni);
  aWordPairs:=TStringList.Create;
  try
    aWordPairs.LoadFromFile(_HamFile);
    for i:=0 to aWordPairs.Count-1 do
    begin
      aWordPairs.GetNameValue(i, w, s);
      FHamWords.Add(w, s.ToInteger);
    end;
    FHamCount:=aIni.ReadInteger('count', 'ham', 0);
    aWordPairs.Clear;
    aWordPairs.LoadFromFile(_SpamFile);
    for i:=0 to aWordPairs.Count-1 do
    begin
      aWordPairs.GetNameValue(i, w, s);
      FSpamWords.Add(w, s.ToInteger);
    end;                                           
    FSpamCount:=aIni.ReadInteger('count', 'spam', 0);
  finally
    aWordPairs.Free;
    aIni.Free;
  end;
end;

procedure TSpamFilter.Save;
var
  aIni: TMemIniFile;
  i: SizeUInt;    
  aWords: TStringList;
begin
  aIni:=TMemIniFile.Create(_FilterIni);
  aWords:=TStringList.Create;
  try
    for i:=0 to FHamWords.Count-1 do
      aWords.AddPair(FHamWords.Keys[i], FHamWords.Data[i].ToString);
    aWords.SaveToFile(_HamFile);
    aIni.WriteInteger('Count', 'ham', FHamCount);
    aWords.Clear;
    for i:=0 to FSpamWords.Count-1 do
      aWords.AddPair(FSpamWords.Keys[i], FSpamWords.Data[i].ToString);
    aWords.SaveToFile(_SpamFile);
    aIni.WriteInteger('Count', 'spam', FSpamCount);
    aIni.UpdateFile;
  finally
    aWords.Free;
    aIni.Free;
  end;
end;

end.


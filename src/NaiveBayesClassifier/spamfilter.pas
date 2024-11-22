unit spamfilter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, IniFiles
  ;

type

  { TCountRec }

  TCountRec = record
    Spam: Integer;
    Ham:  Integer;
  end;

  TWordPairs = specialize TFPGMap<String, TCountRec>;

  { TSpamFilter }

  TSpamFilter = class
  private
    FWords: TWordPairs;
    FSpamCount: Integer;
    FHamCount: Integer;
    FTotalSpamWords: Integer;
    FTotalHamWords: Integer;
    FStorageDir: String;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Train(Message: string; IsSpam: Boolean);
    function Classify(const aMessage: string; out aHamProbability, aSpamProbability: Double): Boolean;  
    function Classify(const aMessage: string): Boolean;
    function Load: Boolean;
    procedure Save;
    property StorageDir: String read FStorageDir write FStorageDir;
  end;

implementation

var
  _50Probability: Double;

const
  _HamFile='hamwords.lst';
  _SpamFile='spamwords.lst'; 
  _FilterIni='messages.ini';
  _Separators=[' ', '.', ',', '!', '?', '"'];

constructor TSpamFilter.Create;
begin
  FWords := TWordPairs.Create;
  FWords.Sorted:=True;
  FSpamCount := 0;
  FHamCount := 0;
end;

destructor TSpamFilter.Destroy;
begin
  FWords.Free;
  inherited Destroy;
end;

procedure TSpamFilter.Train(Message: string; IsSpam: Boolean);
var
  aWords: TStringList;
  aWord, w: string;
  i: Integer;
  aWordRec: TCountRec;
begin
  aWords := TStringList.Create;
  try
    ExtractStrings(_Separators, [], PChar(Message), aWords);
    if IsSpam then
      Inc(FSpamCount)
    else
      Inc(FHamCount);
    for w in aWords do
    begin
      aWord := AnsiLowerCase(w);

      if FWords.Find(aWord, i) then
      begin
        aWordRec:=FWords.Data[i];
        if IsSpam then
          aWordRec.Spam := aWordRec.Spam + 1
        else
          aWordRec.Ham  := aWordRec.Ham + 1;
        FWords.Data[i]:=aWordRec;
      end
      else begin
        if IsSpam then
        begin
          aWordRec.Spam := 1;
          aWordRec.Ham  := 0;
        end
        else begin            
          aWordRec.Spam := 0;
          aWordRec.Ham  := 1;
        end;
        FWords.Add(aWord, aWordRec);
      end;
      if IsSpam then
        Inc(FTotalSpamWords)
      else
        Inc(FTotalHamWords)
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
  if (FSpamCount=0) or (FHamCount=0) then
  begin
    aHamProbability:=_50Probability;
    aSpamProbability:=_50Probability;
    Exit(False);
  end;
  aWords := TStringList.Create;
  try
    ExtractStrings(_Separators, [], PChar(aMessage), aWords);

    aSpamProbability := Ln(FSpamCount / (FSpamCount + FHamCount));
    aHamProbability := Ln(FHamCount / (FSpamCount + FHamCount));

    for w in aWords do
    begin
      aWord := AnsiLowerCase(w);
      if FWords.Find(aWord, i) then
      begin
        aSpamProbability += Ln((FWords.Data[i].Spam+1) / (FWords.Count+FTotalSpamWords));
        aHamProbability  += Ln((FWords.Data[i].Ham+1)  / (FWords.Count+FTotalHamWords));
      end
      else begin
        aSpamProbability += Ln(1 / (FWords.Count+FTotalSpamWords));
        aHamProbability  += Ln(1 / (FWords.Count+FTotalHamWords));
      end;
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

function TSpamFilter.Load: Boolean;
var
  aIni: TMemIniFile;
  aWordPairs: TStringList;
  w, s: String;
  i, j: Integer;
  aWordRec: TCountRec;
begin
  if not (FileExists(FStorageDir+_HamFile) and FileExists(FStorageDir+_SpamFile)) then
    Exit(False);
  aIni:=TMemIniFile.Create(FStorageDir+_FilterIni);
  aWordPairs:=TStringList.Create;
  try
    aWordPairs.LoadFromFile(FStorageDir+_HamFile);
    for i:=0 to aWordPairs.Count-1 do
    begin
      aWordPairs.GetNameValue(i, w, s);
      aWordRec.Ham:=s.ToInteger;
      aWordRec.Spam:=0;
      FWords.Add(w, aWordRec);
      FTotalHamWords+=aWordRec.Ham;
    end;
    aWordPairs.LoadFromFile(FStorageDir+_SpamFile);
    for i:=0 to aWordPairs.Count-1 do
    begin
      aWordPairs.GetNameValue(i, w, s);
      if FWords.Find(w, j) then
      begin
        aWordRec:=FWords.Data[j];
        aWordRec.Spam:=s.ToInteger;
        FWords.Data[j]:=aWordRec;
      end
      else begin
        aWordRec.Spam:=s.ToInteger;
        aWordRec.Ham:=0;
        FWords.Add(w, aWordRec);
      end;
      FTotalSpamWords+=aWordRec.Spam;
    end;

    FHamCount:=aIni.ReadInteger('Count', 'ham', FHamCount);
    FSpamCount:=aIni.ReadInteger('Count', 'spam', FSpamCount);
  finally
    aWordPairs.Free;
    aIni.Free;
  end;
  Result:=True;
end;

procedure TSpamFilter.Save;
var
  aIni: TMemIniFile;
  i: SizeUInt;    
  aSpamWords, aHamWords: TStringList;
begin
  aIni:=TMemIniFile.Create(FStorageDir+_FilterIni);
  aSpamWords:=TStringList.Create;                  
  aHamWords:=TStringList.Create;
  try
    for i:=0 to FWords.Count-1 do
    begin
      aHamWords.AddPair( FWords.Keys[i], FWords.Data[i].Ham.ToString);
      aSpamWords.AddPair(FWords.Keys[i], FWords.Data[i].Spam.ToString);
    end;
    aHamWords.SaveToFile(FStorageDir+_HamFile);
    aSpamWords.SaveToFile(FStorageDir+_SpamFile);
    aIni.WriteInteger('Count', 'HamDocs', FHamCount);
    aIni.WriteInteger('Count', 'SpamDocs', FSpamCount);
    aIni.UpdateFile;
  finally
    aSpamWords.Free;
    aHamWords.Free;
    aIni.Free;
  end;
end;

initialization
  _50Probability:=Ln(0.5); // Logarithm of 50 percent probability

end.


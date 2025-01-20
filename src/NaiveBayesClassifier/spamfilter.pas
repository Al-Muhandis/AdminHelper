unit spamfilter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl
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
    FInitialHamMessage: String;
    FInitialSpamMessage: String;
    FWords: TWordPairs;
    FSpamCount: Integer;
    FHamCount: Integer;
    FTotalSpamWords: Integer;
    FTotalHamWords: Integer;
    FStorageDir: String;
  protected
    property Words: TWordPairs read FWords;
    property SpamCount: Integer read FSpamCount;
    property HamCount: Integer read FHamCount;
    property TotalSpamWords: Integer read FTotalSpamWords;
    property TotalHamWords: Integer read FTotalHamWords;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Train(aMessage: string; IsSpam: Boolean);
    function Classify(const aMessage: string; out aHamProbability, aSpamProbability: Double): Boolean;  
    function Classify(const aMessage: string): Boolean;
    function Load: Boolean;
    function LoadJSON(aIsRebase: Boolean = False): Boolean;
    procedure Rebase;
    procedure Save;
    procedure SaveJSON;
    property StorageDir: String read FStorageDir write FStorageDir;
    property InitialSpamMessage: String read FInitialSpamMessage write FInitialSpamMessage;
    property InitialHamMessage: String read FInitialHamMessage write FInitialHamMessage;
  end;

implementation

uses
  fpjson, LConvEncoding
  ;

var
  _50Probability: Double;

const
  _Separators=[' ', '.', ',', '!', '?', ';', ':', '(', ')', '-'];
  _dSpmDcs='SpamDocs';
  _dHmDcs='HamDocs';
  _dWrds='words';
  _dWrd='word';
  _dSpm='spam';
  _dHm='ham';

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

procedure TSpamFilter.Train(aMessage: string; IsSpam: Boolean);
var
  aWords: TStringList;
  aWord, w: string;
  i: Integer;
  aWordRec: TCountRec;
begin
  aWords := TStringList.Create;
  try
    aMessage:=aMessage.Replace('"', ' ');
    ExtractStrings(_Separators, [], PChar(aMessage), aWords);
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
begin
  Result:=LoadJSON;
end;

function TSpamFilter.LoadJSON(aIsRebase: Boolean): Boolean;
var
  aFile: TStringList;
  aJSON: TJSONObject;
  w: TJSONEnum;
  aCountRec: TCountRec;
  aWord: String;

  procedure ExtractSubwords(const aSubWords: String);
  var
    aWords: TStrings;
    i: Integer;
    s: String;
  begin
    aWords:=TStringList.Create;
    try
    ExtractStrings(_Separators, [], PChar(aSubWords), aWords);
    for s in aWords do
      if FWords.Find(s, i) then
      begin
        aCountRec.Spam+=FWords.Data[i].Spam;
        aCountRec.Ham+=FWords.Data[i].Ham;
      end
      else
        FWords.Add(s, aCountRec);
    finally
      aWords.Free;
    end;
  end;

begin
  FWords.Clear;
  if not FileExists(FStorageDir+'words.json') then
  begin
    Train(FInitialSpamMessage, True);
    Train(FInitialHamMessage, False);
    Exit(False);
  end;
  aFile:=TStringList.Create;
  try
    aFile.LoadFromFile(FStorageDir+'words.json');
    aJSON:=GetJSON(aFile.Text) as TJSONObject;
    try
      FSpamCount:=aJSON.Integers[_dSpmDcs];
      FHamCount:=aJSON.Integers[_dHmDcs];
      for w in aJSON.Arrays[_dWrds] do
        with w.Value as TJSONObject do
        begin
          aCountRec.Spam:=Integers[_dSpm];
          aCountRec.Ham:=Integers[_dHm];
          aWord:=UTF8Encode(UTF8Decode(Strings[_dWrd]));
          if aIsRebase then
            ExtractSubwords(aWord)
          else
            FWords.Add(aWord, aCountRec);
        end;
    finally
      aJSON.Free;
    end;
  finally
    aFile.Free;
  end;
end;

procedure TSpamFilter.Rebase;
begin
  LoadJSON(True);
  Save;
end;

procedure TSpamFilter.Save;
begin
  SaveJSON;
end;

procedure TSpamFilter.SaveJSON;
var
  aJSON, aWord: TJSONObject;
  aFile: TStringList;
  i: Integer;
  aJSONWords: TJSONArray;
begin
  aJSON:=TJSONObject.Create;
  try
    aJSON.Integers[_dSpmDcs]:=FSpamCount;
    aJSON.Integers[_dHmDcs]:=FHamCount;
    aJSON.Arrays[_dWrds]:=TJSONArray.Create;
    aJSONWords:=aJSON.Arrays[_dWrds];
    for i:=0 to FWords.Count-1 do
    begin
      aWord:=TJSONObject.Create;
      aWord.Strings[_dWrd]:=FWords.Keys[i];
      aWord.Integers[_dSpm]:=FWords.Data[i].Spam;
      aWord.Integers[_dHm]:=FWords.Data[i].Ham;
      aJSONWords.Add(aWord);
    end;
    aFile:=TStringList.Create;
    try
      aFile.Text:=aJSON.FormatJSON();
      aFile.SaveToFile(FStorageDir+'words.json');
    finally    
      aFile.Free;
    end;
  finally
    aJSON.Free;
  end;
end;

initialization
  _50Probability:=Ln(0.5); // Logarithm of 50 percent probability

end.


unit test.schema_entities;
{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, TypInfo, fpcunit, testutils, testregistry,
  adminhelper_orm;

type
  { Guards the naming contract between the ORM entities and db_schema.sql:
    dOPF derives column names by lowercasing published property names, so
    every column must be all-lowercase without underscores. 0.1.4-8 shipped
    created_at/notify_ok which no generated query could address }
  TTestSchemaEntities = class(TTestCase)
  private
    FTables: TStringList; { table name -> comma-separated column names }
    function FindSchemaFile: String;
    procedure ParseSchema(const aFileName: String);
    function EntityColumns(aEntity: TClass): TStringList;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure SchemaColumnsMatchEntities;
  end;

implementation

type
  TTableEntity = record
    TableName: String;
    Entity: TClass;
  end;

const
  TableEntities: array[0..5] of TTableEntity = (
    (TableName:'users';       Entity:TBotUser),
    (TableName:'messages';    Entity:TTelegramMessage),
    (TableName:'reactions';   Entity:TTelegramReaction),
    (TableName:'complaints';  Entity:TComplaint),
    (TableName:'chatmembers'; Entity:TChatMember),
    (TableName:'memberships'; Entity:TMembership)
  );

function TTestSchemaEntities.FindSchemaFile: String;
const
  Candidates: array[0..4] of String = (
    '', { reserved for TGADMIN_SCHEMA_PATH }
    'db_schema.sql',
    '..\..\src\db_schema.sql',
    '../../src/db_schema.sql',
    '..\src\db_schema.sql'
  );
var
  i: Integer;
  aEnv: String;
begin
  aEnv:=GetEnvironmentVariable('TGADMIN_SCHEMA_PATH');
  for i:=Low(Candidates) to High(Candidates) do
  begin
    if i=Low(Candidates) then
    begin
      if aEnv=EmptyStr then
        Continue;
      Result:=aEnv;
    end
    else
      Result:=Candidates[i];
    if FileExists(Result) then
      Exit;
  end;
  Result:=EmptyStr;
end;

procedure TTestSchemaEntities.ParseSchema(const aFileName: String);
var
  Lines: TStringList;
  s, aTable, aCol: String;
  i, p: Integer;
begin
  Lines:=TStringList.Create;
  try
    Lines.LoadFromFile(aFileName);
    aTable:=EmptyStr;
    for i:=0 to Lines.Count-1 do
    begin
      s:=Trim(Lines[i]);
      if s.StartsWith('CREATE TABLE') then
      begin
        p:=Pos('`', s);
        aTable:=Copy(s, p+1, PosEx('`', s, p+1)-(p+1));
        FTables.Values[aTable]:=EmptyStr;
      end
      else if (aTable<>EmptyStr) and s.StartsWith('`') then
      begin
        { column definition line: `name` type ... }
        p:=PosEx('`', s, 2);
        aCol:=Copy(s, 2, p-2);
        if FTables.Values[aTable]=EmptyStr then
          FTables.Values[aTable]:=aCol
        else
          FTables.Values[aTable]:=FTables.Values[aTable]+','+aCol;
      end
      else if s.StartsWith(')') then
        aTable:=EmptyStr; { key/index lines and the closing paren }
    end;
  finally
    Lines.Free;
  end;
end;

function TTestSchemaEntities.EntityColumns(aEntity: TClass): TStringList;
var
  aList: PPropList;
  aCount, i: Integer;
begin
  Result:=TStringList.Create;
  GetMem(aList, 256*SizeOf(Pointer));
  try
    aCount:=GetPropList(aEntity.ClassInfo, tkProperties, aList, False);
    for i:=0 to aCount-1 do
      Result.Add(LowerCase(aList^[i]^.Name));
  finally
    FreeMem(aList);
  end;
end;

procedure TTestSchemaEntities.SetUp;
var
  aFile: String;
begin
  FTables:=TStringList.Create;
  FTables.Duplicates:=dupError;
  aFile:=FindSchemaFile;
  if aFile=EmptyStr then
    Fail('db_schema.sql not found: run from the tests directory or set TGADMIN_SCHEMA_PATH');
  ParseSchema(aFile);
end;

procedure TTestSchemaEntities.TearDown;
begin
  FTables.Free;
end;

procedure TTestSchemaEntities.SchemaColumnsMatchEntities;
var
  aPair: TTableEntity;
  aEntityCols, aSchemaCols: TStringList;
  aCol: String;
begin
  for aPair in TableEntities do
  begin
    AssertTrue('table '+aPair.TableName+' must exist in db_schema.sql',
      FTables.IndexOfName(aPair.TableName)>=0);
    aSchemaCols:=TStringList.Create;
    try
      aSchemaCols.StrictDelimiter:=True;
      aSchemaCols.Delimiter:=',';
      aSchemaCols.DelimitedText:=FTables.Values[aPair.TableName];
      aEntityCols:=EntityColumns(aPair.Entity);
      try
        { Every published property must map to an existing schema column,
          keeping the all-lowercase convention }
        for aCol in aEntityCols do
        begin
          AssertTrue('column name must not contain an underscore: '+
            aPair.TableName+'.'+aCol, Pos('_', aCol)=0);
          AssertTrue('property '+aCol+' has no column in table '+aPair.TableName,
            aSchemaCols.IndexOf(aCol)>=0);
        end;
        { Every schema column must be addressed by some property, otherwise
          the row is written or read only partially }
        for aCol in aSchemaCols do
          AssertTrue('column '+aPair.TableName+'.'+aCol+' is not mapped by any '+
            'published property of '+aPair.Entity.ClassName,
            aEntityCols.IndexOf(aCol)>=0);
      finally
        aEntityCols.Free;
      end;
    finally
      aSchemaCols.Free;
    end;
  end;
end;

initialization
  RegisterTest(TTestSchemaEntities);

end.

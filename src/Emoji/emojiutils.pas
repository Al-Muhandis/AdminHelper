unit emojiutils;

{$mode ObjFPC}{$H+}

interface

uses
  Classes
  ;

function IsEmoji(const aUTF8Char: String): Boolean;
function CountEmojis(const aUTF8Str: string): Integer;

implementation

uses
  SysUtils
  ;

function UTF8ToBytes(const s: String): TBytes;
begin
  Assert(StringElementSize(s)=1);
  Initialize(Result);
  SetLength(Result, Length(s)+1);
  if Length(Result)>0 then
    Move(s[1], Result[0], Length(s));
  Result[high(Result)] := 0;
end;

function IsEmoji(const Bytes: TBytes; Index: Integer): Boolean;
var
  CodePoint: Integer;
begin
  Result := False;

   // Check the length of sequence
  if (Bytes[Index] and $F0) = $F0 then // 4-byte sequence
  begin
    if Index + 3 < Length(Bytes) then
    begin
      CodePoint := ((Bytes[Index] and $07) shl 18) or
                   ((Bytes[Index + 1] and $3F) shl 12) or
                   ((Bytes[Index + 2] and $3F) shl 6) or
                   (Bytes[Index + 3] and $3F);
      // Check ranges of emojies
      Result := (CodePoint >= $1F600) and (CodePoint <= $1F64F) or // Emoticons
                (CodePoint >= $1F300) and (CodePoint <= $1F5FF) or // Misc Symbols and Pictographs
                (CodePoint >= $1F680) and (CodePoint <= $1F6FF) or // Transport and Map Symbols
                (CodePoint >= $1F700) and (CodePoint <= $1F77F) or // Alchemical Symbols
                (CodePoint >= $2600) and (CodePoint <= $26FF);     // Miscellaneous Symbols
    end;
  end
  else if (Bytes[Index] and $E0) = $E0 then // 3-byte sequence
  begin
    if Index + 2 < Length(Bytes) then
    begin
      CodePoint := ((Bytes[Index] and $0F) shl 12) or
                   ((Bytes[Index + 1] and $3F) shl 6) or
                   (Bytes[Index + 2] and $3F);
      // Check ranges of emojies
      Result := (CodePoint >= $1F600) and (CodePoint <= $1F64F) or // Emoticons
                (CodePoint >= $1F300) and (CodePoint <= $1F5FF) or // Misc Symbols and Pictographs
                (CodePoint >= $1F680) and (CodePoint <= $1F6FF) or // Transport and Map Symbols
                (CodePoint >= $1F700) and (CodePoint <= $1F77F) or // Alchemical Symbols
                (CodePoint >= $2600) and (CodePoint <= $26FF);     // Miscellaneous Symbols
    end;
  end
  else if (Bytes[Index] and $C0) = $C0 then // 2-byte sequence
  begin
    if Index + 1 < Length(Bytes) then
    begin
      CodePoint := ((Bytes[Index] and $1F) shl 6) or
                   (Bytes[Index + 1] and $3F);
      // Check ranges of emojies, if it needs
      // But most emojis starting with a 2 byte sequence are not used.
    end;
  end;
end;

function IsEmoji(const aUTF8Char: String): Boolean;
begin
  Result:=IsEmoji(UTF8ToBytes(aUTF8Char), 0);
end;

function CountEmojis(const aUTF8Str: string): Integer;
var
  Bytes: TBytes;
  I: Integer;
begin
  Result := 0;
  // Convert the string to a byte array (UTF-8)
  Bytes := UTF8ToBytes(aUTF8Str);

  // Iterate through the byte array
  I := 0;
  while I < Length(Bytes) do
  begin
    if IsEmoji(Bytes, I) then
    begin
      Inc(Result);
      // Move the index forward based on the length of the emoji
      if (Bytes[I] and $F0) = $F0 then
        Inc(I, 4) // 4-byte emoji
      else if (Bytes[I] and $E0) = $E0 then
        Inc(I, 3) // 3-byte emoji
      else if (Bytes[I] and $C0) = $C0 then
        Inc(I, 2) // 2-byte emoji
      else
        Inc(I); // Regular character (1 byte)
    end
    else
      Inc(I); // Regular character (1 byte)
  end;
end;

end.


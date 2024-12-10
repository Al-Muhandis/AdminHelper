unit testemojies;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry
  ;

type

  { TTestEmojies }

  TTestEmojies= class(TTestCase)
  published
    procedure IsEmoji;
    procedure CountEmojies;
  end;

implementation

uses
  emojiutils
  ;

const
  _emjTest1='🗿';
  _sTest2='a';   
  _sTest3='Щ';
  _sTest4='island';

procedure TTestEmojies.IsEmoji;
begin
  if not emojiutils.IsEmoji(_emjTest1) then
    Fail(_emjTest1+' is emoji!');
  if emojiutils.IsEmoji(_sTest2) then
    Fail('"%s" is not emoji!', [_sTest2]);
  if emojiutils.IsEmoji(_sTest3) then
    Fail('"%s" is not emoji!', [_sTest3]);
  if emojiutils.IsEmoji(_sTest4) then
    Fail('"%s" is not emoji!', [_sTest4]);
end;

procedure TTestEmojies.CountEmojies;
begin
  if CountEmojis('Здравствуйте, нужен человек')>0 then
    Fail('There are not emojies in the string!');
  if CountEmojis('🗿')<>1 then
    Fail('There is one emoji in the string!');   
  if CountEmojis('🔤🔤🔤🔤🔤   🔤🔤🔤🔤❄️ 💚💚💚💚💚💚💚 '+LineEnding+
    '️▪️▪️▪️▪️▪️  ▪️▪️▪️▪️▪️▪️ ❄️👾👾👾👾👾👾👾👾👾')<10 then
    Fail('There are more than 10 emojies in the string!');
end;



initialization

  RegisterTest(TTestEmojies);
end.


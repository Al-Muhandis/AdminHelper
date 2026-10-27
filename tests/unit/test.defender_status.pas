unit test.defender_status;
{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry,
  telegram_cmn;

type
  TTestDefenderStatus = class(TTestCase)
  published
    procedure StatusThresholdsAreInclusive;
    procedure MarkOnlyForActiveRanks;
    procedure StatusTextCombinesMarkAndName;
    procedure TagShownForPatrolAndAbove;
    procedure TagHiddenForUnknownRate;
    procedure NextRankHintCountsToPatrol;
    procedure NextRankHintCountsToGuard;
    procedure NextRankHintAbsentForGuard;
  end;

implementation

const
  PatrolRate=11;
  GuardRate=33;

procedure TTestDefenderStatus.StatusThresholdsAreInclusive;
begin
  CheckEquals(Ord(dsStandard), Ord(DefenderStatusOf(0, PatrolRate, GuardRate)), 'zero rate is Standard');
  CheckEquals(Ord(dsStandard), Ord(DefenderStatusOf(-7, PatrolRate, GuardRate)), 'negative rate is Standard');
  CheckEquals(Ord(dsPatrol), Ord(DefenderStatusOf(PatrolRate, PatrolRate, GuardRate)), 'exact PatrolRate is Patrol');
  CheckEquals(Ord(dsPatrol), Ord(DefenderStatusOf(GuardRate-1, PatrolRate, GuardRate)), 'rate below GuardRate is Patrol');
  CheckEquals(Ord(dsGuard), Ord(DefenderStatusOf(GuardRate, PatrolRate, GuardRate)), 'exact GuardRate is Guard');
end;

procedure TTestDefenderStatus.MarkOnlyForActiveRanks;
begin
  CheckEquals('', DefenderMark(dsStandard), 'Standard has no mark');
  CheckTrue(DefenderMark(dsPatrol)<>EmptyStr, 'Patrol has a mark');
  CheckTrue(DefenderMark(dsGuard)<>EmptyStr, 'Guard has a mark');
  CheckTrue(DefenderMark(dsPatrol)<>DefenderMark(dsGuard), 'ranks have distinct marks');
end;

procedure TTestDefenderStatus.StatusTextCombinesMarkAndName;
begin
  CheckEquals('Standard', DefenderStatusText(dsStandard), 'Standard text has no mark');
  CheckTrue(Pos(DefenderMark(dsPatrol), DefenderStatusText(dsPatrol))>0, 'Patrol text starts with the mark');
  CheckTrue(Pos(DefenderMark(dsGuard), DefenderStatusText(dsGuard))>0, 'Guard text starts with the mark');
end;

procedure TTestDefenderStatus.TagShownForPatrolAndAbove;
begin
  CheckEquals('', DefenderTag(PatrolRate-1, PatrolRate, GuardRate), 'no tag below PatrolRate');
  CheckTrue(Pos(DefenderMark(dsPatrol), DefenderTag(PatrolRate, PatrolRate, GuardRate))>0,
    'Patrol tag contains the mark');
  CheckTrue(Pos(PatrolRate.ToString, DefenderTag(PatrolRate, PatrolRate, GuardRate))>0,
    'Patrol tag contains the rate');
  CheckTrue(Pos('89', DefenderTag(89, PatrolRate, GuardRate))>0, 'high rate tag contains the rate');
end;

procedure TTestDefenderStatus.TagHiddenForUnknownRate;
begin
  CheckEquals('', DefenderTag(-1, PatrolRate, GuardRate), 'unknown rate (-1) shows no tag');
end;

procedure TTestDefenderStatus.NextRankHintCountsToPatrol;
var
  aHint: String;
begin
  aHint:=NextRankHint(0, PatrolRate, GuardRate);
  CheckTrue(Pos(DefenderMark(dsPatrol), aHint)>0, 'hint to Patrol contains the Patrol mark');
  CheckTrue(Pos(PatrolRate.ToString, aHint)>0, 'hint contains the points left');
  CheckTrue(Pos((PatrolRate+5).ToString, aHint)=0, 'hint must not contain a wrong points count');
end;

procedure TTestDefenderStatus.NextRankHintCountsToGuard;
var
  aHint: String;
begin
  aHint:=NextRankHint(20, PatrolRate, GuardRate);
  CheckTrue(Pos(DefenderMark(dsGuard), aHint)>0, 'hint from Patrol goes to the Guard mark');
  CheckTrue(Pos((GuardRate-20).ToString, aHint)>0, 'hint contains the points left');
end;

procedure TTestDefenderStatus.NextRankHintAbsentForGuard;
begin
  CheckEquals('', NextRankHint(GuardRate, PatrolRate, GuardRate), 'Guard has no next rank');
  CheckEquals('', NextRankHint(GuardRate+100, PatrolRate, GuardRate), 'top rate has no next rank');
end;

initialization
  RegisterTest(TTestDefenderStatus);

end.

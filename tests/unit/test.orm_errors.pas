unit test.orm_errors;
{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testutils, testregistry, adminhelper_orm;

type
  TTestORMErrorClassification = class(TTestCase)
  published
    procedure DuplicateKeyDetected;
    procedure DisconnectMidQueryDetected;
    procedure DisconnectByIdleClientDetected;
    procedure UnretriableErrorsAreNotClassified;
  end;

implementation

procedure TTestORMErrorClassification.DuplicateKeyDetected;
const
  aMsg = 'TMySQL80Connection : Error executing query: Duplicate entry ''-1001-2'' for key ''PRIMARY''';
begin
  AssertTrue('duplicate entry must be classified as such', CheckDuplicateKeyErr(aMsg));
  AssertFalse('a duplicate key is not a disconnect', CheckDisconnectErr(aMsg));
end;

procedure TTestORMErrorClassification.DisconnectMidQueryDetected;
const
  aMsg = 'TMySQL80Connection : Error executing query: Lost connection to MySQL server during query';
begin
  AssertTrue('lost connection mid-query must be retriable', CheckDisconnectErr(aMsg));
  AssertFalse('a disconnect is not a duplicate key', CheckDuplicateKeyErr(aMsg));
end;

procedure TTestORMErrorClassification.DisconnectByIdleClientDetected;
const
  aMsg = 'The client was disconnected by the server because of inactivity';
begin
  AssertTrue('idle disconnect must be retriable', CheckDisconnectErr(aMsg));
end;

procedure TTestORMErrorClassification.UnretriableErrorsAreNotClassified;
const
  aMsg = 'TMySQL80Connection : Error executing query: Unknown column ''createdat'' in ''field list''';
  aDeadlock = 'TMySQL80Connection : Error executing query: Deadlock found when trying to get lock; try restarting transaction';
begin
  AssertFalse('schema errors must propagate, not be retried', CheckDisconnectErr(aMsg));
  AssertFalse('schema errors must propagate, not be deduped', CheckDuplicateKeyErr(aMsg));
  AssertFalse('deadlock is not a disconnect', CheckDisconnectErr(aDeadlock));
  AssertFalse('deadlock is not a duplicate key', CheckDuplicateKeyErr(aDeadlock));
end;

initialization
  RegisterTest(TTestORMErrorClassification);

end.

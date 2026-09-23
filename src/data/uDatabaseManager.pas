unit uDatabaseManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, sqldb, sqlite3conn, db, Generics.Collections;

type
  { Representasi entitas data patogen }
  TPathogenData = record
    ID: Integer;
    Name: string;
    BaseSequence: string;
    CureSequence: string;
    MutationRate: Double;
    HalfLifeSeconds: Integer;
    ComplexityLevel: Integer;
  end;

  { Representasi profil pemain / bio-architect }
  TPlayerProfile = record
    ID: Integer;
    Username: string;
    TotalCredits: Integer;
    LabLevel: Integer;
    HighestStability: Double;
  end;

  { Representasi modul peningkatan laboratorium }
  TLabUpgradeInfo = record
    ID: Integer;
    Code: string;
    Name: string;
    Category: string;
    CurrentLevel: Integer;
    MaxLevel: Integer;
    BaseCost: Integer;
  end;

  { TDatabaseManager: Abstraksi layer data SQLite dengan eksekusi parameter teroptimasi }
  TDatabaseManager = class
  private
    FConnection: TSQLite3Connection;
    FTransaction: TSQLTransaction;
    FDBPath: string;

    procedure ConfigurePragmas;
    procedure ExecuteDirectSQL(const ASQL: string);
    procedure CreateTables;
    procedure SeedDefaultData;
  public
    constructor Create(const ADBPath: string);
    destructor Destroy; override;

    { Inisialisasi koneksi, skema DDL, dan data awal }
    procedure Initialize;

    { Operasi Player Profile }
    function GetOrCreatePlayer(const AUsername: string): TPlayerProfile;
    procedure UpdatePlayerStats(APlayerID: Integer; AAddedCredits: Integer; AStability: Double);

    { Operasi Patogen }
    function GetPathogenByID(AID: Integer; out AData: TPathogenData): Boolean;
    function GetFirstPathogen(out AData: TPathogenData): Boolean;

    { Operasi Toko & Lab Upgrades }
    function GetAllUpgrades: specialize TArray<TLabUpgradeInfo>;
    function PurchaseUpgrade(APlayerID: Integer; const AUpgradeCode: string; out AMessage: string; out AUpdatedCredits: Integer): Boolean;

    { Operasi Telemetri & Riwayat Simulasi }
    procedure SaveRunHistory(APlayerID, APathogenID: Integer;
      AStability, AContamination: Double; ASuccess: Boolean);
  end;

implementation

{ TDatabaseManager }

constructor TDatabaseManager.Create(const ADBPath: string);
begin
  inherited Create;
  FDBPath := ADBPath;

  // Inisialisasi komponen koneksi sqldb bawaan FPC
  FConnection := TSQLite3Connection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);

  FConnection.Transaction := FTransaction;
  FConnection.DatabaseName := FDBPath;
  FConnection.CharSet := 'UTF-8';
end;

destructor TDatabaseManager.Destroy;
begin
  if FConnection.Connected then
  begin
    if FTransaction.Active then
      FTransaction.Rollback;
    FConnection.Close;
  end;

  FTransaction.Free;
  FConnection.Free;
  inherited Destroy;
end;

procedure TDatabaseManager.ConfigurePragmas;
begin
  // --- PERBAIKAN BUG TRANSAKSI ---
  // Eksekusi Pragma langsung di koneksi menggunakan ExecuteDirect.
  // WAL dinonaktifkan untuk MVP karena SQLite menolak mode WAL di dalam transaksi (sqldb defaults).
  try
    if FTransaction.Active then
      FTransaction.Commit; // Pastikan tidak ada transaksi yang menggantung

    FConnection.ExecuteDirect('PRAGMA synchronous = NORMAL;');
    FConnection.ExecuteDirect('PRAGMA foreign_keys = ON;');
  except
    // Jika engine FPC menolak eksekusi pragma secara langsung, abaikan dengan aman
  end;
end;

procedure TDatabaseManager.ExecuteDirectSQL(const ASQL: string);
var
  Qry: TSQLQuery;
begin
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;
    Qry.SQL.Text := ASQL;

    if not FTransaction.Active then
      FTransaction.StartTransaction;

    Qry.ExecSQL;
    FTransaction.Commit;
  except
    on E: Exception do
    begin
      if FTransaction.Active then
        FTransaction.Rollback;
      raise Exception.CreateFmt('DB Execute Error [%s]: %s', [ASQL, E.Message]);
    end;
  end;
  Qry.Free;
end;

procedure TDatabaseManager.CreateTables;
const
  SQL_SCHEMA =
    'CREATE TABLE IF NOT EXISTS player_profile (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    '  username VARCHAR(50) NOT NULL UNIQUE, ' +
    '  total_credits INTEGER DEFAULT 0, ' +
    '  lab_level INTEGER DEFAULT 1, ' +
    '  highest_stability_achieved REAL DEFAULT 0.0, ' +
    '  created_at DATETIME DEFAULT CURRENT_TIMESTAMP' +
    ');' +
    'CREATE TABLE IF NOT EXISTS pathogen_catalog (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    '  pathogen_name VARCHAR(100) NOT NULL, ' +
    '  base_sequence TEXT NOT NULL, ' +
    '  cure_sequence TEXT NOT NULL, ' +
    '  mutation_rate REAL DEFAULT 0.0, ' +
    '  half_life_seconds INTEGER NOT NULL, ' +
    '  complexity_level INTEGER DEFAULT 1' +
    ');' +
    'CREATE TABLE IF NOT EXISTS lab_upgrades (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    '  upgrade_code VARCHAR(50) UNIQUE NOT NULL, ' +
    '  upgrade_name VARCHAR(100) NOT NULL, ' +
    '  category VARCHAR(50) NOT NULL, ' +
    '  current_level INTEGER DEFAULT 0, ' +
    '  max_level INTEGER DEFAULT 5, ' +
    '  base_cost INTEGER NOT NULL' +
    ');' +
    'CREATE TABLE IF NOT EXISTS run_history (' +
    '  id INTEGER PRIMARY KEY AUTOINCREMENT, ' +
    '  player_id INTEGER NOT NULL, ' +
    '  pathogen_id INTEGER NOT NULL, ' +
    '  stability_score REAL NOT NULL, ' +
    '  contamination_level REAL NOT NULL, ' +
    '  is_success BOOLEAN NOT NULL, ' +
    '  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP, ' +
    '  FOREIGN KEY (player_id) REFERENCES player_profile(id), ' +
    '  FOREIGN KEY (pathogen_id) REFERENCES pathogen_catalog(id)' +
    ');';
begin
  ExecuteDirectSQL(SQL_SCHEMA);
end;

procedure TDatabaseManager.SeedDefaultData;
var
  Qry: TSQLQuery;
  Count: Integer;
begin
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    // Pastikan katalog patogen awal terisi jika tabel masih kosong
    Qry.SQL.Text := 'SELECT COUNT(*) FROM pathogen_catalog;';
    Qry.Open;
    Count := Qry.Fields[0].AsInteger;
    Qry.Close;

    if Count = 0 then
    begin
      if not FTransaction.Active then
        FTransaction.StartTransaction;

      // Seed patogen awal untuk fase tutorial / MVP
      Qry.SQL.Text :=
        'INSERT INTO pathogen_catalog (pathogen_name, base_sequence, cure_sequence, mutation_rate, half_life_seconds, complexity_level) ' +
        'VALUES (:name, :base_seq, :cure_seq, :mut_rate, :half_life, :comp);';

      Qry.Params.ParamByName('name').AsString := 'SYNTH-01 Primus';
      Qry.Params.ParamByName('base_seq').AsString := 'ATGCGATCGATCGATCGCTA';
      Qry.Params.ParamByName('cure_seq').AsString := 'TACGCTAGCTAGCTAGCGAT';
      Qry.Params.ParamByName('mut_rate').AsFloat := 0.05;
      Qry.Params.ParamByName('half_life').AsInteger := 90;
      Qry.Params.ParamByName('comp').AsInteger := 1;
      Qry.ExecSQL;

      // Seed upgrade laboratorium standar + Upgrade System Breach (FIREWALL)
      Qry.SQL.Text :=
        'INSERT INTO lab_upgrades (upgrade_code, upgrade_name, category, current_level, max_level, base_cost) VALUES ' +
        '(''AUTO_ALIGNER'', ''Neural Auto-Aligner'', ''HARDWARE'', 0, 5, 250), ' +
        '(''HEAT_SINK'', ''Cryo-Cooling Heat Sink'', ''COOLING'', 0, 5, 150), ' +
        '(''MEM_EXPANSION'', ''Quantum Buffer Extension'', ''TERMINAL'', 0, 3, 300), ' +
        '(''FIREWALL'', ''ICE Protocol Firewall'', ''SECURITY'', 0, 3, 500);'; // Modul khusus untuk pertahanan sabotase
      Qry.ExecSQL;

      FTransaction.Commit;
    end;
  finally
    Qry.Free;
  end;
end;

procedure TDatabaseManager.Initialize;
var
  DBFolder: string;
begin
  DBFolder := ExtractFileDir(FDBPath);
  if (DBFolder <> '') and not DirectoryExists(DBFolder) then
    ForceDirectories(DBFolder);

  FConnection.Open;
  ConfigurePragmas;
  CreateTables;
  SeedDefaultData;
end;

function TDatabaseManager.GetOrCreatePlayer(const AUsername: string): TPlayerProfile;
var
  Qry: TSQLQuery;
begin
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    // Cari pemain berdasarkan username
    Qry.SQL.Text := 'SELECT id, username, total_credits, lab_level, highest_stability_achieved ' +
                    'FROM player_profile WHERE username = :uname LIMIT 1;';
    Qry.Params.ParamByName('uname').AsString := AUsername;
    Qry.Open;

    if not Qry.IsEmpty then
    begin
      Result.ID := Qry.FieldByName('id').AsInteger;
      Result.Username := Qry.FieldByName('username').AsString;
      Result.TotalCredits := Qry.FieldByName('total_credits').AsInteger;
      Result.LabLevel := Qry.FieldByName('lab_level').AsInteger;
      Result.HighestStability := Qry.FieldByName('highest_stability_achieved').AsFloat;
    end
    else
    begin
      Qry.Close;
      if not FTransaction.Active then
        FTransaction.StartTransaction;

      // Buat pemain baru jika belum ditemukan
      Qry.SQL.Text := 'INSERT INTO player_profile (username, total_credits, lab_level, highest_stability_achieved) ' +
                      'VALUES (:uname, 0, 1, 0.0);';
      Qry.Params.ParamByName('uname').AsString := AUsername;
      Qry.ExecSQL;
      FTransaction.Commit;

      // Ambil record yang baru saja dibuat
      Qry.SQL.Text := 'SELECT id, username, total_credits, lab_level, highest_stability_achieved ' +
                      'FROM player_profile WHERE username = :uname LIMIT 1;';
      Qry.Params.ParamByName('uname').AsString := AUsername;
      Qry.Open;

      Result.ID := Qry.FieldByName('id').AsInteger;
      Result.Username := Qry.FieldByName('username').AsString;
      Result.TotalCredits := Qry.FieldByName('total_credits').AsInteger;
      Result.LabLevel := Qry.FieldByName('lab_level').AsInteger;
      Result.HighestStability := Qry.FieldByName('highest_stability_achieved').AsFloat;
    end;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

procedure TDatabaseManager.UpdatePlayerStats(APlayerID: Integer; AAddedCredits: Integer; AStability: Double);
var
  Qry: TSQLQuery;
begin
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    if not FTransaction.Active then
      FTransaction.StartTransaction;

    Qry.SQL.Text :=
      'UPDATE player_profile SET ' +
      '  total_credits = total_credits + :credits, ' +
      '  highest_stability_achieved = MAX(highest_stability_achieved, :stab) ' +
      'WHERE id = :id;';

    Qry.Params.ParamByName('credits').AsInteger := AAddedCredits;
    Qry.Params.ParamByName('stab').AsFloat := AStability;
    Qry.Params.ParamByName('id').AsInteger := APlayerID;

    Qry.ExecSQL;
    FTransaction.Commit;
  except
    on E: Exception do
    begin
      if FTransaction.Active then
        FTransaction.Rollback;
      raise;
    end;
  end;
  Qry.Free;
end;

function TDatabaseManager.GetPathogenByID(AID: Integer; out AData: TPathogenData): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    Qry.SQL.Text := 'SELECT id, pathogen_name, base_sequence, cure_sequence, ' +
                    'mutation_rate, half_life_seconds, complexity_level ' +
                    'FROM pathogen_catalog WHERE id = :id LIMIT 1;';
    Qry.Params.ParamByName('id').AsInteger := AID;
    Qry.Open;

    if not Qry.IsEmpty then
    begin
      AData.ID := Qry.FieldByName('id').AsInteger;
      AData.Name := Qry.FieldByName('pathogen_name').AsString;
      AData.BaseSequence := Qry.FieldByName('base_sequence').AsString;
      AData.CureSequence := Qry.FieldByName('cure_sequence').AsString;
      AData.MutationRate := Qry.FieldByName('mutation_rate').AsFloat;
      AData.HalfLifeSeconds := Qry.FieldByName('half_life_seconds').AsInteger;
      AData.ComplexityLevel := Qry.FieldByName('complexity_level').AsInteger;
      Result := True;
    end;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TDatabaseManager.GetFirstPathogen(out AData: TPathogenData): Boolean;
var
  Qry: TSQLQuery;
begin
  Result := False;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    Qry.SQL.Text := 'SELECT id, pathogen_name, base_sequence, cure_sequence, ' +
                    'mutation_rate, half_life_seconds, complexity_level ' +
                    'FROM pathogen_catalog ORDER BY id ASC LIMIT 1;';
    Qry.Open;

    if not Qry.IsEmpty then
    begin
      AData.ID := Qry.FieldByName('id').AsInteger;
      AData.Name := Qry.FieldByName('pathogen_name').AsString;
      AData.BaseSequence := Qry.FieldByName('base_sequence').AsString;
      AData.CureSequence := Qry.FieldByName('cure_sequence').AsString;
      AData.MutationRate := Qry.FieldByName('mutation_rate').AsFloat;
      AData.HalfLifeSeconds := Qry.FieldByName('half_life_seconds').AsInteger;
      AData.ComplexityLevel := Qry.FieldByName('complexity_level').AsInteger;
      Result := True;
    end;
    Qry.Close;
  finally
    Qry.Free;
  end;
end;

function TDatabaseManager.GetAllUpgrades: specialize TArray<TLabUpgradeInfo>;
var
  Qry: TSQLQuery;
  List: specialize TList<TLabUpgradeInfo>;
  Item: TLabUpgradeInfo;
begin
  List := specialize TList<TLabUpgradeInfo>.Create;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;
    Qry.SQL.Text := 'SELECT id, upgrade_code, upgrade_name, category, current_level, max_level, base_cost FROM lab_upgrades;';
    Qry.Open;

    while not Qry.EOF do
    begin
      Item.ID := Qry.FieldByName('id').AsInteger;
      Item.Code := Qry.FieldByName('upgrade_code').AsString;
      Item.Name := Qry.FieldByName('upgrade_name').AsString;
      Item.Category := Qry.FieldByName('category').AsString;
      Item.CurrentLevel := Qry.FieldByName('current_level').AsInteger;
      Item.MaxLevel := Qry.FieldByName('max_level').AsInteger;
      Item.BaseCost := Qry.FieldByName('base_cost').AsInteger;
      List.Add(Item);
      Qry.Next;
    end;
    Qry.Close;
    Result := List.ToArray;
  finally
    Qry.Free;
    List.Free;
  end;
end;

function TDatabaseManager.PurchaseUpgrade(APlayerID: Integer; const AUpgradeCode: string; out AMessage: string; out AUpdatedCredits: Integer): Boolean;
var
  Qry: TSQLQuery;
  PlayerCredits, CurrentLevel, MaxLevel, BaseCost, Cost: Integer;
begin
  Result := False;
  AUpdatedCredits := 0;
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    // 1. Ambil kredit pemain saat ini
    Qry.SQL.Text := 'SELECT total_credits FROM player_profile WHERE id = :pid LIMIT 1;';
    Qry.Params.ParamByName('pid').AsInteger := APlayerID;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      AMessage := 'Player profile not found.';
      Exit;
    end;
    PlayerCredits := Qry.FieldByName('total_credits').AsInteger;
    Qry.Close;

    // 2. Ambil data upgrade berdasarkan kode
    Qry.SQL.Text := 'SELECT current_level, max_level, base_cost FROM lab_upgrades WHERE upgrade_code = :code LIMIT 1;';
    Qry.Params.ParamByName('code').AsString := AUpgradeCode;
    Qry.Open;
    if Qry.IsEmpty then
    begin
      AMessage := Format('Upgrade code "%s" not found in catalog.', [AUpgradeCode]);
      Exit;
    end;

    CurrentLevel := Qry.FieldByName('current_level').AsInteger;
    MaxLevel := Qry.FieldByName('max_level').AsInteger;
    BaseCost := Qry.FieldByName('base_cost').AsInteger;
    Qry.Close;

    // 3. Validasi batas level maksimal
    if CurrentLevel >= MaxLevel then
    begin
      AMessage := Format('Module "%s" is already at maximum level (%d/%d).', [AUpgradeCode, CurrentLevel, MaxLevel]);
      Exit;
    end;

    // 4. Hitung biaya upgrade level berikutnya
    Cost := BaseCost * (CurrentLevel + 1);
    if PlayerCredits < Cost then
    begin
      AMessage := Format('Insufficient credits. Required: %d CR, Available: %d CR.', [Cost, PlayerCredits]);
      Exit;
    end;

    // 5. Eksekusi transaksi pembelian (Kurangi kredit pemain & naikkan level upgrade)
    if not FTransaction.Active then
      FTransaction.StartTransaction;

    Qry.SQL.Text := 'UPDATE player_profile SET total_credits = total_credits - :cost WHERE id = :pid;';
    Qry.Params.ParamByName('cost').AsInteger := Cost;
    Qry.Params.ParamByName('pid').AsInteger := APlayerID;
    Qry.ExecSQL;

    Qry.SQL.Text := 'UPDATE lab_upgrades SET current_level = current_level + 1 WHERE upgrade_code = :code;';
    Qry.Params.ParamByName('code').AsString := AUpgradeCode;
    Qry.ExecSQL;

    FTransaction.Commit;

    AUpdatedCredits := PlayerCredits - Cost;
    AMessage := Format('Successfully upgraded %s to Level %d!', [AUpgradeCode, CurrentLevel + 1]);
    Result := True;
  except
    on E: Exception do
    begin
      if FTransaction.Active then
        FTransaction.Rollback;
      AMessage := 'Transaction Error: ' + E.Message;
    end;
  end;
  Qry.Free;
end;

procedure TDatabaseManager.SaveRunHistory(APlayerID, APathogenID: Integer;
  AStability, AContamination: Double; ASuccess: Boolean);
var
  Qry: TSQLQuery;
begin
  Qry := TSQLQuery.Create(nil);
  try
    Qry.DataBase := FConnection;
    Qry.Transaction := FTransaction;

    if not FTransaction.Active then
      FTransaction.StartTransaction;

    Qry.SQL.Text :=
      'INSERT INTO run_history (player_id, pathogen_id, stability_score, contamination_level, is_success) ' +
      'VALUES (:pid, :path_id, :stab, :contam, :success);';

    Qry.Params.ParamByName('pid').AsInteger := APlayerID;
    Qry.Params.ParamByName('path_id').AsInteger := APathogenID;
    Qry.Params.ParamByName('stab').AsFloat := AStability;
    Qry.Params.ParamByName('contam').AsFloat := AContamination;
    Qry.Params.ParamByName('success').AsBoolean := ASuccess;

    Qry.ExecSQL;
    FTransaction.Commit;
  except
    on E: Exception do
    begin
      if FTransaction.Active then
        FTransaction.Rollback;
      raise;
    end;
  end;
  Qry.Free;
end;

end.

unit uGenomData;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, RegExpr, uDatabaseManager;

type
  { Deklarasi Event untuk memicu pembaruan UI secara aman }
  TGenomStateEvent = procedure(Sender: TObject) of object;
  TGenomMutationEvent = procedure(Sender: TObject; NodeIndex: Integer; OldBase, NewBase: Char) of object;

  { TGenomData: Model Logika Inti untuk Simulasi Patogen }
  TGenomData = class
  private
    FBaseSequence: string;
    FTargetSequence: string;  { Sekuens penawar yang benar }
    FCurrentSequence: string; { Sekuens yang sedang dimanipulasi pemain }
    FHalfLifeSeconds: Integer;
    FMutationRate: Double;

    FStability: Double;       { 100.0 turun ke 0.0 }
    FContamination: Double;   { 0.0 naik ke 100.0 }
    FHeat: Double;            // Suhu sintesis (0.0 up to 100.0)

    { Event Callbacks }
    FOnStateChanged: TGenomStateEvent;
    FOnMutation: TGenomMutationEvent;
    FOnGameOver: TGenomStateEvent;
    FOnSuccess: TGenomStateEvent;

    { Cache Regular Expression Engine untuk efisiensi memori }
    FRegexEngine: TRegExpr;

    function GetRandomBase(ExcludeBase: Char = ' '): Char;
    procedure EvaluateWinLossCondition;
  public
    constructor Create;
    destructor Destroy; override;

    { Memuat patogen baru dari Database }
    procedure LoadPathogen(const APathogen: TPathogenData);

    { Dipanggil oleh Game Loop (Engine) menggunakan DeltaTime (detik) }
    procedure Update(DeltaTimeSeconds: Double);

    { Aksi Pemain }
    function ExecuteRegExpr(const APattern, AReplacement: string; out AErrorMsg: string): Boolean;
    procedure CoolDownHeat(Amount: Double);

    { Properties }
    property BaseSequence: string read FBaseSequence;
    property TargetSequence: string read FTargetSequence;
    property CurrentSequence: string read FCurrentSequence;

    property Stability: Double read FStability;
    property Contamination: Double read FContamination;
    property Heat: Double read FHeat;

    { Event Listeners (Di-bind ke fMain/UI) }
    property OnStateChanged: TGenomStateEvent read FOnStateChanged write FOnStateChanged;
    property OnMutation: TGenomMutationEvent read FOnMutation write FOnMutation;
    property OnGameOver: TGenomStateEvent read FOnGameOver write FOnGameOver;
    property OnSuccess: TGenomStateEvent read FOnSuccess write FOnSuccess;
  end;

implementation

{ TGenomData }

constructor TGenomData.Create;
begin
  inherited Create;
  // Membuat instance TRegExpr satu kali saja di awal (Mencegah Memory Fragmentation)
  FRegexEngine := TRegExpr.Create;
  // Modifier RegExpr: Case-insensitive, multi-line off
  FRegexEngine.ModifierI := True;
end;

destructor TGenomData.Destroy;
begin
  FRegexEngine.Free;
  inherited Destroy;
end;

procedure TGenomData.LoadPathogen(const APathogen: TPathogenData);
begin
  FBaseSequence := APathogen.BaseSequence;
  FTargetSequence := APathogen.CureSequence;

  // Awalnya pemain melihat Base Sequence, yang perlahan harus diubah menjadi Target Sequence
  FCurrentSequence := FBaseSequence;

  FHalfLifeSeconds := APathogen.HalfLifeSeconds;
  FMutationRate := APathogen.MutationRate;

  // Reset Parameter Telemetri
  FStability := 100.0;
  FContamination := 0.0;
  FHeat := 0.0;

  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);
end;

function TGenomData.GetRandomBase(ExcludeBase: Char): Char;
const
  BASES: array[0..3] of Char = ('A', 'T', 'C', 'G');
var
  NewBase: Char;
begin
  repeat
    NewBase := BASES[Random(4)];
  until NewBase <> ExcludeBase;
  Result := NewBase;
end;

procedure TGenomData.Update(DeltaTimeSeconds: Double);
var
  TargetIndex: Integer;
  OldBase, NewBase: Char;
begin
  if (FStability <= 0) or (FContamination >= 100) or (FCurrentSequence = FTargetSequence) then
    Exit; // Simulasi sudah berakhir

  // 1. Degradasi Eksponensial (Rumus Waktu Paruh / Half-Life)
  // N(t) = N0 * (0.5 ^ (t / T_half))
  // Menggunakan Math.Power sangat efisien untuk perhitungan real-time
  FStability := FStability * Power(0.5, DeltaTimeSeconds / FHalfLifeSeconds);

  // 2. Kalkulasi Spontaneous Mutation
  // Probabilitas mutasi berdasarkan DeltaTime dan MutationRate patogen
  if Random < (FMutationRate * DeltaTimeSeconds) then
  begin
    TargetIndex := Random(Length(FCurrentSequence)) + 1; // Index string pascal mulai dari 1
    OldBase := FCurrentSequence[TargetIndex];
    NewBase := GetRandomBase(OldBase);

    // Terapkan mutasi pada sekuens saat ini
    FCurrentSequence[TargetIndex] := NewBase;

    // Mutasi meningkatkan kontaminasi
    FContamination := Min(100.0, FContamination + 2.5);

    // Beritahu sistem visual bahwa node tertentu bermutasi (untuk efek Neon Kedip)
    if Assigned(FOnMutation) then
      FOnMutation(Self, TargetIndex, OldBase, NewBase);
  end;

  // Beritahu UI bahwa metrik telah berubah (dibatasi oleh timer Invalidate di UI nanti)
  if Assigned(FOnStateChanged) then
    FOnStateChanged(Self);

  EvaluateWinLossCondition;
end;

procedure TGenomData.EvaluateWinLossCondition;
begin
  // Kondisi Kalah: Sampel hancur (Stability mendekati 0) atau Lab terkontaminasi penuh
  if (FStability <= 0.1) or (FContamination >= 100.0) then
  begin
    if Assigned(FOnGameOver) then
      FOnGameOver(Self);
  end
  // Kondisi Menang: Sekuens pemain sama persis dengan sekues penawar
  else if FCurrentSequence = FTargetSequence then
  begin
    if Assigned(FOnSuccess) then
      FOnSuccess(Self);
  end;
end;

function TGenomData.ExecuteRegExpr(const APattern, AReplacement: string; out AErrorMsg: string): Boolean;
var
  PreviousSequence: string;
begin
  Result := False;
  AErrorMsg := '';

  if FHeat >= 100.0 then
  begin
    AErrorMsg := 'CRITICAL: Synthesizer is overheated! Cooldown required.';
    Exit;
  end;

  try
    FRegexEngine.Expression := APattern;

    // Cek apakah ada pola yang cocok sebelum mengganti
    if FRegexEngine.Exec(FCurrentSequence) then
    begin
      PreviousSequence := FCurrentSequence;

      // ReplaceAll
      FCurrentSequence := FRegexEngine.Replace(FCurrentSequence, AReplacement, True);

      // Menambah beban proses/panas
      FHeat := Min(100.0, FHeat + 15.0);

      // Jika sekuens berubah menjauh atau malah hancur (misal regex ngawur)
      if Length(FCurrentSequence) <> Length(FTargetSequence) then
      begin
        FContamination := Min(100.0, FContamination + 10.0); // Penalti berat
        FCurrentSequence := PreviousSequence; // Rollback
        AErrorMsg := 'ERROR: Synthesis structural integrity compromised. Action blocked.';
      end
      else
      begin
        // Jika penggantian berhasil, periksa kemenangannya
        EvaluateWinLossCondition;
        Result := True;
      end;

      if Assigned(FOnStateChanged) then
        FOnStateChanged(Self);
    end
    else
    begin
      AErrorMsg := 'WARNING: No sequence matched the provided expression.';
    end;
  except
    on E: Exception do
    begin
      AErrorMsg := 'SYNTAX ERROR: ' + E.Message;
    end;
  end;
end;

procedure TGenomData.CoolDownHeat(Amount: Double);
begin
  if FHeat > 0 then
  begin
    FHeat := Max(0.0, FHeat - Amount);
    if Assigned(FOnStateChanged) then
      FOnStateChanged(Self);
  end;
end;

end.


unit uTelemetryManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, TAGraph, TASeries, uGenomData;

type
  { TTelemetryManager:
    Mengelola dan mendistribusikan data ke komponen TAChart secara efisien.
    Menggunakan teknik "Sliding Window" untuk mencegah kebocoran memori pada grafik berdurasi panjang. }
  TTelemetryManager = class
  private
    FGenomData: TGenomData;
    FElapsedTime: Double;
    FMaxDataPoints: Integer;

    { Referensi Seri Grafik Vitals (Metrik Inti) }
    FSeriesStability: TLineSeries;
    FSeriesContamination: TLineSeries;
    FSeriesHeat: TLineSeries;

    { Referensi Seri Grafik Kromatogram DNA (A, T, C, G) }
    FSeriesA, FSeriesT, FSeriesC, FSeriesG: TLineSeries;
    FScanIndex: Double; { Posisi "laser" pembaca DNA }

    procedure TrimSeries(ASeries: TLineSeries);
  public
    { AMaxPoints membatasi jumlah titik data di layar agar rendering tetap 60 FPS }
    constructor Create(AGenomData: TGenomData; AMaxPoints: Integer = 150);

    { Binding komponen UI (fMain) ke Manager }
    procedure AttachVitalSeries(AStability, AContam, AHeat: TLineSeries);
    procedure AttachChromatogramSeries(ASeriesA, ASeriesT, ASeriesC, ASeriesG: TLineSeries);

    { Dipanggil secara asinkron/periodik oleh Timer UI (misal tiap 30-50ms) }
    procedure UpdateVitals(DeltaTimeSeconds: Double);
    procedure UpdateChromatogram(DeltaTimeSeconds: Double);

    { Reset grafik untuk simulasi baru }
    procedure ResetTelemetry;
  end;

implementation

{ TTelemetryManager }

constructor TTelemetryManager.Create(AGenomData: TGenomData; AMaxPoints: Integer);
begin
  inherited Create;
  FGenomData := AGenomData;
  FMaxDataPoints := AMaxPoints;
  FElapsedTime := 0;
  FScanIndex := 1.0;
end;

procedure TTelemetryManager.AttachVitalSeries(AStability, AContam, AHeat: TLineSeries);
begin
  FSeriesStability := AStability;
  FSeriesContamination := AContam;
  FSeriesHeat := AHeat;
end;

procedure TTelemetryManager.AttachChromatogramSeries(ASeriesA, ASeriesT, ASeriesC, ASeriesG: TLineSeries);
begin
  FSeriesA := ASeriesA;
  FSeriesT := ASeriesT;
  FSeriesC := ASeriesC;
  FSeriesG := ASeriesG;
end;

procedure TTelemetryManager.TrimSeries(ASeries: TLineSeries);
begin
  // Teknik Sliding Window: Hapus data paling lama jika melebihi batas (FIFO)
  // Menjaga alokasi memori tetap konstan (O(1) memory overhead)
  if Assigned(ASeries) and (ASeries.Count > FMaxDataPoints) then
    ASeries.Delete(0);
end;

procedure TTelemetryManager.UpdateVitals(DeltaTimeSeconds: Double);
begin
  if not Assigned(FGenomData) then Exit;

  FElapsedTime := FElapsedTime + DeltaTimeSeconds;

  { Update Stability (Turun) }
  if Assigned(FSeriesStability) then
  begin
    FSeriesStability.AddXY(FElapsedTime, FGenomData.Stability);
    TrimSeries(FSeriesStability);
  end;

  { Update Contamination (Naik) }
  if Assigned(FSeriesContamination) then
  begin
    FSeriesContamination.AddXY(FElapsedTime, FGenomData.Contamination);
    TrimSeries(FSeriesContamination);
  end;

  { Update Heat (Fluktuatif) }
  if Assigned(FSeriesHeat) then
  begin
    FSeriesHeat.AddXY(FElapsedTime, FGenomData.Heat);
    TrimSeries(FSeriesHeat);
  end;
end;

procedure TTelemetryManager.UpdateChromatogram(DeltaTimeSeconds: Double);
var
  BaseStr: string;
  CurrentBase: Char;
  IntIndex: Integer;
  ValA, ValT, ValC, ValG: Double;
  Noise: Double;
begin
  if (not Assigned(FGenomData)) or (not Assigned(FSeriesA)) then Exit;

  BaseStr := FGenomData.CurrentSequence;
  if Length(BaseStr) = 0 then Exit;

  // Memajukan sensor pembaca di sepanjang sekuens DNA
  FScanIndex := FScanIndex + (DeltaTimeSeconds * 5.0); // Kecepatan scan
  if FScanIndex >= Length(BaseStr) then
    FScanIndex := 1.0; // Looping pembacaan jika sudah di ujung

  IntIndex := Trunc(FScanIndex);
  CurrentBase := BaseStr[IntIndex];

  // Efek Base Noise (garis dasar kromatogram tidak pernah 100% datar)
  Noise := Random * 0.1;

  // Menghasilkan gelombang Gaussian pseudo untuk basa yang sedang dibaca
  ValA := Noise; ValT := Noise; ValC := Noise; ValG := Noise;

  case CurrentBase of
    'A', 'a': ValA := 1.0 - Random * 0.2; // Puncak gelombang A
    'T', 't': ValT := 1.0 - Random * 0.2; // Puncak gelombang T
    'C', 'c': ValC := 1.0 - Random * 0.2; // Puncak gelombang C
    'G', 'g': ValG := 1.0 - Random * 0.2; // Puncak gelombang G
  end;

  // Terapkan interpolasi sederhana menggunakan Sinusoidal untuk efek gelombang menyambung (smooth)
  // Ini menghindari lonjakan kaku antar garis grafik
  FSeriesA.AddXY(FScanIndex, ValA * Abs(Sin(FScanIndex * Pi)));
  FSeriesT.AddXY(FScanIndex, ValT * Abs(Sin(FScanIndex * Pi)));
  FSeriesC.AddXY(FScanIndex, ValC * Abs(Sin(FScanIndex * Pi)));
  FSeriesG.AddXY(FScanIndex, ValG * Abs(Sin(FScanIndex * Pi)));

  // Trim memori kromatogram (biasanya butuh lebih sedikit point agar lebih renggang/jelas)
  TrimSeries(FSeriesA);
  TrimSeries(FSeriesT);
  TrimSeries(FSeriesC);
  TrimSeries(FSeriesG);
end;

procedure TTelemetryManager.ResetTelemetry;
begin
  FElapsedTime := 0;
  FScanIndex := 1.0;

  if Assigned(FSeriesStability) then FSeriesStability.Clear;
  if Assigned(FSeriesContamination) then FSeriesContamination.Clear;
  if Assigned(FSeriesHeat) then FSeriesHeat.Clear;

  if Assigned(FSeriesA) then FSeriesA.Clear;
  if Assigned(FSeriesT) then FSeriesT.Clear;
  if Assigned(FSeriesC) then FSeriesC.Clear;
  if Assigned(FSeriesG) then FSeriesG.Clear;
end;

end.


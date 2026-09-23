unit uSequenceRenderer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes, uGenomData;

const
  MAX_VISIBLE_NODES = 40;     // Batasi jumlah node yang dirender agar komputasi 3D sangat ringan
  MAX_BIO_PARTICLES = 35;     // Jumlah partikel suspensi mikroskopis di background

type
  { Struktur data penyusun DNA (Rung / Anak Tangga) }
  TRung3D = record
    X1, Y1, Z1: Double; // Titik Strand 1
    X2, Y2, Z2: Double; // Titik Strand 2
    ZCenter: Double;    // Titik tengah Z (untuk sorting Depth/Painter's Algorithm)
    BaseChar: Char;
    ScreenX1, ScreenY1: Double; // Hasil proyeksi ke 2D
    ScreenX2, ScreenY2: Double;
  end;

  { Struktur partikel mikroskopis cair (Bio-Dust / Cellular Suspension) }
  TBioParticle = record
    X, Y: Double;
    SpeedY: Double;
    Radius: Double;
    Alpha: Byte;
    BaseColor: TBGRAPixel;
  end;

  { TSequenceRenderer: Mesin grafis khusus untuk menggambar DNA dan lingkungan lab }
  TSequenceRenderer = class
  private
    FGenomData: TGenomData;
    FRotationAngle: Double;
    FRungs: array[0..MAX_VISIBLE_NODES - 1] of TRung3D;
    FParticles: array[0..MAX_BIO_PARTICLES - 1] of TBioParticle;
    FIsParticlesInitialized: Boolean;
    FLastDeltaTime: Double;
    FBreachMode: Boolean;

    function GetBaseColor(ABase: Char): TBGRAPixel;
    procedure Project3DTo2D(Width, Height: Integer);
    procedure SortRungs;
    procedure InitParticles(Width, Height: Integer);
    procedure DrawSciFiBackground(ABitmap: TBGRABitmap);

    { Fitur Baru: Menggambar panel informasi bola DNA di sudut kanan atas }
    procedure DrawNodeLegend(ABitmap: TBGRABitmap);

    { Setter khusus untuk memicu efek suara saat status Breach berubah }
    procedure SetBreachMode(AValue: Boolean);
  public
    constructor Create(AGenomData: TGenomData);

    { Mengatur rotasi secara independen (dipanggil oleh Timer Invalidate) }
    procedure Update(DeltaTimeSeconds: Double);

    { Menggambar langsung ke BGRABitmap yang disediakan oleh UI }
    procedure Render(ABitmap: TBGRABitmap);

    { Properti untuk memicu efek visual dan audio sabotase (Glitch / Red Alarm) }
    property BreachMode: Boolean read FBreachMode write SetBreachMode;
  end;

implementation

uses
  uAudioManager; // Integrasi pustaka audio BASS

{ TSequenceRenderer }

constructor TSequenceRenderer.Create(AGenomData: TGenomData);
begin
  inherited Create;
  FGenomData := AGenomData;
  FRotationAngle := 0.0;
  FIsParticlesInitialized := False;
  FLastDeltaTime := 0.016; // Default ~60 FPS
  FBreachMode := False;
end;

procedure TSequenceRenderer.SetBreachMode(AValue: Boolean);
begin
  if FBreachMode = AValue then Exit;

  FBreachMode := AValue;

  // Picu efek audio sesuai perubahan state
  if Assigned(AudioManager) then
  begin
    if FBreachMode then
      AudioManager.PlaySFX('assets/audio/breach_alarm.mp3', 0.8)
    else
      AudioManager.PlaySFX('assets/audio/breach_cleared.mp3', 0.6);
  end;
end;

procedure TSequenceRenderer.Update(DeltaTimeSeconds: Double);
begin
  FLastDeltaTime := DeltaTimeSeconds;

  if FBreachMode then
  begin
    // FITUR PAMUNGKAS: Rotasi lebih cepat, agresif, dan bergetar (jitter) saat disabotase
    FRotationAngle := FRotationAngle + (4.0 * DeltaTimeSeconds) + ((Random * 0.2) - 0.1);
  end
  else
  begin
    // Rotasi konstan heliks DNA dalam keadaan normal
    FRotationAngle := FRotationAngle + (1.5 * DeltaTimeSeconds);
  end;

  if FRotationAngle >= (2 * Pi) then
    FRotationAngle := FRotationAngle - (2 * Pi);
  if FRotationAngle < 0 then
    FRotationAngle := FRotationAngle + (2 * Pi);
end;

function TSequenceRenderer.GetBaseColor(ABase: Char): TBGRAPixel;
begin
  // Palet Warna Neon Medis
  case UpCase(ABase) of
    'A': Result := BGRA(0, 255, 255, 255);   // Cyan
    'T': Result := BGRA(255, 50, 100, 255);  // Crimson/Neon Pink
    'C': Result := BGRA(255, 255, 0, 255);   // Neon Yellow
    'G': Result := BGRA(50, 255, 100, 255);  // Toxic Green
    else Result := BGRA(100, 100, 100, 255); // Grey (Unknown/Corrupted)
  end;
end;

procedure TSequenceRenderer.Project3DTo2D(Width, Height: Integer);
var
  i: Integer;
  FocalLength, Scale: Double;
  CenterX, CenterY: Double;
begin
  FocalLength := 400.0; // Simulasi Field of View (FOV) lensa
  CenterX := Width * 0.5;
  CenterY := Height * 0.5;

  for i := 0 to MAX_VISIBLE_NODES - 1 do
  begin
    // Proyeksi Strand 1
    Scale := FocalLength / (FocalLength + FRungs[i].Z1);
    FRungs[i].ScreenX1 := CenterX + (FRungs[i].X1 * Scale);
    FRungs[i].ScreenY1 := CenterY + (FRungs[i].Y1 * Scale);

    // Proyeksi Strand 2
    Scale := FocalLength / (FocalLength + FRungs[i].Z2);
    FRungs[i].ScreenX2 := CenterX + (FRungs[i].X2 * Scale);
    FRungs[i].ScreenY2 := CenterY + (FRungs[i].Y2 * Scale);
  end;
end;

procedure TSequenceRenderer.SortRungs;
var
  i, j: Integer;
  Temp: TRung3D;
begin
  // Insertion Sort untuk mengurutkan ZCenter dari nilai terbesar (belakang) ke terkecil (depan)
  for i := 1 to MAX_VISIBLE_NODES - 1 do
  begin
    Temp := FRungs[i];
    j := i - 1;
    while (j >= 0) and (FRungs[j].ZCenter < Temp.ZCenter) do
    begin
      FRungs[j + 1] := FRungs[j];
      Dec(j);
    end;
    FRungs[j + 1] := Temp;
  end;
end;

procedure TSequenceRenderer.InitParticles(Width, Height: Integer);
var
  i: Integer;
begin
  for i := 0 to MAX_BIO_PARTICLES - 1 do
  begin
    FParticles[i].X := Random(Round(Width));
    FParticles[i].Y := Random(Round(Height));
    FParticles[i].SpeedY := 6.0 + Random(14); // Kecepatan gerak vertikal lambat
    FParticles[i].Radius := 1.0 + Random(2);
    FParticles[i].Alpha := 20 + Random(50);

    // Warna acak antara Cyan pudar dan Toxic Green untuk partikel suspensi sel
    if Random(2) = 0 then
      FParticles[i].BaseColor := BGRA(0, 255, 255, FParticles[i].Alpha)
    else
      FParticles[i].BaseColor := BGRA(50, 255, 100, FParticles[i].Alpha);
  end;
  FIsParticlesInitialized := True;
end;

procedure TSequenceRenderer.DrawSciFiBackground(ABitmap: TBGRABitmap);
var
  i: Integer;
  x, y: Integer;
  GridColor: TBGRAPixel;
  OffsetY: Integer;
  PulseRadius: Double;
begin
  if not FIsParticlesInitialized then
    InitParticles(ABitmap.Width, ABitmap.Height);

  // 1. Latar belakang dasar
  if FBreachMode then
    ABitmap.Fill(BGRA(25, 5, 5, 255))
  else
    ABitmap.Fill(BGRA(4, 8, 14, 255));

  // 2. Efek Garis Grid Monitor Lab
  if FBreachMode then
    GridColor := BGRA(255, 0, 0, 20)
  else
    GridColor := BGRA(0, 200, 220, 10);

  OffsetY := Round(FRotationAngle * 20) mod 40;

  x := 0;
  while x < ABitmap.Width do
  begin
    ABitmap.DrawLineAntialias(x, 0, x, ABitmap.Height, GridColor, 1);
    Inc(x, 40);
  end;

  y := OffsetY;
  while y < ABitmap.Height do
  begin
    ABitmap.DrawLineAntialias(0, y, ABitmap.Width, y, GridColor, 1);
    Inc(y, 40);
  end;

  // 3. Render Partikel
  for i := 0 to MAX_BIO_PARTICLES - 1 do
  begin
    if FBreachMode then
    begin
      FParticles[i].Y := FParticles[i].Y - (FParticles[i].SpeedY * FLastDeltaTime * 4.0);
      FParticles[i].X := FParticles[i].X + (Sin(FParticles[i].Y * 0.1) * 2.0);
    end
    else
    begin
      FParticles[i].Y := FParticles[i].Y - (FParticles[i].SpeedY * FLastDeltaTime);
      FParticles[i].X := FParticles[i].X + (Sin(FParticles[i].Y * 0.05) * 0.5);
    end;

    if FParticles[i].Y < 0 then
    begin
      FParticles[i].Y := ABitmap.Height;
      FParticles[i].X := Random(ABitmap.Width);
    end;

    if FBreachMode then
      ABitmap.FillEllipseAntialias(FParticles[i].X, FParticles[i].Y, FParticles[i].Radius, FParticles[i].Radius, BGRA(255, 50, 50, FParticles[i].Alpha))
    else
      ABitmap.FillEllipseAntialias(FParticles[i].X, FParticles[i].Y, FParticles[i].Radius, FParticles[i].Radius, FParticles[i].BaseColor);
  end;

  // 4. Efek Cincin Scanner
  PulseRadius := 140 + (Sin(FRotationAngle * 2) * 10);

  if FBreachMode then
    ABitmap.EllipseAntialias(ABitmap.Width div 2, ABitmap.Height div 2, PulseRadius, PulseRadius, BGRA(255, 0, 0, 20), 2.5)
  else
    ABitmap.EllipseAntialias(ABitmap.Width div 2, ABitmap.Height div 2, PulseRadius, PulseRadius, BGRA(0, 255, 255, 8), 1.5);
end;

procedure TSequenceRenderer.DrawNodeLegend(ABitmap: TBGRABitmap);
var
  BoxWidth, BoxHeight: Integer;
  BoxX, BoxY: Integer;
  i: Integer;
  TextY: Integer;
  BaseChars: array[0..3] of Char;
  BaseNames: array[0..3] of string;
  BColor: TBGRAPixel;
  BorderColor: TBGRAPixel; // Tambahan variabel untuk warna tepi
begin
  // Tentukan posisi dan ukuran kotak (di sudut kanan atas dari area render)
  BoxWidth := 317 ;//160;
  BoxHeight := 130;// 120;
  BoxX := ABitmap.Width - BoxWidth - 1; // Jarak 15px dari tepi kanan
  BoxY := 0;                            // Jarak 15px dari tepi atas

  // Latar belakang kotak (semi transparan gelap)
  ABitmap.FillRect(BoxX, BoxY, BoxX + BoxWidth, BoxY + BoxHeight, BGRA(10, 15, 25, 200), dmDrawWithTransparency);

  // Tentukan warna garis tepi sesuai status
  if FBreachMode then
    BorderColor := BGRA(255, 0, 0, 150)
  else
    BorderColor := BGRA(0, 200, 220, 150);

  // Garis tepi (border) kotak menggunakan 4 garis (Atas, Bawah, Kiri, Kanan)
  ABitmap.DrawLineAntialias(BoxX, BoxY, BoxX + BoxWidth, BoxY, BorderColor, 1.0); // Atas
  ABitmap.DrawLineAntialias(BoxX, BoxY + BoxHeight, BoxX + BoxWidth, BoxY + BoxHeight, BorderColor, 1.0); // Bawah
  ABitmap.DrawLineAntialias(BoxX, BoxY, BoxX, BoxY + BoxHeight, BorderColor, 1.0); // Kiri
  ABitmap.DrawLineAntialias(BoxX + BoxWidth, BoxY, BoxX + BoxWidth, BoxY + BoxHeight, BorderColor, 1.0); // Kanan

  // Judul Kotak Info
  ABitmap.FontName := 'Consolas';
  ABitmap.FontHeight := 12;
  ABitmap.FontStyle := [fsBold];
  ABitmap.FontAntialias := True;

  if FBreachMode then
    ABitmap.TextOut(BoxX + 10, BoxY + 10, 'NODE LEGEND [WARN]', BGRA(255, 100, 100, 255))
  else
    ABitmap.TextOut(BoxX + 10, BoxY + 10, 'NODE LEGEND', BGRA(0, 255, 255, 255));

  // Data Basa Nitrogen
  BaseChars[0] := 'A'; BaseNames[0] := 'Adenine [A]';
  BaseChars[1] := 'T'; BaseNames[1] := 'Thymine [T]';
  BaseChars[2] := 'C'; BaseNames[2] := 'Cytosine [C]';
  BaseChars[3] := 'G'; BaseNames[3] := 'Guanine [G]';

  // Gambar setiap item basa nitrogen
  TextY := BoxY + 32;
  for i := 0 to 3 do
  begin
    BColor := GetBaseColor(BaseChars[i]);

    // 1. Gambar Glow (Bulatan besar transparan)
    ABitmap.FillEllipseAntialias(BoxX + 22, TextY + 7, 10.0, 10.0, BGRA(BColor.red, BColor.green, BColor.blue, 64));

    // 2. Gambar Core
    ABitmap.FillEllipseAntialias(BoxX + 22, TextY + 7, 7.0, 7.0, BColor);

    // 3. Karakter di dalam core
    ABitmap.FontHeight := 10;
    ABitmap.FontStyle := [fsBold];
    ABitmap.TextOut(BoxX + 18, TextY, BaseChars[i], BGRA(255, 255, 255, 255));

    // 4. Label Teks Nama
    ABitmap.FontHeight := 12;
    ABitmap.FontStyle := []; // Hapus format bold untuk label nama
    ABitmap.TextOut(BoxX + 42, TextY + 1, BaseNames[i], BGRA(220, 220, 220, 255));

    TextY := TextY + 20; // Spasi baris ke bawah
  end;
end;

procedure TSequenceRenderer.Render(ABitmap: TBGRABitmap);
var
  i, NodeCount, SeqLen: Integer;
  Radius, YSpacing, YOffset: Double;
  Angle, Strand1Angle, Strand2Angle: Double;
  BaseColor: TBGRAPixel;
  AlphaZ: Byte;
begin
  if not Assigned(ABitmap) then Exit;

  // Render latar belakang Sci-Fi Grid & Bio-Dust terlebih dahulu
  DrawSciFiBackground(ABitmap);

  if not Assigned(FGenomData) then Exit;

  SeqLen := Length(FGenomData.CurrentSequence);
  if SeqLen = 0 then Exit;

  NodeCount := Min(MAX_VISIBLE_NODES, SeqLen);
  Radius := 80.0;
  YSpacing := 18.0;

  // Kalkulasi koordinat 3D
  for i := 0 to NodeCount - 1 do
  begin
    Angle := (i * 0.3) + FRotationAngle;

    if FBreachMode and (Random(15) = 0) then
      Angle := Angle + ((Random * 0.8) - 0.4);

    Strand1Angle := Angle;
    Strand2Angle := Angle + Pi;

    YOffset := (i - (NodeCount * 0.5)) * YSpacing;

    FRungs[i].X1 := Radius * Cos(Strand1Angle);
    FRungs[i].Y1 := YOffset;
    FRungs[i].Z1 := Radius * Sin(Strand1Angle);

    FRungs[i].X2 := Radius * Cos(Strand2Angle);
    FRungs[i].Y2 := YOffset;
    FRungs[i].Z2 := Radius * Sin(Strand2Angle);

    FRungs[i].ZCenter := (FRungs[i].Z1 + FRungs[i].Z2) * 0.5;
    FRungs[i].BaseChar := FGenomData.CurrentSequence[i + 1];
  end;

  SortRungs;
  Project3DTo2D(ABitmap.Width, ABitmap.Height);

  // Eksekusi Rendering DNA
  for i := 0 to NodeCount - 1 do
  begin
    BaseColor := GetBaseColor(FRungs[i].BaseChar);

    if FRungs[i].ZCenter > 0 then
      AlphaZ := 100
    else
      AlphaZ := 255;

    BaseColor.alpha := AlphaZ;

    ABitmap.DrawLineAntialias(
      FRungs[i].ScreenX1, FRungs[i].ScreenY1,
      FRungs[i].ScreenX2, FRungs[i].ScreenY2,
      BGRA(255, 255, 255, AlphaZ div 3), 1.5
    );

    ABitmap.FillEllipseAntialias(
      FRungs[i].ScreenX1, FRungs[i].ScreenY1,
      12.0, 12.0, BGRA(BaseColor.red, BaseColor.green, BaseColor.blue, AlphaZ div 4)
    );

    ABitmap.FillEllipseAntialias(
      FRungs[i].ScreenX1, FRungs[i].ScreenY1,
      8.0, 8.0, BaseColor
    );

    ABitmap.FillEllipseAntialias(
      FRungs[i].ScreenX2, FRungs[i].ScreenY2,
      4.0, 4.0, BGRA(200, 200, 200, AlphaZ)
    );

    ABitmap.FontName := 'Consolas';
    ABitmap.FontHeight := 16;
    ABitmap.FontStyle := [fsBold];
    ABitmap.FontAntialias := True;

    ABitmap.TextOut(
      Round(FRungs[i].ScreenX1) - 6,
      Round(FRungs[i].ScreenY1) - 8,
      FRungs[i].BaseChar,
      BGRA(255, 255, 255, AlphaZ)
    );
  end;

  // --- LAYER PALING ATAS: Menggambar Panel Keterangan Bola DNA ---
  DrawNodeLegend(ABitmap);
end;

end.

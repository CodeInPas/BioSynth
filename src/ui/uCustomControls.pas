unit uCustomControls;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, Graphics, LMessages, LCLType, LCLIntf,
  BGRABitmap, BGRABitmapTypes;

type
  { TBioPanel:
    Panel kustom dengan latar belakang gelap, opsi grid vektor, dan border neon.
    Didesain khusus untuk menggantikan TPanel standar agar mendukung alpha blending
    dan bebas dari flicker OS. }
  TBioPanel = class(TCustomControl)
  private
    FBorderColor: TBGRAPixel;
    FBackColor: TBGRAPixel;
    FShowGrid: Boolean;
    FGridSpacing: Integer;

    { Mencegat event OS untuk menghapus background agar tidak berkedip (Flicker-Free) }
    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;
    procedure SetShowGrid(const Value: Boolean);

    { Setter kustom agar panel me-render ulang saat warnanya diubah dinamis (contoh: Alarm Sabotase) }
    procedure SetBorderColor(const Value: TBGRAPixel);
    procedure SetBackColor(const Value: TBGRAPixel);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property BorderColor: TBGRAPixel read FBorderColor write SetBorderColor;
    property BackColor: TBGRAPixel read FBackColor write SetBackColor;
    property ShowGrid: Boolean read FShowGrid write SetShowGrid;
    property GridSpacing: Integer read FGridSpacing write FGridSpacing;
  end;

  { TNeonProgressBar:
    Meteran progres beresolusi tinggi dengan efek pendaran cahaya (Glow).
    Sangat ringan karena dirender menggunakan matematika vektor murni. }
  TNeonProgressBar = class(TCustomControl)
  private
    FValue: Double;
    FMaxValue: Double;
    FGlowColor: TBGRAPixel;
    FTrackColor: TBGRAPixel;

    procedure WMEraseBkgnd(var Message: TLMEraseBkgnd); message LM_ERASEBKGND;
    procedure SetValue(const AValue: Double);
    procedure SetMaxValue(const AValue: Double);

    { Setter kustom agar meteran bisa berkedip berubah warna saat krisis }
    procedure SetGlowColor(const Value: TBGRAPixel);
    procedure SetTrackColor(const Value: TBGRAPixel);
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Value: Double read FValue write SetValue;
    property MaxValue: Double read FMaxValue write SetMaxValue;
    property GlowColor: TBGRAPixel read FGlowColor write SetGlowColor;
    property TrackColor: TBGRAPixel read FTrackColor write SetTrackColor;
  end;

implementation

{ Membantu komparasi piksel agar tidak render ulang berlebihan }
function IsSameColor(const C1, C2: TBGRAPixel): Boolean;
begin
  Result := (C1.red = C2.red) and (C1.green = C2.green) and
            (C1.blue = C2.blue) and (C1.alpha = C2.alpha);
end;

{ TBioPanel }

constructor TBioPanel.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque]; // Beritahu OS kita yang menggambar seluruh areanya

  // Warna default: Dark/Glassmorphism theme
  FBackColor := BGRA(15, 20, 25, 240);       // Hitam kebiruan semi-transparan
  FBorderColor := BGRA(0, 255, 255, 100);    // Cyan redup
  FShowGrid := True;
  FGridSpacing := 20;
end;

procedure TBioPanel.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin
  // Kembalikan nilai 1 (True) untuk memberi tahu OS bahwa kita sudah
  // menangani penghapusan background. Ini kunci utama Anti-Flicker!
  Message.Result := 1;
end;

procedure TBioPanel.SetShowGrid(const Value: Boolean);
begin
  if FShowGrid <> Value then
  begin
    FShowGrid := Value;
    Invalidate; // Paksa render ulang jika properti berubah
  end;
end;

procedure TBioPanel.SetBorderColor(const Value: TBGRAPixel);
begin
  if not IsSameColor(FBorderColor, Value) then
  begin
    FBorderColor := Value;
    Invalidate; // Penting untuk efek Alarm System Breach dari fMain
  end;
end;

procedure TBioPanel.SetBackColor(const Value: TBGRAPixel);
begin
  if not IsSameColor(FBackColor, Value) then
  begin
    FBackColor := Value;
    Invalidate;
  end;
end;

procedure TBioPanel.Paint;
var
  Bmp: TBGRABitmap;
  X, Y: Integer;
begin
  // 1. Buat kanvas memori seukuran kontrol
  Bmp := TBGRABitmap.Create(Width, Height);
  try
    // 2. Gambar latar belakang
    Bmp.FillRect(0, 0, Width, Height, FBackColor, dmDrawWithTransparency);

    // 3. Gambar Grid (Vector Blueprint Effect)
    if FShowGrid then
    begin
      X := 0;
      while X < Width do
      begin
        Bmp.DrawLineAntialias(X, 0, X, Height, BGRA(255, 255, 255, 10), 1.0);
        Inc(X, FGridSpacing);
      end;

      Y := 0;
      while Y < Height do
      begin
        Bmp.DrawLineAntialias(0, Y, Width, Y, BGRA(255, 255, 255, 10), 1.0);
        Inc(Y, FGridSpacing);
      end;
    end;

    // 4. Gambar Border menggunakan 4 garis menyambung (Pengganti DrawRectAntialias)
    Bmp.DrawLineAntialias(1, 1, Width - 1, 1, FBorderColor, 1.5); // Atas
    Bmp.DrawLineAntialias(Width - 1, 1, Width - 1, Height - 1, FBorderColor, 1.5); // Kanan
    Bmp.DrawLineAntialias(Width - 1, Height - 1, 1, Height - 1, FBorderColor, 1.5); // Bawah
    Bmp.DrawLineAntialias(1, Height - 1, 1, 1, FBorderColor, 1.5); // Kiri

    // 5. Salin hasil render memori ke kanvas layar (Double Buffering eksekusi)
    Bmp.Draw(Canvas, 0, 0, False);
  finally
    Bmp.Free;
  end;
end;


{ TNeonProgressBar }

constructor TNeonProgressBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];

  FValue := 50.0;
  FMaxValue := 100.0;

  // Warna default
  FGlowColor := BGRA(0, 255, 255, 255);      // Cyan menyala
  FTrackColor := BGRA(30, 35, 40, 255);      // Abu-abu gelap untuk jalur kosong

  Height := 15; // Tinggi standar agar ramping
end;

procedure TNeonProgressBar.WMEraseBkgnd(var Message: TLMEraseBkgnd);
begin
  Message.Result := 1; // Anti-Flicker
end;

procedure TNeonProgressBar.SetValue(const AValue: Double);
begin
  if FValue <> AValue then
  begin
    FValue := AValue;
    if FValue > FMaxValue then FValue := FMaxValue;
    if FValue < 0 then FValue := 0;
    Invalidate; // Render ulang jika nilai berubah
  end;
end;

procedure TNeonProgressBar.SetMaxValue(const AValue: Double);
begin
  if FMaxValue <> AValue then
  begin
    FMaxValue := AValue;
    if FMaxValue <= 0 then FMaxValue := 1;
    Invalidate;
  end;
end;

procedure TNeonProgressBar.SetGlowColor(const Value: TBGRAPixel);
begin
  if not IsSameColor(FGlowColor, Value) then
  begin
    FGlowColor := Value;
    Invalidate;
  end;
end;

procedure TNeonProgressBar.SetTrackColor(const Value: TBGRAPixel);
begin
  if not IsSameColor(FTrackColor, Value) then
  begin
    FTrackColor := Value;
    Invalidate;
  end;
end;

procedure TNeonProgressBar.Paint;
var
  Bmp: TBGRABitmap;
  FillWidth: Double;
  BarRect: TRect;
begin
  Bmp := TBGRABitmap.Create(Width, Height);
  try
    // Latar belakang transparan (mengikuti warna parent)
    Bmp.Fill(BGRAPixelTransparent);

    // Hitung lebar bar berdasarkan persentase
    if FMaxValue > 0 then
      FillWidth := (FValue / FMaxValue) * Width
    else
      FillWidth := 0;

    // Gambar Track/Jalur Kosong
    Bmp.FillRect(0, 0, Width, Height, FTrackColor, dmSet);

    if FillWidth > 0 then
    begin
      // Gambar isi progres
      BarRect := Rect(0, 0, Trunc(FillWidth), Height);
      Bmp.FillRect(BarRect, FGlowColor, dmDrawWithTransparency);

      // Efek Pendaran / Glow di ujung (Head) progres
      if FillWidth < Width then
      begin
        Bmp.DrawLineAntialias(FillWidth, 0, FillWidth, Height,
          BGRA(255, 255, 255, 200), 2.0); // Garis putih terang di ujung
        Bmp.DrawLineAntialias(FillWidth - 2, 0, FillWidth - 2, Height,
          BGRA(FGlowColor.red, FGlowColor.green, FGlowColor.blue, 150), 4.0);
      end;
    end;

    // Border bingkai tipis menggunakan 4 garis menyambung
    Bmp.DrawLineAntialias(1, 1, Width - 1, 1, BGRA(255, 255, 255, 30), 1.0); // Atas
    Bmp.DrawLineAntialias(Width - 1, 1, Width - 1, Height - 1, BGRA(255, 255, 255, 30), 1.0); // Kanan
    Bmp.DrawLineAntialias(Width - 1, Height - 1, 1, Height - 1, BGRA(255, 255, 255, 30), 1.0); // Bawah
    Bmp.DrawLineAntialias(1, Height - 1, 1, 1, BGRA(255, 255, 255, 30), 1.0); // Kiri

    Bmp.Draw(Canvas, 0, 0, False);
  finally
    Bmp.Free;
  end;
end;

end.s

unit fMain;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  TAGraph, TASeries, BGRABitmap, BGRABitmapTypes, uAudioManager  ,
  uGameEngine, uTerminalConsole, uCustomControls, uSequenceRenderer;

type
  { TfrmMain: Antarmuka utama simulasi BIO-SYNTH }
  TfrmMain = class(TForm)
    chtTelemetry: TChart;
    Panel1: TPanel;
    pbDNAVisualizer: TPaintBox;
    pnlControlsHost: TPanel;
    pnlLeft: TPanel;
    pnlRight: TPanel;
    pnlTerminalHost: TPanel;
    serContamination: TLineSeries;
    serHeat: TLineSeries;
    serStability: TLineSeries;
    tmrGameLoop: TTimer;

    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure pbDNAVisualizerPaint(Sender: TObject);
    procedure tmrGameLoopTimer(Sender: TObject);
  private
    FEngine: TGameEngine;
    FTerminal: TTerminalConsole;
    FRenderer: TSequenceRenderer;

    { Komponen Kustom yang di-instansiasi secara dinamis }
    FBackgroundPanel: TBioPanel;

    { Panel Panduan Pemula }
    FGuidancePanel: TBioPanel;
    FLblGuidanceTitle: TLabel;
    FLblGuidanceText: TLabel;

    { Progress Bars }
    FBarStability: TNeonProgressBar;
    FBarContam: TNeonProgressBar;
    FBarHeat: TNeonProgressBar;

    { Labels Caption & Nilai }
    FLblStability: TLabel;
    FLblContam: TLabel;
    FLblHeat: TLabel;

    FLastTick: QWord; // Untuk kalkulasi DeltaTime (FPS independen)

    procedure InitializeUI;
    procedure SetupBindings;
    procedure UpdateGuidanceText;

    { Event Callbacks dari Engine/Terminal }
    procedure OnTerminalCommand(Sender: TObject; const ACommand: string);
    procedure OnEngineLog(const AMsg: string; IsError: Boolean);
    procedure OnEngineStateChange(NewState: TGameState);
  public
  end;

var
  frmMain: TfrmMain;

implementation

uses
  fSettings; // Import form pengaturan

{$R *.lfm}

{ TfrmMain }

procedure TfrmMain.FormCreate(Sender: TObject);
var
  DBPath: string;
begin
  // --- MULAI PERBAIKAN AUDIO ---
  // Bangun instance global audio manager agar dikenali seluruh unit
  AudioManager := TAudioManager.Create;

  // Putar suara dengung ambien lab. Pastikan path file ini benar dan file .wav/.mp3 nya ada.
  if Assigned(AudioManager) then
    AudioManager.PlayBGM('assets/audio/reactor_ambient.mp3', 0.4);
  // --- SELESAI PERBAIKAN AUDIO ---
  // 1. Tentukan path database (di folder data samping executable)
  DBPath := ExtractFilePath(ParamStr(0)) + 'data\biosynth.db';

  // 2. Inisiasi Engine Inti
  FEngine := TGameEngine.Create(DBPath);

  // 3. Inisiasi Mesin Grafis (Meneruskan data genom)
  FRenderer := TSequenceRenderer.Create(FEngine.GenomData);

  // 4. Bangun Antarmuka Kustom
  InitializeUI;

  // 5. Kaitkan Event (Data Binding)
  SetupBindings;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FRenderer.Free;
  FEngine.Free;
end;

procedure TfrmMain.InitializeUI;
begin
  { --- Setup Terminal CLI --- }
  FTerminal := TTerminalConsole.Create(Self);
  FTerminal.Parent := pnlTerminalHost;
  FTerminal.Align := alClient;


  { --- Setup BioPanel (Glassmorphism & Neon UI) --- }
  FBackgroundPanel := TBioPanel.Create(Self);
  FBackgroundPanel.Parent := pnlControlsHost;
  FBackgroundPanel.Align := alClient;
  FBackgroundPanel.BorderColor := BGRA(0, 255, 255, 100);

  { --- Setup Panel Panduan Pemula (Posisi Vertikal Kiri) --- }
  FGuidancePanel := TBioPanel.Create(Self);
  FGuidancePanel.Parent := pnlRight;
  FGuidancePanel.SetBounds(3, round(pnlRight.height/2)-350, 313  , 130);
  FGuidancePanel.BorderColor := BGRA(0, 255, 255, 150);

  FLblGuidanceTitle := TLabel.Create(Self);
  FLblGuidanceTitle.Parent := FGuidancePanel;
  FLblGuidanceTitle.AutoSize := False;
  // Lebar label diset dinamis: Lebar Panel dikurangi margin kiri (10) dan kanan (10) = -20
  FLblGuidanceTitle.SetBounds(10, 10, FGuidancePanel.Width - 20, 30);
  FLblGuidanceTitle.Anchors := [akLeft, akTop, akRight]; // Teks otomatis ikut meregang ke kanan
  FLblGuidanceTitle.Font.Color := clAqua;
  FLblGuidanceTitle.Font.Name := 'Consolas';
  FLblGuidanceTitle.Font.Size := 10;
  FLblGuidanceTitle.Font.Style := [fsBold];
  FLblGuidanceTitle.WordWrap := True;
  FLblGuidanceTitle.Caption := '>>> PANDUAN BIO-ARCHITECT <<<';

  FLblGuidanceText := TLabel.Create(Self);
  FLblGuidanceText.Parent := FGuidancePanel;
  FLblGuidanceText.AutoSize := False;
  FLblGuidanceText.Font.Name := 'Consolas';
  // Lebar dan Tinggi diset dinamis mengikuti Panel
  FLblGuidanceText.SetBounds(10, 45, FGuidancePanel.Width - 20, FGuidancePanel.Height - 55);
  FLblGuidanceText.Anchors := [akLeft, akTop, akRight, akBottom]; // Teks meregang mengikuti kotak panel
  FLblGuidanceText.Font.Color := clWhite;
  FLblGuidanceText.Font.Size := 10;
  FLblGuidanceText.WordWrap := True;
  FLblGuidanceText.Caption := 'Ketik "isolate" di terminal untuk memuat patogen dan memulai simulasi.';

  { --- 1. Stability Bar & Label --- }
  FLblStability := TLabel.Create(Self);
  FLblStability.Parent := FBackgroundPanel;
  FLblStability.SetBounds(20, 15, 200, 14);
  FLblStability.Font.Color := clLime;
  FLblStability.Font.Size := 8;
  FLblStability.Font.Style := [fsBold];
  FLblStability.Caption := 'STABILITY: 100.0%';

  FBarStability := TNeonProgressBar.Create(Self);
  FBarStability.Parent := FBackgroundPanel;
  FBarStability.SetBounds(20, 32, 200, 12);
  FBarStability.GlowColor := BGRA(0, 255, 255, 255);

  { --- 2. Contamination Bar & Label --- }
  FLblContam := TLabel.Create(Self);
  FLblContam.Parent := FBackgroundPanel;
  FLblContam.SetBounds(20, 52, 200, 14);
  FLblContam.Font.Color := clRed;
  FLblContam.Font.Size := 8;
  FLblContam.Font.Style := [fsBold];
  FLblContam.Caption := 'CONTAMINATION: 0.0%';

  FBarContam := TNeonProgressBar.Create(Self);
  FBarContam.Parent := FBackgroundPanel;
  FBarContam.SetBounds(20, 69, 200, 12);
  FBarContam.GlowColor := BGRA(255, 50, 50, 255);

  { --- 3. Heat / CPU Bar & Label --- }
  FLblHeat := TLabel.Create(Self);
  FLblHeat.Parent := FBackgroundPanel;
  FLblHeat.SetBounds(20, 89, 200, 14);
  FLblHeat.Font.Color := clYellow;
  FLblHeat.Font.Size := 8;
  FLblHeat.Font.Style := [fsBold];
  FLblHeat.Caption := 'REACTOR HEAT: 0.0%';

  FBarHeat := TNeonProgressBar.Create(Self);
  FBarHeat.Parent := FBackgroundPanel;
  FBarHeat.SetBounds(20, 106, 200, 12);
  FBarHeat.GlowColor := BGRA(255, 200, 0, 255);
end;

procedure TfrmMain.SetupBindings;
begin
  FTerminal.OnCommand := @OnTerminalCommand;
  FEngine.OnLogMessage := @OnEngineLog;
  FEngine.OnStateChange := @OnEngineStateChange;
  FEngine.TelemetryManager.AttachVitalSeries(serStability, serContamination, serHeat);
end;

procedure TfrmMain.FormShow(Sender: TObject);
begin
  FEngine.InitializeSystem('GuestArchitect');
  FLastTick := GetTickCount64;
  tmrGameLoop.Enabled := True;

  UpdateGuidanceText;
end;

procedure TfrmMain.UpdateGuidanceText;
begin
  if not Assigned(FEngine) then Exit;

  // Setel warna normal terlebih dahulu
  FLblGuidanceTitle.Font.Color := clAqua;
  FLblGuidanceText.Font.Color := clWhite;

  case FEngine.State of
    gsIdle, gsBooting:
      FLblGuidanceText.Caption := 'TIPS:' + sLineBreak + 'Ketik "isolate" di terminal untuk memuat patogen dan memulai simulasi.';
    gsPlaying:
      FLblGuidanceText.Caption := 'TIPS:' + sLineBreak + 'Ketik "mutate <pattern> <replace>" perbaiki DNA, atau "ask <tanya>" untuk AI.';
    gsVictory:
      FLblGuidanceText.Caption := 'TIPS:' + sLineBreak + 'Isolasi sukses! Ketik "shop" untuk belanja upgrade atau "isolate" misi baru.';
    gsGameOver:
      FLblGuidanceText.Caption := 'TIPS:' + sLineBreak + 'Simulasi gagal. Ketik "isolate" untuk mencoba ulang dan perbaiki strategi.';
    gsBreach: // --- PENANGANAN STATUS SYSTEM BREACH ---
      begin
        FLblGuidanceTitle.Font.Color := clRed;
        FLblGuidanceText.Font.Color := clRed;
        FLblGuidanceText.Caption := 'WARNING:' + sLineBreak + 'SISTEM DISABOTASE! Ketik perintah "override <hash>" dari log AI segera untuk menahan serangan!';
      end;
  end;
end;

procedure TfrmMain.tmrGameLoopTimer(Sender: TObject);
var
  CurrentTick: QWord;
  DeltaTime: Double;
  IsBlink: Boolean;
begin
  if not Assigned(FEngine) then Exit;

  CurrentTick := GetTickCount64;
  DeltaTime := (CurrentTick - FLastTick) / 1000.0;
  FLastTick := CurrentTick;

  FEngine.Update(DeltaTime);

  if Assigned(FRenderer) then
    FRenderer.Update(DeltaTime);

  pbDNAVisualizer.Invalidate;

  // --- VISUAL GLITCH / ALARM SYSTEM BREACH ---
  if FEngine.State = gsBreach then
  begin
    // Kedipkan panel kaca menjadi merah setiap 300ms (0.3 detik)
    IsBlink := (CurrentTick div 300) mod 2 = 0;
    if IsBlink then
    begin
      FBackgroundPanel.BorderColor := BGRA(255, 0, 0, 200);
      FGuidancePanel.BorderColor := BGRA(255, 0, 0, 200);
    end
    else
    begin
      FBackgroundPanel.BorderColor := BGRA(100, 0, 0, 150);
      FGuidancePanel.BorderColor := BGRA(100, 0, 0, 150);
    end;
  end
  else
  begin
    // Kembalikan ke warna neon biru normal saat tidak sabotase
    FBackgroundPanel.BorderColor := BGRA(0, 255, 255, 100);
    FGuidancePanel.BorderColor := BGRA(0, 255, 255, 150);
  end;
  // -------------------------------------------

  if Assigned(FEngine.GenomData) then
  begin
    FBarStability.Value := FEngine.GenomData.Stability;
    FBarContam.Value := FEngine.GenomData.Contamination;
    FBarHeat.Value := FEngine.GenomData.Heat;

    FLblStability.Caption := Format('STABILITY: %.1f%%', [FEngine.GenomData.Stability]);
    FLblContam.Caption := Format('CONTAMINATION: %.1f%%', [FEngine.GenomData.Contamination]);
    FLblHeat.Caption := Format('REACTOR HEAT: %.1f%%', [FEngine.GenomData.Heat]);
  end;
end;

procedure TfrmMain.pbDNAVisualizerPaint(Sender: TObject);
var
  BufferBmp: TBGRABitmap;
begin
  if not Assigned(FRenderer) then Exit;

  BufferBmp := TBGRABitmap.Create(pbDNAVisualizer.Width, pbDNAVisualizer.Height);
  try
    FRenderer.Render(BufferBmp);
    BufferBmp.Draw(pbDNAVisualizer.Canvas, 0, 0, False);
  finally
    BufferBmp.Free;
  end;
end;

procedure TfrmMain.OnTerminalCommand(Sender: TObject; const ACommand: string);
var
  Cmd: string;
begin
  Cmd := LowerCase(Trim(ACommand));

  if Cmd = 'clear' then
    FTerminal.ClearScreen
  else if (Cmd = 'settings') or (Cmd = 'config') then
  begin
    FTerminal.WriteSystem('Opening AI Core Configuration...');
    with TfrmSettings.Create(Application) do
    begin
      try
        ShowModal;
      finally
        Free;
      end;
    end;

    if Assigned(FEngine) then
      FEngine.ProcessCommand('reload_ai_config');

    FTerminal.WriteSystem('Configuration closed.');
  end
  else
    FEngine.ProcessCommand(ACommand);

  UpdateGuidanceText;
end;

procedure TfrmMain.OnEngineLog(const AMsg: string; IsError: Boolean);
begin
  if Pos('[AI]', AMsg) > 0 then
    FTerminal.WriteLog(AMsg)
  else if IsError then
    FTerminal.WriteError(AMsg)
  else
    FTerminal.WriteLog(AMsg);
end;

procedure TfrmMain.OnEngineStateChange(NewState: TGameState);
begin
  UpdateGuidanceText;
end;

end.

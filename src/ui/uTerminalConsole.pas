unit uTerminalConsole;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Controls, StdCtrls, Graphics, LCLType, LMessages;

type
  { Event delegate untuk menangani input dari pengguna }
  TOnTerminalInput = procedure(Sender: TObject; const ACommand: string) of object;

  { TTerminalConsole:
    Komponen komposit yang menggabungkan TMemo (untuk log display) dan
    TEdit (untuk input perintah). Didesain agar independen dari logika game,
    sehingga hanya bertugas menangani I/O teks murni. }
  TTerminalConsole = class(TCustomControl)
  private
    FDisplay: TMemo;
    FInput: TEdit;
    FHistory: TStringList;
    FHistoryIndex: Integer;
    FOnCommand: TOnTerminalInput;
    FBreachMode: Boolean;

    procedure InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure InputKeyPress(Sender: TObject; var Key: char);
    procedure TerminalResize(Sender: TObject);
    procedure FocusInput(Sender: TObject);
    procedure SetBreachMode(const Value: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;

    { Metode untuk menulis output ke layar terminal }
    procedure WriteLog(const AMsg: string);
    procedure WriteError(const AMsg: string);
    procedure WriteSystem(const AMsg: string);

    { Membersihkan layar terminal }
    procedure ClearScreen;

    { Properti untuk mengaktifkan efek sabotase ketikan (System Breach) }
    property BreachMode: Boolean read FBreachMode write SetBreachMode;

    { Event yang akan dipicu saat pengguna menekan ENTER }
    property OnCommand: TOnTerminalInput read FOnCommand write FOnCommand;
  end;

implementation

{ TTerminalConsole }

constructor TTerminalConsole.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  // Konfigurasi dasar kontainer
  Width := 400;
  Height := 250;
  Color := RGBToColor(10, 15, 20); // Warna latar sangat gelap (Void Black)
  OnResize := @TerminalResize;
  OnClick := @FocusInput; // Klik di area kosong akan otomatis memfokuskan kursor ke input

  // Inisialisasi riwayat perintah (Command History)
  FHistory := TStringList.Create;
  FHistoryIndex := -1;
  FBreachMode := False;
  self.Color:=$003A3A3A;
  // 1. Inisialisasi Display Log (TMemo)
  FDisplay := TMemo.Create(Self);
  FDisplay.Parent := Self;
  FDisplay.BorderSpacing.Around:=10;
  FDisplay.ReadOnly := True;
  FDisplay.ScrollBars := ssAutoVertical;
  FDisplay.WordWrap := True;
  FDisplay.Color := $00433932;//Self.Color;
  FDisplay.Font.Name := 'Lucida Console'; // Gunakan font Monospace bawaan yang aman
  FDisplay.Font.Size := 10;
 // FDisplay.Color:=$00382125;
  FDisplay.ScrollBars:=ssNone;
  FDisplay.Font.Color := clLime;// RGBToColor(0, 200, 200); // Cyan/Ice Blue
  FDisplay.BorderStyle := bsNone;
  FDisplay.TabStop := False; // Mencegah display menerima fokus dari tombol Tab
  FDisplay.OnClick := @FocusInput;

  // 2. Inisialisasi Input Box (TEdit)
  FInput := TEdit.Create(Self);
  FInput.Parent := Self;
  FInput.Color := $00413623 ;// Self.Color;
  FInput.Font.Name := 'Lucida Console';
  FInput.Font.Size := 10;
  FInput.Font.Color := RGBToColor(255, 255, 255); // Teks input putih agar kontras
  FInput.Font.Style := [fsBold];
  FInput.BorderStyle := bsNone;
  FInput.OnKeyDown := @InputKeyDown;
  FInput.OnKeyPress := @InputKeyPress; // Handler baru untuk mutasi karakter

end;

destructor TTerminalConsole.Destroy;
begin
  FHistory.Free;
  inherited Destroy;
end;

procedure TTerminalConsole.TerminalResize(Sender: TObject);
const
  INPUT_HEIGHT = 25;
begin
  // Mencegah error saat pembuatan form awal
  if not Assigned(FDisplay) or not Assigned(FInput) then Exit;

  // TEdit (Input) selalu berada di bagian paling bawah
  FInput.Left := 5;
  FInput.Width := Width - 10;
  FInput.Height := INPUT_HEIGHT;
  FInput.Top := Height - INPUT_HEIGHT - 5;

  // TMemo (Display) mengisi sisa ruang di atasnya
  FDisplay.Left := 5;
  FDisplay.Top := 5;
  FDisplay.Width := Width - 10;
  FDisplay.Height := FInput.Top - 10;
end;

procedure TTerminalConsole.FocusInput(Sender: TObject);
begin
  if FInput.CanFocus then
    FInput.SetFocus;
end;

procedure TTerminalConsole.SetBreachMode(const Value: Boolean);
begin
  if FBreachMode = Value then Exit;
  FBreachMode := Value;

  // Ubah tema warna terminal secara dinamis untuk mengindikasikan status krisis
  if FBreachMode then
  begin
    FInput.Font.Color := clRed;
    FDisplay.Font.Color := RGBToColor(255, 100, 100); // Merah pudar untuk log
  end
  else
  begin
    FInput.Font.Color := RGBToColor(255, 255, 255);
    FDisplay.Font.Color := RGBToColor(0, 200, 200);
  end;
end;

procedure TTerminalConsole.InputKeyPress(Sender: TObject; var Key: char);
const
  GARBAGE_CHARS = '!@#$%^&*()_+{}|:"<>?[]\;,./~`X01';
begin
  // FITUR PAMUNGKAS: Sabotase Input Karakter
  if FBreachMode then
  begin
    // Terdapat peluang 25% setiap tombol yang diketik berubah menjadi karakter sampah
    if Random(4) = 0 then
      Key := GARBAGE_CHARS[Random(Length(GARBAGE_CHARS)) + 1];
  end;
end;

procedure TTerminalConsole.InputKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Cmd: string;
begin
  case Key of
    VK_RETURN:
      begin
        Cmd := Trim(FInput.Text);
        if Cmd = '' then Exit;

        // Cetak perintah yang diketik pengguna ke layar
        WriteLog('> ' + Cmd);

        // Simpan ke riwayat perintah
        FHistory.Add(Cmd);
        FHistoryIndex := FHistory.Count;

        // Bersihkan kotak input
        FInput.Clear;

        // Trigger event ke TGameEngine atau fMain
        if Assigned(FOnCommand) then
          FOnCommand(Self, Cmd);

        Key := 0; // Cegah bunyi 'beep' default OS
      end;

    VK_UP:
      begin
        // Navigasi mundur di riwayat perintah
        if FHistory.Count > 0 then
        begin
          Dec(FHistoryIndex);
          if FHistoryIndex < 0 then FHistoryIndex := 0;
          FInput.Text := FHistory[FHistoryIndex];
          FInput.SelStart := Length(FInput.Text); // Taruh kursor di akhir teks
        end;
        Key := 0;
      end;

    VK_DOWN:
      begin
        // Navigasi maju di riwayat perintah
        if FHistory.Count > 0 then
        begin
          Inc(FHistoryIndex);
          if FHistoryIndex >= FHistory.Count then
          begin
            FHistoryIndex := FHistory.Count;
            FInput.Clear;
          end
          else
          begin
            FInput.Text := FHistory[FHistoryIndex];
            FInput.SelStart := Length(FInput.Text);
          end;
        end;
        Key := 0;
      end;

    VK_BACK:
      begin
        // FITUR PAMUNGKAS: Sabotase Tombol Backspace
        if FBreachMode then
        begin
          // Peluang 50% tombol Backspace diabaikan (macet) saat sistem diretas
          if Random(2) = 0 then
            Key := 0;
        end;
      end;
  end;
end;

procedure TTerminalConsole.WriteLog(const AMsg: string);
var
  LinesArray: TStringArray;
  LineStr: string;
begin
  LinesArray := AMsg.Split([#13#10, #10, #13]);

  for LineStr in LinesArray do
  begin
    FDisplay.Lines.Add(LineStr);
  end;

  FDisplay.SelStart := Length(FDisplay.Text);
  FDisplay.SelLength := 0;
end;

procedure TTerminalConsole.WriteError(const AMsg: string);
begin
  WriteLog('[FATAL] ' + AMsg);
end;

procedure TTerminalConsole.WriteSystem(const AMsg: string);
begin
  WriteLog('[SYS] ' + AMsg);
end;

procedure TTerminalConsole.ClearScreen;
begin
  FDisplay.Clear;
  WriteSystem('BIO-SYNTH OS v1.0.4. Terminal Cleared.');
end;

end.

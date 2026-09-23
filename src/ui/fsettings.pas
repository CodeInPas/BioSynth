unit fSettings;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls, IniFiles;

type
  { TfrmSettings: Form untuk mengonfigurasi API Asisten AI }
  TfrmSettings = class(TForm)
    btnSave: TButton;
    btnCancel: TButton;
    cbProvider: TComboBox;
    lblTitle: TLabel;
    lblProvider: TLabel;
    lblAPIKey: TLabel;
    txtAPIKey: TEdit;
    lblEndpoint: TLabel;
    txtEndpoint: TEdit;
    pnlMain: TPanel;

    procedure btnCancelClick(Sender: TObject);
    procedure btnSaveClick(Sender: TObject);
    procedure cbProviderChange(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    procedure LoadConfig;
    procedure SaveConfig;
  public
  end;

var
  frmSettings: TfrmSettings;

implementation

{$R *.lfm}

{ TfrmSettings }

procedure TfrmSettings.FormShow(Sender: TObject);
begin
  LoadConfig;
end;

procedure TfrmSettings.LoadConfig;
var
  Ini: TIniFile;
  ConfigPath: string;
begin
  // Simpan konfigurasi di folder data yang sama dengan database
  ConfigPath := ExtractFilePath(ParamStr(0)) + 'data\config.ini';
  Ini := TIniFile.Create(ConfigPath);
  try
    cbProvider.ItemIndex := Ini.ReadInteger('AI_CONFIG', 'ProviderIndex', 0);
    txtAPIKey.Text := Ini.ReadString('AI_CONFIG', 'APIKey', '');
    txtEndpoint.Text := Ini.ReadString('AI_CONFIG', 'Endpoint', '');

    // Trigger event change untuk menyesuaikan state antarmuka
    cbProviderChange(Self);
  finally
    Ini.Free;
  end;
end;

procedure TfrmSettings.SaveConfig;
var
  Ini: TIniFile;
  ConfigPath: string;
begin
  ConfigPath := ExtractFilePath(ParamStr(0)) + 'data\config.ini';
  Ini := TIniFile.Create(ConfigPath);
  try
    Ini.WriteInteger('AI_CONFIG', 'ProviderIndex', cbProvider.ItemIndex);
    Ini.WriteString('AI_CONFIG', 'ProviderName', cbProvider.Text);
    Ini.WriteString('AI_CONFIG', 'APIKey', txtAPIKey.Text);
    Ini.WriteString('AI_CONFIG', 'Endpoint', txtEndpoint.Text);
  finally
    Ini.Free;
  end;
end;

procedure TfrmSettings.cbProviderChange(Sender: TObject);
begin
  // Logika otomatis untuk mengisi URL Endpoint bawaan berdasarkan provider
  case cbProvider.ItemIndex of
    0: // Mode Offline / Heuristics
      begin
        txtAPIKey.Enabled := False;
        txtEndpoint.Enabled := False;
        txtEndpoint.Text := 'LOCAL_HEURISTICS';
      end;
    1: // OpenAI (ChatGPT)
      begin
        txtAPIKey.Enabled := True;
        txtEndpoint.Enabled := True;
        if (txtEndpoint.Text = '') or (txtEndpoint.Text = 'LOCAL_HEURISTICS') then
          txtEndpoint.Text := 'https://api.openai.com/v1/chat/completions';
      end;
    2: // Ollama (Local LLM)
      begin
        txtAPIKey.Enabled := False; // Ollama murni lokal, tidak butuh API Key
        txtEndpoint.Enabled := True;
        if (txtEndpoint.Text = '') or (txtEndpoint.Text = 'LOCAL_HEURISTICS') then
          txtEndpoint.Text := 'http://localhost:11434/api/generate';
      end;
    3: // DeepSeek
      begin
        txtAPIKey.Enabled := True;
        txtEndpoint.Enabled := True;
        if (txtEndpoint.Text = '') or (txtEndpoint.Text = 'LOCAL_HEURISTICS') then
          txtEndpoint.Text := 'https://api.deepseek.com/chat/completions';
      end;
    4: // Gemini
      begin
        txtAPIKey.Enabled := True;
        txtEndpoint.Enabled := True;
        if (txtEndpoint.Text = '') or (txtEndpoint.Text = 'LOCAL_HEURISTICS') then
          txtEndpoint.Text := 'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent';
      end;
  end;
end;

procedure TfrmSettings.btnSaveClick(Sender: TObject);
begin
  SaveConfig;
  ModalResult := mrOk;
  Close;
end;

procedure TfrmSettings.btnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
  Close;
end;

end.

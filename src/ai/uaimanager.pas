unit uAIManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, fpjson, jsonparser, opensslsockets, IniFiles;

type
  { Event Delegate untuk mengirim balasan kembali ke main thread (UI) }
  TAIResponseEvent = procedure(const AMsg: string) of object;

  { TAIThread: Worker Thread asinkron agar UI/Game Loop tidak Freeze saat loading }
  TAIThread = class(TThread)
  private
    FQuestion: string;
    FContextStr: string;
    FProviderIndex: Integer;
    FAPIKey: string;
    FEndpoint: string;
    FResultText: string;
    FOnResponse: TAIResponseEvent;

    procedure SyncResponse;
  protected
    procedure Execute; override;
  public
    constructor Create(const AQuestion, AContext: string; AProviderIdx: Integer;
                       const AKey, AEndpoint: string; AOnResponse: TAIResponseEvent);
  end;

  { TAIManager: Manajer utama yang membungkus pemanggilan AI }
  TAIManager = class
  private
    FProviderIndex: Integer;
    FAPIKey: string;
    FEndpoint: string;
    FOnResponse: TAIResponseEvent;
  public
    constructor Create;
    procedure LoadConfig;

    { Menerima pertanyaan dan vitalitas game saat ini sebagai konteks (Prompt Engineering) }
    procedure Ask(const AQuestion: string; AIsPlaying: Boolean;
                  AStability, AHeat, AContam: Double);
    property OnResponse: TAIResponseEvent read FOnResponse write FOnResponse;
  end;

implementation

{ TAIManager }

constructor TAIManager.Create;
begin
  inherited Create;
  LoadConfig;
end;

procedure TAIManager.LoadConfig;
var
  Ini: TIniFile;
  ConfigPath: string;
begin
  ConfigPath := ExtractFilePath(ParamStr(0)) + 'data\config.ini';
  if FileExists(ConfigPath) then
  begin
    Ini := TIniFile.Create(ConfigPath);
    try
      FProviderIndex := Ini.ReadInteger('AI_CONFIG', 'ProviderIndex', 0);
      FAPIKey := Ini.ReadString('AI_CONFIG', 'APIKey', '');
      FEndpoint := Ini.ReadString('AI_CONFIG', 'Endpoint', '');
    finally
      Ini.Free;
    end;
  end
  else
  begin
    FProviderIndex := 0; // Default: Offline Mode
    FAPIKey := '';
    FEndpoint := '';
  end;
end;

procedure TAIManager.Ask(const AQuestion: string; AIsPlaying: Boolean; AStability, AHeat, AContam: Double);
var
  ContextData: string;
begin
  if not Assigned(FOnResponse) then Exit;

  // Bangun Konteks (Prompt) berdasarkan kondisi permainan
  if AIsPlaying then
    ContextData := Format('Active Synthesis. Vitals -> Stability: %.1f%%, Heat: %.1f%%, Contamination: %.1f%%.',
                          [AStability, AHeat, AContam])
  else
    ContextData := 'No active sample. Idle mode.';

  // Jalankan request di Thread terpisah agar game berjalan mulus di 60 FPS
  TAIThread.Create(AQuestion, ContextData, FProviderIndex, FAPIKey, FEndpoint, FOnResponse);
end;


{ TAIThread }

constructor TAIThread.Create(const AQuestion, AContext: string; AProviderIdx: Integer;
                             const AKey, AEndpoint: string; AOnResponse: TAIResponseEvent);
begin
  inherited Create(False); // False = Langsung dieksekusi saat di-create
  FreeOnTerminate := True; // Thread akan otomatis menghancurkan dirinya setelah selesai

  FQuestion := AQuestion;
  FContextStr := AContext;
  FProviderIndex := AProviderIdx;
  FAPIKey := AKey;
  FEndpoint := AEndpoint;
  FOnResponse := AOnResponse;
end;

procedure TAIThread.SyncResponse;
begin
  // Fungsi ini dieksekusi secara aman di dalam Main Thread (UI)
  if Assigned(FOnResponse) then
    FOnResponse(FResultText);
end;

procedure TAIThread.Execute;
var
  Client: TFPHTTPClient;
  ReqStream, RespStream: TStringStream;
  JSONResp: TJSONData;
  ReqStr, QLower, ModelName, SafeQuestion, SafeContext: string;
begin
  { --- 1. MODE OFFLINE / SIMULASI (Provider 0) --- }
  if FProviderIndex = 0 then
  begin
    Sleep(1200); // Simulasi delay jaringan (1.2 detik)

    QLower := LowerCase(FQuestion);

    // Heuristic AI sederhana berdasarkan kata kunci (Telah diperbarui untuk System Breach)
    if (Pos('sabotase', QLower) > 0) or (Pos('breach', QLower) > 0) or (Pos('override', QLower) > 0) then
      FResultText := 'CRITICAL: Port system breached. Find the 4-digit red hash in the system log above and type "override <hash>" to block the attack immediately!'
    else if Pos('heat', QLower) > 0 then
      FResultText := 'Heat level affects mutation volatility. Cease active synthesis momentarily to trigger automatic cryo-cooling.'
    else if (Pos('contam', QLower) > 0) or (Pos('clean', QLower) > 0) then
      FResultText := 'Contamination rises per second. Ensure your regex patterns are efficient to minimize synthesis time.'
    else if Pos('stability', QLower) > 0 then
      FResultText := 'Stability is critical. Accurate regex matches restore stability, while incorrect sequences will rapidly degrade the sample.'
    else if Pos('hello', QLower) > 0 then
      FResultText := 'Greetings, Bio-Architect. I am the BIO-SYNTH mainframe. Awaiting parameters.'
    else
      FResultText := 'OFFLINE HEURISTIC: ' + FContextStr + ' Please optimize parameters or consult laboratory manual.';

    Synchronize(@SyncResponse);
    Exit;
  end;

  { --- 2. MODE ONLINE (HTTP REST API) --- }
  Client := TFPHTTPClient.Create(nil);
  ReqStream := TStringStream.Create('');
  RespStream := TStringStream.Create('');
  try
    try
      Client.IOTimeout := 15000; // Timeout 15 detik untuk antisipasi LLM lambat
      Client.AddHeader('Content-Type', 'application/json');

      // Otorisasi API Key berdasarkan platform
      if FAPIKey <> '' then
      begin
        if FProviderIndex = 4 then // Gemini API membutuhkan header x-goog-api-key
          Client.AddHeader('x-goog-api-key', FAPIKey)
        else // OpenAI & DeepSeek menggunakan Authorization Bearer standar
          Client.AddHeader('Authorization', 'Bearer ' + FAPIKey);
      end;

      // Membersihkan karakter kutip ganda dari input agar JSON tidak rusak
      SafeQuestion := StringReplace(FQuestion, '"', '\"', [rfReplaceAll]);
      SafeContext := StringReplace(FContextStr, '"', '\"', [rfReplaceAll]);

      if FProviderIndex = 4 then
      begin
        // Format Payload untuk GEMINI
        ReqStr :=
          '{' +
          '  "systemInstruction": {"parts": [{"text": "You are Bio-Synth OS, a gritty sci-fi medical lab AI. Keep answers strictly under 2 sentences. Do not use markdown."}]},' +
          '  "contents": [{"parts": [{"text": "Context: ' + SafeContext + ' Question: ' + SafeQuestion + '"}]}]' +
          '}';
      end
      else if FProviderIndex = 2 then
      begin
        // Format Payload untuk OLLAMA (Local LLM)
        ReqStr :=
          '{' +
          '  "model": "llama3", ' +
          '  "prompt": "You are Bio-Synth OS, a gritty sci-fi medical lab AI. Keep answers under 2 sentences. Context: ' + SafeContext + ' Question: ' + SafeQuestion + '", ' +
          '  "stream": false' +
          '}';
      end
      else
      begin
        // Format Payload untuk OPENAI & DEEPSEEK
        if FProviderIndex = 3 then ModelName := 'deepseek-chat'
        else ModelName := 'gpt-3.5-turbo';

        ReqStr :=
          '{' +
          '  "model": "' + ModelName + '", ' +
          '  "temperature": 0.7, ' +
          '  "messages": [' +
          '    {"role": "system", "content": "You are Bio-Synth OS, a gritty sci-fi medical lab AI. Keep answers strictly under 2 sentences. Do not use markdown."}, ' +
          '    {"role": "user", "content": "Context: ' + SafeContext + ' Question: ' + SafeQuestion + '"}' +
          '  ]' +
          '}';
      end;

      ReqStream.WriteString(ReqStr);
      ReqStream.Position := 0;

      Client.RequestBody := ReqStream;
      Client.Post(FEndpoint, RespStream);

      // Parsing Respons JSON
      JSONResp := GetJSON(RespStream.DataString);
      if Assigned(JSONResp) then
      begin
        try
          if FProviderIndex = 4 then
            FResultText := JSONResp.FindPath('candidates[0].content.parts[0].text').AsString // Parsing Gemini
          else if FProviderIndex = 2 then
            FResultText := JSONResp.FindPath('response').AsString // Parsing Ollama
          else
            FResultText := JSONResp.FindPath('choices[0].message.content').AsString; // Parsing OpenAI/DeepSeek
        finally
          JSONResp.Free;
        end;
      end;

    except
      on E: Exception do
        FResultText := 'SYSTEM FAULT: AI Core Connection Failed. (' + E.Message + ')';
    end;
  finally
    Client.Free;
    ReqStream.Free;
    RespStream.Free;
  end;

  // Sinkronisasi hasil kembali ke UI Utama
  Synchronize(@SyncResponse);
end;

end.

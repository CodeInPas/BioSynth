unit uGameEngine;

{$mode objfpc}{$H+}
{$modeSwitch advancedrecords}

interface

uses
  Classes, SysUtils, StrUtils,
  uDatabaseManager, uGenomData, uTelemetryManager, uAIManager, uMacroManager;

type
  { Status utama dari Game Engine (Ditambahkan gsBreach untuk mode Sabotase) }
  TGameState = (gsBooting, gsIdle, gsPlaying, gsBreach, gsGameOver, gsVictory);

  { Event Delegates untuk komunikasi ke UI (fMain) }
  TLogMessageEvent = procedure(const AMsg: string; IsError: Boolean = False) of object;
  TGameStateEvent = procedure(NewState: TGameState) of object;

  { TGameEngine: Arsitektur inti yang memediasi semua sistem }
  TGameEngine = class
  private
    FState: TGameState;
    FDBManager: TDatabaseManager;
    FGenomData: TGenomData;
    FTelemetryManager: TTelemetryManager;
    FAIManager: TAIManager; // Modul AI Assistant
    FMacroManager: TMacroManager; // Modul Makro Otomatisasi

    FPlayerProfile: TPlayerProfile;
    FCurrentPathogen: TPathogenData;

    { Variabel untuk fitur System Breach (Sabotase) }
    FBreachTimer: Double;
    FOverrideHash: string;

    FOnLogMessage: TLogMessageEvent;
    FOnStateChange: TGameStateEvent;

    procedure SetState(const NewState: TGameState);
    procedure LogMsg(const AMsg: string; IsError: Boolean = False);

    { Fitur Pamungkas: Memicu sabotase terminal }
    procedure TriggerSystemBreach;

    { Event Handlers yang di-bind ke TGenomData & TAIManager }
    procedure HandleGenomSuccess(Sender: TObject);
    procedure HandleGenomGameOver(Sender: TObject);
    procedure HandleAIResponse(const AMsg: string);

    { Parser dan Eksekutor Perintah CLI }
    procedure ExecuteHelp;
    procedure ExecuteStatus;
    procedure ExecuteMutate(const Args: TStringArray);
    procedure ExecuteAsk(const ACmdLine: string);
    procedure ExecuteShop;
    procedure ExecuteUpgrade(const Args: TStringArray);
    procedure ExecuteMacro(const Args: TStringArray; const ACmdLine: string);
  public
    constructor Create(const ADBPath: string);
    destructor Destroy; override;

    { Inisialisasi awal sistem (Login/Load Player) }
    procedure InitializeSystem(const APlayerName: string);

    { Memulai level/isolasi patogen baru }
    procedure StartSimulation;

    { Main Game Loop (Di-trigger oleh TTimer UI berdasarkan DeltaTime real-world) }
    procedure Update(DeltaTimeSeconds: Double);

    { Menerima input string murni dari UI Terminal }
    procedure ProcessCommand(const ACmdLine: string);

    { Ekspos Sub-Sistem untuk keperluan visualisasi UI }
    property DBManager: TDatabaseManager read FDBManager;
    property GenomData: TGenomData read FGenomData;
    property TelemetryManager: TTelemetryManager read FTelemetryManager;
    property State: TGameState read FState;

    { Events }
    property OnLogMessage: TLogMessageEvent read FOnLogMessage write FOnLogMessage;
    property OnStateChange: TGameStateEvent read FOnStateChange write FOnStateChange;
  end;

implementation

{ TGameEngine }

constructor TGameEngine.Create(const ADBPath: string);
begin
  inherited Create;
  FState := gsBooting;
  Randomize; // Inisialisasi seed acak untuk Breach Timer

  // Inisialisasi Subsistem (Dependency Injection terpusat)
  FDBManager := TDatabaseManager.Create(ADBPath);
  FGenomData := TGenomData.Create;
  FTelemetryManager := TTelemetryManager.Create(FGenomData, 150);

  // Inisialisasi AI & Macro Manager
  FAIManager := TAIManager.Create;
  FAIManager.OnResponse := @HandleAIResponse;

  FMacroManager := TMacroManager.Create(ExtractFilePath(ParamStr(0)) + 'data\macros.ini');

  // Binding Event TGenomData ke Engine
  FGenomData.OnSuccess := @HandleGenomSuccess;
  FGenomData.OnGameOver := @HandleGenomGameOver;
end;

destructor TGameEngine.Destroy;
begin
  FMacroManager.Free;
  FAIManager.Free;
  FTelemetryManager.Free;
  FGenomData.Free;
  FDBManager.Free;
  inherited Destroy;
end;

procedure TGameEngine.SetState(const NewState: TGameState);
begin
  if FState <> NewState then
  begin
    FState := NewState;
    if Assigned(FOnStateChange) then
      FOnStateChange(FState);
  end;
end;

procedure TGameEngine.LogMsg(const AMsg: string; IsError: Boolean);
begin
  if Assigned(FOnLogMessage) then
    FOnLogMessage(AMsg, IsError);
end;

procedure TGameEngine.InitializeSystem(const APlayerName: string);
begin
  try
    FDBManager.Initialize;
    FPlayerProfile := FDBManager.GetOrCreatePlayer(APlayerName);

    LogMsg('BIO-SYNTH OS Initialized.');
    LogMsg(Format('Welcome, Bio-Architect %s. Lab Level: %d | Credits: %d', [FPlayerProfile.Username, FPlayerProfile.LabLevel, FPlayerProfile.TotalCredits]));
    LogMsg('System AI Assistant & Macro Engine online. Type "help" for commands.');

    SetState(gsIdle);
  except
    on E: Exception do
    begin
      LogMsg('DATABASE ERROR: ' + E.Message, True);
    end;
  end;
end;

procedure TGameEngine.StartSimulation;
begin
  if (FState = gsPlaying) or (FState = gsBreach) then
  begin
    LogMsg('Simulation is already running.', True);
    Exit;
  end;

  // Untuk MVP, ambil patogen pertama dari database
  if FDBManager.GetFirstPathogen(FCurrentPathogen) then
  begin
    FGenomData.LoadPathogen(FCurrentPathogen);
    FTelemetryManager.ResetTelemetry;

    // Setel waktu sabotase pertama kali antara 20 hingga 40 detik
    FBreachTimer := 20.0 + Random(20);

    SetState(gsPlaying);
    LogMsg(Format('Pathogen Loaded: %s [Complexity: %d]', [FCurrentPathogen.Name, FCurrentPathogen.ComplexityLevel]));
    LogMsg('WARNING: Sample degradation started. Initialize isolation sequence.');
  end
  else
    LogMsg('SYSTEM FAULT: No pathogen data found in archives.', True);
end;

procedure TGameEngine.Update(DeltaTimeSeconds: Double);
begin
  if (FState <> gsPlaying) and (FState <> gsBreach) then Exit;

  if FState = gsPlaying then
  begin
    // 1. Eksekusi logika inti patogen (degradasi, mutasi acak) normal
    FGenomData.Update(DeltaTimeSeconds);
    FGenomData.CoolDownHeat(5.0 * DeltaTimeSeconds);

    // 2. Hitung mundur waktu menuju System Breach
    FBreachTimer := FBreachTimer - DeltaTimeSeconds;
    if (FBreachTimer <= 0) and (FCurrentPathogen.ComplexityLevel >= 1) then
      TriggerSystemBreach;
  end
  else if FState = gsBreach then
  begin
    // Hukuman Sabotase: Degradasi patogen dan akumulasi panas dipercepat 3x lipat
    FGenomData.Update(DeltaTimeSeconds * 3.0);
    // Tidak ada pendinginan selama sabotase
  end;

  // 3. Rekam jejak telemetri untuk TAChart
  FTelemetryManager.UpdateVitals(DeltaTimeSeconds);
  FTelemetryManager.UpdateChromatogram(DeltaTimeSeconds);
end;

procedure TGameEngine.TriggerSystemBreach;
const
  CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
var
  i: Integer;
begin
  SetState(gsBreach);

  // Buat 4 kode unik acak untuk Override
  FOverrideHash := '';
  for i := 1 to 4 do
    FOverrideHash := FOverrideHash + CHARS[Random(Length(CHARS)) + 1];

  LogMsg('!!! CRITICAL SYSTEM BREACH DETECTED !!!', True);
  LogMsg('UNAUTHORIZED CYBER-BIOLOGICAL ENTITY HAS HIJACKED THE CONSOLE.', True);
  LogMsg(Format('[AI-CRITICAL]: Kernel compromised! Use the ''override %s'' command to block the port!', [FOverrideHash]), True);
end;

procedure TGameEngine.ProcessCommand(const ACmdLine: string);
var
  Tokens: TStringArray;
  Cmd: string;
  MacroCommands: TStringArray;
  SubCmd: string;
begin
  // Abaikan spasi ekstra dan pisahkan berdasarkan spasi
  Tokens := ACmdLine.Trim.Split([' '], TStringSplitOptions.ExcludeEmpty);
  if Length(Tokens) = 0 then Exit;

  Cmd := LowerCase(Tokens[0]);

  // --- CEGAH PERINTAH NORMAL SAAT TERJADI SABOTASE ---
  if FState = gsBreach then
  begin
    if Cmd = 'override' then
    begin
      if (Length(Tokens) >= 2) and (UpperCase(Tokens[1]) = FOverrideHash) then
      begin
        LogMsg('OVERRIDE ACCEPTED. Threat neutralized. System control restored.', False);
        SetState(gsPlaying);
        // Atur ulang timer untuk ancaman sabotase berikutnya (30-60 detik)
        FBreachTimer := 30.0 + Random(30);
      end
      else
        LogMsg('OVERRIDE FAILED: Invalid hash sequence.', True);
    end
    else
      LogMsg('ERROR: TERMINAL LOCKED. UNAUTHORIZED ENTITY IN CONTROL. USE "override <hash>".', True);

    Exit; // Blokir semua perintah lain
  end;

  // --- PERINTAH NORMAL ---
  if (Cmd = 'help') or (Cmd = '?') then
    ExecuteHelp
  else if Cmd = 'status' then
    ExecuteStatus
  else if Cmd = 'isolate' then
    StartSimulation
  else if Cmd = 'mutate' then
    ExecuteMutate(Tokens)
  else if Cmd = 'shop' then
    ExecuteShop
  else if Cmd = 'upgrade' then
    ExecuteUpgrade(Tokens)
  else if Cmd = 'ask' then
    ExecuteAsk(ACmdLine)
  else if Cmd = 'macro' then
    ExecuteMacro(Tokens, ACmdLine)
  else if Cmd = 'exec' then
  begin
    if Length(Tokens) < 2 then
    begin
      LogMsg('SYNTAX ERROR: Usage: exec <macro_name>', True);
      Exit;
    end;
    SubCmd := LowerCase(Tokens[1]);
    if FMacroManager.GetMacro(SubCmd, MacroCommands) then
    begin
      LogMsg(Format('Executing Macro script [%s] (%d commands)...', [SubCmd, Length(MacroCommands)]));
      for SubCmd in MacroCommands do
        ProcessCommand(SubCmd); // Rekursi eksekusi perintah di dalam makro
    end
    else
      LogMsg(Format('MACRO FAULT: Script "%s" not found.', [Tokens[1]]), True);
  end
  else if Cmd = 'reload_ai_config' then
  begin
    FAIManager.LoadConfig;
    LogMsg('[SYS] AI Core Configuration reloaded successfully.', False);
  end
  else
    LogMsg('Unknown command. Type "help" for a list of valid commands.', True);
end;

procedure TGameEngine.ExecuteHelp;
begin
  LogMsg('AVAILABLE COMMANDS:');
  LogMsg('  isolate                      - Load a new pathogen and start simulation');
  LogMsg('  status                       - Show current sample vitals');
  LogMsg('  mutate <pattern> <replace>   - Use RegExpr to synthesize DNA strand');
  LogMsg('  shop                         - Open Laboratory Upgrades Catalog');
  LogMsg('  upgrade <code>               - Purchase lab upgrade module');
  LogMsg('  macro list                   - Show saved macro scripts');
  LogMsg('  macro save <name> <cmd>      - Save a script command to macro');
  LogMsg('  exec <name>                  - Execute a saved macro script');
  LogMsg('  ask <question>               - Consult the AI-Powered Lab Assistant');
  LogMsg('  settings                     - Open AI Core Configuration');
  LogMsg('  clear                        - Clear terminal output');
end;

procedure TGameEngine.ExecuteStatus;
begin
  if FState <> gsPlaying then
  begin
    LogMsg('No active sample in the synthesizer.');
    Exit;
  end;
  LogMsg(Format('SAMPLE VITALS - Stability: %.1f%% | Contamination: %.1f%% | Heat: %.1f%%',
                [FGenomData.Stability, FGenomData.Contamination, FGenomData.Heat]));
end;

procedure TGameEngine.ExecuteMutate(const Args: TStringArray);
var
  Pattern, Replacement, ErrMsg: string;
begin
  if FState <> gsPlaying then
  begin
    LogMsg('COMMAND REJECTED: No active simulation.', True);
    Exit;
  end;

  if Length(Args) < 3 then
  begin
    LogMsg('SYNTAX ERROR: Usage: mutate <pattern> <replacement>', True);
    Exit;
  end;

  Pattern := Args[1];
  Replacement := Args[2];

  LogMsg(Format('Executing RegExpr synthesis... [Pattern: %s] [Rep: %s]', [Pattern, Replacement]));

  if FGenomData.ExecuteRegExpr(Pattern, Replacement, ErrMsg) then
    LogMsg('Synthesis accepted. Integrity stabilized.')
  else
    LogMsg(ErrMsg, True);
end;

procedure TGameEngine.ExecuteAsk(const ACmdLine: string);
var
  Question: string;
begin
  if Length(ACmdLine) <= 4 then
  begin
    LogMsg('SYNTAX ERROR: Usage: ask <your question>', True);
    Exit;
  end;

  Question := Trim(Copy(ACmdLine, 5, Length(ACmdLine)));
  LogMsg('Transmitting query to OS AI Core...');

  if FState = gsPlaying then
    FAIManager.Ask(Question, True, FGenomData.Stability, FGenomData.Heat, FGenomData.Contamination)
  else
    FAIManager.Ask(Question, False, 0, 0, 0);
end;

procedure TGameEngine.ExecuteShop;
var
  Upgrades: specialize TArray<TLabUpgradeInfo>;
  U: TLabUpgradeInfo;
begin
  FPlayerProfile := FDBManager.GetOrCreatePlayer(FPlayerProfile.Username);

  LogMsg('========================================');
  LogMsg(Format(' LABORATORY UPGRADES SHOP | Credits: %d CR', [FPlayerProfile.TotalCredits]));
  LogMsg('========================================');

  Upgrades := FDBManager.GetAllUpgrades;
  for U in Upgrades do
  begin
    LogMsg(Format(' [%s]', [U.Code]));
    LogMsg(Format('   Name: %s (Level: %d/%d)', [U.Name, U.CurrentLevel, U.MaxLevel]));
    LogMsg(Format('   Cost: %d Credits | Category: %s', [U.BaseCost * (U.CurrentLevel + 1), U.Category]));
  end;

  LogMsg('----------------------------------------');
  LogMsg(' Type "upgrade <code>" to purchase a module.');
  LogMsg('========================================');
end;

procedure TGameEngine.ExecuteUpgrade(const Args: TStringArray);
var
  UpgradeCode: string;
  Success: Boolean;
  NewMsg: string;
  UpdatedCredits: Integer;
begin
  if Length(Args) < 2 then
  begin
    LogMsg('SYNTAX ERROR: Usage: upgrade <upgrade_code>', True);
    Exit;
  end;

  UpgradeCode := UpperCase(Args[1]);
  Success := FDBManager.PurchaseUpgrade(FPlayerProfile.ID, UpgradeCode, NewMsg, UpdatedCredits);

  if Success then
  begin
    FPlayerProfile.TotalCredits := UpdatedCredits;
    LogMsg('[SUCCESS] ' + NewMsg, False);
    LogMsg(Format('Remaining Credits: %d CR', [FPlayerProfile.TotalCredits]), False);
  end
  else
    LogMsg('[FAILED] ' + NewMsg, True);
end;

procedure TGameEngine.ExecuteMacro(const Args: TStringArray; const ACmdLine: string);
var
  SubCmd, MacroName, CmdContent: string;
  MacroList: TStringArray;
  M: string;
begin
  if Length(Args) < 2 then
  begin
    LogMsg('SYNTAX ERROR: Usage: macro list | macro save <name> <command>', True);
    Exit;
  end;

  SubCmd := LowerCase(Args[1]);

  if SubCmd = 'list' then
  begin
    MacroList := FMacroManager.GetMacroNames;
    LogMsg('=== SAVED MACROS ===');
    if Length(MacroList) = 0 then
      LogMsg(' No custom macros found.')
    else
    begin
      for M in MacroList do
        LogMsg('  - ' + M);
    end;
    LogMsg('====================');
  end
  else if SubCmd = 'save' then
  begin
    if Length(Args) < 4 then
    begin
      LogMsg('SYNTAX ERROR: Usage: macro save <name> <command>', True);
      Exit;
    end;

    MacroName := LowerCase(Args[2]);
    CmdContent := Trim(Copy(ACmdLine, Pos(Args[2], ACmdLine) + Length(Args[2]), Length(ACmdLine)));
    CmdContent := Trim(Copy(CmdContent, Pos(Args[3], CmdContent), Length(CmdContent)));

    FMacroManager.AddCommandToMacro(MacroName, CmdContent);
    LogMsg(Format('[SUCCESS] Command saved to macro [%s].', [MacroName]));
  end
  else
    LogMsg('Unknown macro action. Use "macro list" or "macro save".', True);
end;

{ --- Event Handlers Status Permainan --- }

procedure TGameEngine.HandleGenomSuccess(Sender: TObject);
begin
  SetState(gsVictory);
  LogMsg('SEQUENCE MATCHED! Pathogen successfully isolated and neutralized.', False);

  FDBManager.UpdatePlayerStats(FPlayerProfile.ID, 100, FGenomData.Stability);
  FDBManager.SaveRunHistory(FPlayerProfile.ID, FCurrentPathogen.ID,
                            FGenomData.Stability, FGenomData.Contamination, True);

  LogMsg('Reward Granted: +100 Credits added to your account.', False);
end;

procedure TGameEngine.HandleGenomGameOver(Sender: TObject);
begin
  SetState(gsGameOver);
  if FGenomData.Stability <= 0 then
    LogMsg('CRITICAL FAILURE: Sample degraded completely.', True)
  else
    LogMsg('CRITICAL FAILURE: Lab contamination overload.', True);

  FDBManager.SaveRunHistory(FPlayerProfile.ID, FCurrentPathogen.ID,
                            FGenomData.Stability, FGenomData.Contamination, False);
end;

procedure TGameEngine.HandleAIResponse(const AMsg: string);
begin
  LogMsg('[AI] ' + AMsg, False);
end;

end.

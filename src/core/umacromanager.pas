unit uMacroManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles;

type
  { TMacroManager: Pengelola skrip makro otomatisasi terminal berbasis INI }
  TMacroManager = class
  private
    FIniPath: string;
  public
    constructor Create(const AIniPath: string);
    destructor Destroy; override;

    { Mengambil daftar perintah dalam satu makro berdasarkan nama }
    function GetMacro(const AName: string; out ACommands: TStringArray): Boolean;

    { Menambahkan perintah ke dalam makro tertentu (menyimpannya secara persisten) }
    procedure AddCommandToMacro(const AName, ACommand: string);

    { Mengambil daftar seluruh nama makro yang tersimpan di berkas konfigurasi }
    function GetMacroNames: TStringArray;
  end;

implementation

constructor TMacroManager.Create(const AIniPath: string);
begin
  inherited Create;
  FIniPath := AIniPath;
end;

destructor TMacroManager.Destroy;
begin
  inherited Destroy;
end;

function TMacroManager.GetMacro(const AName: string; out ACommands: TStringArray): Boolean;
var
  Ini: TIniFile;
  CmdString: string;
begin
  Result := False;
  SetLength(ACommands, 0);

  Ini := TIniFile.Create(FIniPath);
  try
    if Ini.SectionExists(AName) then
    begin
      CmdString := Ini.ReadString(AName, 'Commands', '');
      if CmdString <> '' then
      begin
        ACommands := CmdString.Split(['|'], TStringSplitOptions.ExcludeEmpty);
        Result := Length(ACommands) > 0;
      end;
    end;
  finally
    Ini.Free;
  end;
end;

procedure TMacroManager.AddCommandToMacro(const AName, ACommand: string);
var
  Ini: TIniFile;
  ExistingCmds: string;
begin
  Ini := TIniFile.Create(FIniPath);
  try
    ExistingCmds := Ini.ReadString(AName, 'Commands', '');
    if ExistingCmds = '' then
      ExistingCmds := ACommand
    else
      ExistingCmds := ExistingCmds + '|' + ACommand;

    Ini.WriteString(AName, 'Commands', ExistingCmds);
  finally
    Ini.Free;
  end;
end;

function TMacroManager.GetMacroNames: TStringArray;
var
  Ini: TIniFile;
  Sections: TStringList;
  i: Integer;
begin
  SetLength(Result, 0);
  Ini := TIniFile.Create(FIniPath);
  Sections := TStringList.Create;
  try
    Ini.ReadSections(Sections);
    if Sections.Count > 0 then
    begin
      SetLength(Result, Sections.Count);
      for i := 0 to Sections.Count - 1 do
        Result[i] := Sections[i];
    end;
  finally
    Sections.Free;
    Ini.Free;
  end;
end;

end.

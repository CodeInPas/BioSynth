unit uAudioManager;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, BASS;

type
  TAudioManager = class
  private
    FBGMChannel: HSTREAM;
    FIsInitialized: Boolean;
  public
    constructor Create;
    destructor Destroy; override;

    { Memutar musik latar secara berulang (Looping) }
    procedure PlayBGM(const AFileName: string; AVolume: Single = 0.5);
    procedure StopBGM;

    { Memutar efek suara (Fire and Forget) }
    procedure PlaySFX(const AFileName: string; AVolume: Single = 1.0);
  end;

var
  // Global instance agar mudah diakses dari UI atau Renderer
  AudioManager: TAudioManager;

implementation

{ TAudioManager }

constructor TAudioManager.Create;
begin
  inherited Create;
  FBGMChannel := 0;

  // PERBAIKAN: Ubah argumen keempat (Window Handle) dari 'nil' menjadi '0'
  // Inisialisasi BASS pada perangkat default (Device -1), 44100Hz
  FIsInitialized := BASS_Init(-1, 44100, 0, 0, nil);

  if not FIsInitialized then
    Writeln('ERROR: Gagal menginisialisasi pustaka BASS. Pastikan bass.dll tersedia.');
end;

destructor TAudioManager.Destroy;
begin
  if FIsInitialized then
  begin
    StopBGM;
    BASS_Free; // Bebaskan seluruh memori audio dari RAM
  end;
  inherited Destroy;
end;

// PERBAIKAN: Ubah tipe data 'Float' menjadi 'Single' agar cocok dengan interface
procedure TAudioManager.PlayBGM(const AFileName: string; AVolume: Single);
begin
  if not FIsInitialized then Exit;

  StopBGM;

  // Buat stream audio dengan mode BASS_SAMPLE_LOOP
  FBGMChannel := BASS_StreamCreateFile(False, PChar(AFileName), 0, 0, BASS_SAMPLE_LOOP);
  if FBGMChannel <> 0 then
  begin
    BASS_ChannelSetAttribute(FBGMChannel, BASS_ATTRIB_VOL, AVolume);
    BASS_ChannelPlay(FBGMChannel, False);
  end;
end;

procedure TAudioManager.StopBGM;
begin
  if FBGMChannel <> 0 then
  begin
    BASS_ChannelStop(FBGMChannel);
    BASS_StreamFree(FBGMChannel);
    FBGMChannel := 0;
  end;
end;

// PERBAIKAN: Ubah tipe data 'Float' menjadi 'Single' agar cocok dengan interface
procedure TAudioManager.PlaySFX(const AFileName: string; AVolume: Single);
var
  SFXChannel: HSTREAM;
begin
  if not FIsInitialized then Exit;

  // Stream standar tanpa loop
  SFXChannel := BASS_StreamCreateFile(False, PChar(AFileName), 0, 0, 0);
  if SFXChannel <> 0 then
  begin
    BASS_ChannelSetAttribute(SFXChannel, BASS_ATTRIB_VOL, AVolume);
    // BASS_ChannelPlay tidak menghentikan eksekusi kode (asinkron)
    BASS_ChannelPlay(SFXChannel, False);

    // Catatan: Pada implementasi tingkat lanjut, Anda bisa menggunakan BASS_ChannelSetSync
    // untuk membersihkan (BASS_StreamFree) SFXChannel setelah selesai diputar,
    // atau menggunakan sistem BASS_SampleLoad untuk SFX yang sering berulang seperti ketikan keyboard.
  end;
end;

initialization
  AudioManager := nil;

finalization
  if Assigned(AudioManager) then
    AudioManager.Free;

end.

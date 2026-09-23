program BioSynth;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads, // Wajib diaktifkan di Linux/macOS untuk mendukung background worker/multithreading
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // LCL widgetset (Harus berada di urutan pertama)
  Forms,
  fMain, BASS;

{$R *.res}

begin
  // Memastikan aplikasi menggunakan sumber daya form yang terkompilasi
  RequireDerivedFormResource := True;

  // Mengaktifkan dukungan High-DPI rendering untuk monitor modern (4K/Retina)
  Application.Scaled:=True;

  // Inisialisasi engine LCL
  Application.Initialize;

  // Membuat instance utama Form Simulasi
  Application.CreateForm(TfrmMain, frmMain);
  // Menjalankan Game Loop (Message Loop bawaan OS)
  Application.Run;
end.


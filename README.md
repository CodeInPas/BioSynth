# BioSynth

<img width="1291" height="687" alt="BIO" src="https://github.com/user-attachments/assets/2391167f-8d9d-4ba6-96ba-98eb31ea9ee0" />

A terminal-based bio-hacking simulation. Master Regular Expressions (RegEx) to isolate, stabilize, and cure pathogens in a real-time 3D environment before the system breaches.

# BIO-SYNTH: Gene Sequencer

> A real-time CLI puzzle game where you use RegEx to repair mutating 3D DNA sequences. Built with Lazarus / Free Pascal.

**BIO-SYNTH** is a real-time laboratory crisis simulation game. Players take on the role of a *Bio-Architect* who must accurately use *Regular Expression* (RegEx) commands through a CLI Terminal interface to cleanse pollutants from DNA strands before the system overheats and triggers a *System Breach*.

## 🧬 Key Features
* **Terminal-Based Gameplay:** Full interaction via CLI with support for mutation commands and macro execution.
* **Real-time 3D DNA Renderer:** Interactive 3D DNA helix visualization, *glassmorphism* UI effects, and a scrolling sci-fi background.
* **Dynamic Audio Engine:** Responsive laboratory BGM ambience and alarm SFX powered by the **BASS** audio library.
* **AI Core Assistant:** An **SQLite**-driven *in-game* assistant to provide RegEx puzzle hints and system intelligence.

## 🛠️ Tech Stack & Dependencies
* **Engine/IDE:** [Lazarus IDE](https://www.lazarus-ide.org/) / Free Pascal
* **Graphics:** BGRABitmap (required for UI canvas and 3D graphics rendering)
* **Audio:** [BASS Audio Library](https://www.un4seen.com/) (ensure `bass.dll` is placed in the project's `/bin` folder)
* **Database:** SQLite3 (the `biosynth.db` file must be located in the `/data` folder)

## 📖 Complete Documentation
This project includes comprehensive documentation. For gameplay instructions, a list of terminal commands, RegEx syntax guides, database schemas, and answers to technical questions, please refer to:

👉 **[READ THE FULL DOCUMENTATION & 40 FAQs HERE](link-to-your-doc-file.md)**

## 🚀 How to Run (Build & Play)
1. *Clone* this repository.
2. Open the `BioSynth.lpi` project file using the Lazarus IDE.
3. Ensure the **BGRABitmap** library is installed via the Lazarus Package Manager.
4. Make sure the `bass.dll` file and the `data/biosynth.db` database are present in your output directory (usually `/bin/`).
5. Press `F9` (Run) to compile and launch the simulation.


#!/bin/bash

emulator="/Applications/DuckStation.app/Contents/MacOS/DuckStation"
emu_dir="/Users/snake/Ceres/Emulation/PS1/Games/"

# get basename
filename=$(basename "$1")
basename="${filename%.*}"

game_dir="$emu_dir$basename"


# Temporäres Verzeichnis erstellen
#ft_temp=$(mktemp -d -t ft_)

if [ -d "$game_dir" ]; then
    echo "Das Verzeichnis '$game_dir' existiert bereits. Kein Entpacken erforderlich."
else
    # Prüfen, ob die Datei auf .chd endet
    if [[ "$filename" == *.chd ]]; then
        echo "Datei endet auf .chd, wird nach $game_dir kopiert."
        mkdir -p "$game_dir"
        cp "$1" "$game_dir/"
    else
        # Archiv entpacken
        #7zz x "$1" -o"$ft_temp"
        7zz x "$1" -o"$game_dir"
    fi
fi

# Prüfen, ob eine .cue Datei existiert
#cue_file=$(find "$ft_temp" -type f -iname "*.bin" | head -n 1)
cue_file=$(find "$game_dir" -type f -iname "*.cue" | head -n 1)

# Falls keine .cue Datei gefunden wurde, nach .iso Datei suchen
if [ -z "$cue_file" ]; then
    iso_file=$(find "$game_dir" -type f -iname "*.iso" | head -n 1)
    chd_file=$(find "$game_dir" -type f -iname "*.iso" | head -n 1)
    
    # Wenn eine .iso Datei gefunden wurde, übergeben
    if [ -n "$iso_file" ]; then
        cue_file="$iso_file"
    elif [ -n "$chd_file" ]; then 
        cue_file="$chd_file"
    else
        echo "Weder .cue noch .iso Datei gefunden."
        exit 1
    fi
fi

# DuckStation mit der gefundenen Datei starten
"$emulator" "$cue_file"

#!/bin/bash

# Überprüfe, ob die korrekte Anzahl an Argumenten übergeben wurde
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <input_directory> <output_directory>"
    exit 1
fi

input_directory="$1"
output_directory="$2"

# Erstelle das Ausgabe-Verzeichnis, falls es nicht existiert
mkdir -p "$output_directory"

# Finde alle .iso Dateien und konvertiere sie
find "$input_directory" -type f -name '*.iso' | while read iso_file; do
    # Extrahiere den Basisnamen der Datei ohne Erweiterung
    base_name=$(basename "$iso_file" .iso)
    # Setze den Ausgabe-Dateinamen
    output_file="$output_directory/"
    
    echo "Konvertiere $iso_file zu $output_file"
    makemkvcon mkv iso:"$iso_file" all "$output_directory" --minlength=0
done

## Some useful shell Scripts I made for myself and might be useful for others.


### backupDocker.sh
This script backups all docker compose stacks in a given directory.

### dualWallpaperRandomizer.sh
More like a triple wallpaper randomizer by now.
This script splits up a triple wallpaper image (e.g. 15360x2880) into three wallpapers (e.g. 5120x2880 each) and applies them to the three screens of your Mac.

### myCodesign.sh
This script codesigns a given binary or app and applies the +x permission so that unsigned apps can be run without annoying Gatekeeper warnings.

### iso2mkv.sh
This script converts all ISO files and DVD folder structures (VIDEO_TS) in a given directory into MKV files.

Usage: `iso2mkv.sh /path/to/input /path/to/output`

### pushnotify.py
A plugin for znc to send notifications to your phone using ntfy.sh.

### unrar
The unrar tool by Alexander Roshal doesn't support extracting multiple .rar files (ie. `unrar x file1.rar file2.rar` or `unrar x file*.rar`)
This tiny script fixes that.

Usage: `unrar file*.rar`
This will unrar all files like file1.rar, file2.rar etc.

### ql2icon.sh
	This requires fileicon from https://github.com/mklement0/fileicon in your $PATH
This script applies the icon preview from QuickLook as a icon. This is good for comic book files which take a long time to generate icon previews. With this you apply it as a icon one time and always get the nice icon without waiting.


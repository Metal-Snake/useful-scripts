#!/bin/bash

function screenIsLocked { [ "$(/usr/libexec/PlistBuddy -c "print :IOConsoleUsers:0:CGSSessionScreenIsLocked" /dev/stdin 2>/dev/null <<< "$(ioreg -n Root -d1 -a)")" = "true" ] && return 0 || return 1; }

#say "Hello World"

if screenIsLocked; then
    #say "locked"
    sleep 15
    #exit
fi

verbose=false
width=5120
height=2880

# Writings location
sourcePath="$HOME/Pictures/Digital Blasphemy 15360x2880"
destination="$HOME/Pictures/Digital Blasphemy 15360x2880 Mac"

# suffixes (delimited by the | char)
suffixes='jpg|png'


while getopts 'p:d:e:s:w:h:v' flag; do
  case "${flag}" in
    p) sourcePath=${OPTARG} ;;
    d) destination=${OPTARG} ;;
    e) suffixes=${OPTARG} ;;
    s) suffixes=${OPTARG} ;;
    w) width=${OPTARG{} ;;
    h) height=${OPTARG{} ;;
    v) verbose=true ;;
#    *) error "Unexpected option ${flag}" ;;
  esac
done

export PATH=$HOME/bin:/opt/homebrew/bin:$PATH

find -E "$sourcePath" -iregex ".*.($suffixes)" |
(
    # Put all lines into lines[] array
    i=0; while read line; do lines[i++]="$line"; done
    
    if [ $i -le 0 ]; then echo "Nothing found"; exit; fi

    # Open a random lines[] element
    myrandom=$[$RANDOM%$i]
    if [ "$verbose" = true ]; then
      j=1; for wallpaper in "${lines[@]}"; do echo $((j++)) $wallpaper; done
      echo "using $((myrandom+1))/$i ${lines[$myrandom]}"
    fi

    theChosenOne=${lines[$myrandom]}
    #path=${theChosenOne%/*}
    fileName=${theChosenOne##*/}
    base=${fileName%%.*} 
    ext=${fileName#*.} 
    
    leftFile=${destination}/${base}_left.${ext}
    middleFile=${destination}/${base}_middle.${ext}
    rightFile=${destination}/${base}_right.${ext}

    if [ "$verbose" = true ]; then
      echo $leftFile
      echo $middleFile
      echo $rightFile
    fi

    if [[ ! -f "$leftFile" || ! -f "$middleFile" || ! -f "$rightFile" ]]; then 
      echo "convert magick"
      #convert "$theChosenOne" -crop ${width}x${height}+0+0 "$leftFile"
      magick "$theChosenOne" -crop ${width}x${height}+0+0 "$leftFile"
      #convert "$theChosenOne" -crop ${width}x${height}+${width}+0 "$middleFile"
      magick "$theChosenOne" -crop ${width}x${height}+${width}+0 "$middleFile"
      #convert "$theChosenOne" -crop ${width}x${height}+$((width*2))+0 "$rightFile"
      magick "$theChosenOne" -crop ${width}x${height}+$((width*2))+0 "$rightFile"
    fi
 
    osascript - "$leftFile" "$middleFile" "$rightFile" <<EOF 
    on run argv
      set leftFile to item 1 of argv
      set middleFile to item 2 of argv
      set rightFile to item 3 of argv

      tell application "System Events"
        set desktopPictures to picture of every desktop
        set leftIndex to missing value
        set middleIndex to missing value
        set rightIndex to missing value

        repeat with i from 1 to (count of desktopPictures)
          set thisPic to item i of desktopPictures
          set thisPath to (thisPic as text)
          if thisPath ends with "_left.jpg" or thisPath ends with "_left.png" or thisPath ends with "_left.jpeg" then
            if leftIndex is missing value then set leftIndex to i
          else if thisPath ends with "_middle.jpg" or thisPath ends with "_middle.png" or thisPath ends with "_middle.jpeg" then
            if middleIndex is missing value then set middleIndex to i
          else if thisPath ends with "_right.jpg" or thisPath ends with "_right.png" or thisPath ends with "_right.jpeg" then
            if rightIndex is missing value then set rightIndex to i
          end if
        end repeat

        if leftIndex is missing value then set leftIndex to 4
        if middleIndex is missing value then set middleIndex to 1
        if rightIndex is missing value then set rightIndex to 3

        tell desktop leftIndex
          set picture to leftFile
        end tell
        tell desktop middleIndex
          set picture to middleFile
        end tell
        tell desktop rightIndex
          set picture to rightFile
        end tell
      end tell
    end run
EOF
)

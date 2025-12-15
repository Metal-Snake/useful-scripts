#!/bin/bash

## --- TODO ---
## print Usage if $1 empty

# --- set Options ---
while [[ "$1" = "-"* ]] ; do
  case "$1" in
    -f|--force) force=true ;;
    -p|--preview) preview=true ;;
    -i|--icon) preview=false ;;
    -s|--size) shift; size=$1 ;;
    -q|--quiet) quiet=1 ;;
  esac
  shift
done

# --- set default params if they aren't set ---
if [ -z ${force+x} ]; then force=false; fi
if [ -z ${preview+x} ]; then preview=false; fi
if [ -z ${quiet+x} ]; then quiet=0; fi
if [ -z ${size+x} ]; then qlArgs="$qlArgs -s 1024" ; size=1024 ; else qlArgs="$qlArgs -s $size"; fi

if [ "$preview" = false ] ; then qlArgs="$qlArgs -i" ; sips=false; else sips=true; fi
# --- end set Options ---

i=1 applied=0 skipped=0 count=$#

# --- main loop ---
while [ "$1" != '' ] ; do
  filename=`basename "$1"`
  if ! $force && fileicon -q test "$1"; then
      (( quiet )) || echo "$i/$count nothing to do for \"$filename\""
      ((i++)) ; ((skipped++)) ; shift ; continue
  fi

  target=$1
  tmpImage="${TMPDIR}${filename}.png"

  # Create a thumbnail from the file preview
  qlmanage -t $qlArgs -o ${TMPDIR} "$target" &>/dev/null
  if [ "$sips" = true ] ; then
    sips -Z $size -p $size $size "$tmpImage" &>/dev/null
  fi

  # apply the image to the target
  fileicon -q set "$target" "$tmpImage"

  # clean up
  rm "$tmpImage"

  (( quiet )) || echo "$i/$count Icon applied to \"$filename\""
  ((i++)) ; ((applied++)) ; shift
done


(( quiet )) || echo "=====Results====="
(( quiet )) || echo " Applied $applied icons"
(( quiet )) || echo " Skipped $skipped files"
(( quiet )) || echo "================="

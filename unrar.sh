#!/bin/bash

while [ "$1" == '-*' ] || [ "$1" == 'x' ]
do
	PARAMS="$PARAMS $1"
	shift
done

if [ "$PARAMS" == '' ]
then
     PARAMS='x'
fi

while [ "$1" != '' ] 
do
    /usr/local/bin/unrar $PARAMS "$1" 
    shift
done

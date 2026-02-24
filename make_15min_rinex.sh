#!/bin/bash

# The script takes the UBX bin recorded data and translates it into a RINEX version 3 file

# Configuration for manual input
rpiUSER="alexk" # user name
STATION="ANTC" # station name
binEXT="ubx" # bin file extention
nSEC2KEEP=452 # if 15 min rinex file conatins less seconds than this value not keep such file

# Prepare Folders structure
RAW_DIR="/home/$rpiUSER/record"  # Folder with raw data
TEMP_DIR="/home/$rpiUSER/record/temp_recovery" # Temporary folder for processing
FINAL_DIR="/home/$rpiUSER/data"  # Folder with output compressed rinex (.crx.gz) 
FINAL_DIR_BIN="/home/$rpiUSER/data_bin" # Folder with processed bin (and corrupt rnx if any) data. For further remove

# Make Folders structure
mkdir -p "$RAW_DIR"
mkdir -p "$TEMP_DIR"
mkdir -p "$FINAL_DIR"
mkdir -p "$FINAL_DIR_BIN"

# Date/time of run
echo `date -u`

# First, what quarter of the hour is it.
QUARTER=$1

# Go to the record directory
# cd "/home/$rpiUSER/record"

# Get parts of the date and time
if [[ "$QUARTER" -lt "4" ]]; then

    YEAR=`date -u +"%Y"`
    MONTH=`date -u +"%m"`
    DAY=`date -u +"%d"`
    DOY=`date -u +"%j"`
    HOUR=`date -u +"%H"`

else

    YEAR=`date -u +"%Y" -d "-1 hour"`
    MONTH=`date -u +"%m" -d "-1 hour"`
    DAY=`date -u +"%d" -d "-1 hour"`
    DOY=`date -u +"%j" -d "-1 hour"`
    HOUR=`date -u +"%H" -d "-1 hour"`
fi

# Process each BIN file found in the record directory
for BINFILE in "$RAW_DIR"/*."$binEXT"; do
    [ -f "$BINFILE" ] || continue

    echo "Converting $(basename "$BINFILE")..."

    # Create a unique temp name for the RINEX fragment
    TEMP_OUT="$RAW_DIR/$(basename "$BINFILE" ."$binEXT").rnx"

    # Convert BIN to RINEX
    convbin -ti 1.0000 -od -os -v 3.04 \
        -hm "$STATION" \
        -hc "For permission to use this data, contact:" \
        -hc "PT Jayachandran (chain@unb.ca)" \
        -hc "Canadian High Arctic Ionospheric Network" \
        -hc "Telephone: 506-453-4637" \
        -ho "PT Jayachandran/CHAIN" \
        -hr "Unknown/U-Blox C099-F9P" \
        -ha "Unknown/TOPGNSS TOP158" \
        -o "$TEMP_OUT" "$BINFILE" >/dev/null 2>&1

    # echo error if convbin fail
    if [[ $? != 0 ]]; then
	echo "There was an error with convbin"
    else  $ clean rnx files if convbin converted bin files correctly
    	# Clean the rnx file
    	sed -i -e 's/[ \t]*$//' -e '/log:/d' "$TEMP_OUT"
    fi

done

# preapare start time for gfzrnx
case $QUARTER in
    1) # QUATER 1
    START_TIME="${YEAR}-${MONTH}-${DAY}T${HOUR}:00:00"
    ;;

    2) # QUATER 2
    START_TIME="${YEAR}-${MONTH}-${DAY}T${HOUR}:15:00"
    ;;

    3) # QUATER 3
    START_TIME="${YEAR}-${MONTH}-${DAY}T${HOUR}:30:00"
    ;;

    4) # QUATER 4
    START_TIME="${YEAR}-${MONTH}-${DAY}T${HOUR}:45:00"
    ;;

esac

echo "Start time: ${START_TIME}"

# Merge and split into the 15-min rnx file with START_TIME + 900 sec
# and move resulting rnx to $TEMP_DIR
echo "Merging and splitting into 15-min file start time: ${START_TIME}"
gfzrnx -finp "$RAW_DIR/*.rnx" \
       -fout "$TEMP_DIR/${STATION}_%Y%j%H%M00_01Sa.rnx::RX3::" \
       -epo_beg "$START_TIME"
       -d 900  \
       -f \
       -vo 3.04 \
       -chk >/dev/null 2>&1

# echo error if gfzrnx fail
if [[ $? != 0 ]]; then
	echo "There was an error with gfzrnx"

# preparing output files
else

fi

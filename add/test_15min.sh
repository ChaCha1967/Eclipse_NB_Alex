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

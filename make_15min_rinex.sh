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
    else  # clean rnx files if convbin converted bin files correctly
    	# Clean the rnx file
    	sed -i -e 's/[ \t]*$//' -e '/log:/d' "$TEMP_OUT"
    fi

done

# preapare start time for gfzrnx
case $QUARTER in
    1) # QUATER 1
    START_TIME="${YEAR}${MONTH}${DAY}_${HOUR}0000"
    ;;

    2) # QUATER 2
    START_TIME="${YEAR}${MONTH}${DAY}_${HOUR}1500"
    ;;

    3) # QUATER 3
    START_TIME="${YEAR}${MONTH}${DAY}_${HOUR}3000"
    ;;

    4) # QUATER 4
    START_TIME="${YEAR}${MONTH}${DAY}_${HOUR}4500"
    ;;

esac

echo "Start time: ${START_TIME}"

# Merge and split into the 15-min rnx file with START_TIME + 900 sec
# and move resulting rnx to $TEMP_DIR
echo "Merging and splitting into 15-min file start time: ${START_TIME}"
gfzrnx -finp "$RAW_DIR/*.rnx" \
       -fout "$TEMP_DIR/${STATION}_%Y%j%H%M00_01Sa.rnx::RX3::" \
       -epo_beg "$START_TIME" \
       -d 900  \
       -f \
       -vo 3.04 \
       -chk >/dev/null 2>&1

# echo error if gfzrnx fail
if [[ $? != 0 ]]; then
	echo "There was an error with gfzrnx"

# preparing output files
else

    for RNX_FILE in "$TEMP_DIR"/*01S*.rnx; do
    	[ -f "$RNX_FILE" ] || continue

    	# Count the number of epochs (lines starting with '>')
    	EPOCH_COUNT=$(grep -c "^>" "$RNX_FILE")

        # Check if the count is NOT less than nSEC2KEEP (Count >= nSEC2KEEP)
        if [ "$EPOCH_COUNT" -ge "$nSEC2KEEP" ]; then

		echo "Processing $RNX_FILE with  $EPOCH_COUNT epochs" 

    		# A. Get the base filename (e.g., 202200XXX_R_20220410045_15M_01S_MO.rnx)
    		BASE_NAME=$(basename "$RNX_FILE")

    		# DYNAMIC RENAMING
    		# We take everything from the 10th character onwards and
    		# prepend your $STATION and "00CAN"
    		# The 'cut -c 10-' command removes the first 9 characters (the wrong ID)
    		SUFFIX=$(echo "$BASE_NAME" | cut -c 10-)
    		NEW_FILE_NAME="${STATION}00CAN${SUFFIX}"
      		# Extract the part before the last dot
		BASE_FILE_NAME="${NEW_FILE_NAME%.*}"
		# Extract the extension (including the dot)
		EXT_NAME="${NEW_FILE_NAME##*.}"

		# Reconstruct with "a" for first file and without a for all other files
		NEW_FILE_NAMErnx="${BASE_FILE_NAME}.${EXT_NAME}"
    		NEW_FILE_NAMEcrx="${BASE_FILE_NAME}.crx"
    		NEW_FILE_NAMEcrxgz="${BASE_FILE_NAME}.crx.gz"
    		NEW_FILE_PATHrnx="$FINAL_DIR/$NEW_FILE_NAMErnx"
    		NEW_FILE_PATHcrx="$FINAL_DIR/$NEW_FILE_NAMEcrx"

		echo "Processing: $BASE_NAME -> $NEW_FILE_NAME"

		echo "Cleaning: $(basename "$RNX_FILE")"

    		# B. Remove trailing whitespace and 'log:' lines potentially re-introduced or left over
    		sed -i -e 's/[ \t]*$//' -e '/log:/d' "$RNX_FILE"

    		# C. Fix LEAP SECONDS if missing (Important for proper processing in RTKLIB/CHAIN)
    		#if ! grep -q "LEAP SECONDS" "$RNX_FILE"; then
    		#    # Inserts the Leap Second line at line 2
    		#    sed -i '2i \    18                                                      LEAP SECONDS' "$RNX_FILE"
    		#fi

    		# C. Optional: Ensure end of header is clean (fixes issues with some older RINEX parsers)
    		# This removes empty lines that might have been trapped at the end of the header
    		sed -i '/END OF HEADER/s/[[:space:]]*$//' "$RNX_FILE"

    		# D. PERFORM RENAME
    		mv "$RNX_FILE" "$NEW_FILE_PATHrnx"

    		# Convert to crx
    		# remove old crx if exist
    		rm -f "$NEW_FILE_PATHcrx"
    		# convert rnx to crx
    		RNX2CRX -d ${NEW_FILE_PATHrnx}
		if [[ $? != 0 ]]; then
			echo "There was an error with RNX2CRX. Move corrupt RNX to archive"
        		mv "$NEW_FILE_PATHrnx" "$FINAL_DIR_BIN" # move rnx if corrupt to archive 
		fi

    		# gzip crx to crx.gz
    		gzip -f ${NEW_FILE_PATHcrx}
        	if [[ $? != 0 ]]; then
	    		echo "There was an error with gzip crx 2 crx.gz. Move corrupt CRX to archive"
            		mv "$NEW_FILE_PATHcrx" "$FINAL_DIR_BIN" # move crx if corrupt to archive
        	fi

        else
		echo "Skipping $RNX_FILE: Only $EPOCH_COUNT epochs (less than $nSEC2KEEP)" 
  	fi

    done

fi

# Remove processed rnx files 
echo "Remove processed rnx files..."
rm -f "$RAW_DIR"/*.rnx

## Cleanup temp files
rm -rf "$TEMP_DIR"

# Move processed bin files to archive except updeted by str2str 
echo "Archiving processed bin files..."
# 1. ls -1t: List files, one per line, newest first
# 2. tail -n +2: Start the list from the second line (skips the newest)
# 3. read -r: Safely handle filenames with spaces or special characters
ls -1t "$RAW_DIR"/*."$binEXT" 2>/dev/null | tail -n +2 | while read -r FILE; do
    echo "Archiving: $FILE"
    mv -f "$FILE" "$FINAL_DIR_BIN"
done

#FILENAMES=`ls -t "$RAW_DIR"/*."$binEXT"`
#FILES_TO_DELETE=`echo $FILENAMES | cut --complement -f 1 -d " "`
#for FILE in $FILES_TO_DELETE
#    do
#	mv -f $FILE "$FINAL_DIR_BIN"
#    done

echo "15-min file ${NEW_FILE_NAMEcrxgz} (with more than: ${nSEC2KEEP} 1S EPOCHs) are cleaned and ready"

#!/bin/bash

# The script takes the UBX bin recorded data and translates it into a RINEX version 3 file

# Configuration for manual input
# rpiUSER="alexk" # user name
STATION="ANTC" # station name
binEXT="ubx" # bin file extention
nSEC2KEEP=1 # if 15 min rinex file conatins less seconds than this value not keep such file

RAW_DIR="$HOME/record" # Temporary folder for processing
TEMP_DIR="$HOME/record/temp_recovery" # Temporary folder for processing
FINAL_DIR="$HOME/data"  # Folder with output compressed rinex (.crx.gz) 
FINAL_DIR_BIN="$HOME/archive" # Folder with processed bin (and corrupt rnx if any) data. For further remove

# Make Folders structure
# Create if not exist folder with raw data
if [ ! -d "$RAW_DIR" ]; then
    mkdir -p "$RAW_DIR" \
    	&& echo "[$(date +%T)] Directory ready: $RAW_DIR" >> make_15min_rinex.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $RAW_DIR" >> make_15min_rinex.log; \ 
    		echo "Critical Error 4ZABBIX: Check make_15min_rinex.log"; \
        	exit 1; \
    	   }
fi
# Temporary folder for processing
if [ ! -d "$TEMP_DIR" ]; then
    mkdir -p "$TEMP_DIR" \
    	&& echo "[$(date +%T)] Directory ready: $TEMP_DIR" >> make_15min_rinex.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $TEMP_DIR" >> make_15min_rinex.log; \
    		echo "Critical Error 4ZABBIX: Check make_15min_rinex.log"; \
        	exit 1; \
    	   }
fi
# Folder with output compressed rinex (.crx.gz)
if [ ! -d "$FINAL_DIR" ]; then
    mkdir -p "$FINAL_DIR" \
    	&& echo "[$(date +%T)] Directory ready: $FINAL_DIR" >> make_15min_rinex.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $FINAL_DIR" >> make_15min_rinex.log; \
    		echo "Critical Error 4ZABBIX: Check make_15min_rinex.log"; \
        	exit 1; \
    	   }
fi
# Folder with processed bin (and corrupt rnx if any) data. For further remove
if [ ! -d "$FINAL_DIR_BIN" ]; then
    mkdir -p "$FINAL_DIR_BIN" \
    	&& echo "[$(date +%T)] Directory ready: $FINAL_DIR_BIN" >> make_15min_rinex.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $FINAL_DIR_BIN" >> make_15min_rinex.log; \
    		echo "Critical Error 4ZABBIX: Check make_15min_rinex.log"; \
        	exit 1; \
    	   }
fi

# Date/time of run
echo "$(date +%T) Start bin files processing" >> make_15min_rinex.log

# First, what quarter of the hour is it.
QUARTER=$1

# Go to the record directory
# cd "/home/$rpiUSER/record"

# Get parts of the date and time
if [ "$QUARTER" -lt "4" ]; then

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

    echo "[$(date +%T)] Runing convbin to convert $BINFILE to rnx" >> make_15min_rinex.log 
    convbin -ti 1.0000 -od -os -v 3.04 \
            -hr "UBX-ZED-F9P" \
            -ha "ANN-MB-00" \
            -hm "$STATION" \
            -o "$TEMP_OUT" "$BINFILE"

    # echo error if convbin fail
    if [ $? != 0 ]; then
	echo "[$(date +%T)] WARNING: $? Could not convert $BINFILE to rnx" >> make_15min_rinex.log 
  	echo "Warning 4ZABBIX: Check make_15min_rinex.log" 
	echo "There was an error with convbin. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_15min_rinex.log
     	mv -f "$BINFILE" "$FINAL_DIR_BIN" # move bin if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $BINFILE to archive folder" >> make_15min_rinex.log
  				echo "Warning 4ZABBIX: Check make_15min_rinex.log"; \
		fi
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
       -fout "$TEMP_DIR/$::RX3::" \
       -epo_beg "$START_TIME" \
       -d 900 -f -vo 3.04 -chk >> make_15min_rinex.log 2>&1

# echo error if gfzrnx fail
if [ $? != 0 ]; then
	echo "[$(date +%T)] WARNING: $? gfzrnx could not merge rnx files" >> make_15min_rinex.log 
  	echo "Warning 4ZABBIX: Check make_15min_rinex.log"
	echo "There was an error with gfzrnx. Move corrupt rnx files to archive folder" >> make_15min_rinex.log
     	mv -f "$RAW_DIR/*.rnx" "$FINAL_DIR_BIN" # move rnx ailes if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt rnx files to archive folder" >> make_15min_rinex.log
  				echo "Warning 4ZABBIX: Check make_15min_rinex.log" 
		fi

# preparing output files
else

    for RNX_FILE in "$TEMP_DIR"/*01S*.rnx; do
    	[ -f "$RNX_FILE" ] || continue

    	# Count the number of epochs (lines starting with '>')
    	EPOCH_COUNT=$(grep -c "^>" "$RNX_FILE")

        # Check if the count is NOT less than nSEC2KEEP (Count >= nSEC2KEEP)
        if [ "$EPOCH_COUNT" -ge "$nSEC2KEEP" ]; then

		echo "Processing $RNX_FILE with  $EPOCH_COUNT epochs" >> make_15min_rinex.log

    		# Get the base filename (e.g., 202200XXX_R_20220410045_15M_01S_MO.rnx)
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

    		# PERFORM RENAME
    		mv "$RNX_FILE" "$NEW_FILE_PATHrnx"

    		# Convert to crx
    		RNX2CRX -d ${NEW_FILE_PATHrnx}
		if [ $? != 0 ]; then
			echo "There was an error: $? with RNX2CRC"
			echo "[$(date +%T)] WARNING: RNX2CRC could not convert $NEW_FILE_NAMErnx to RNX" >> make_15min_rinex.log 
  			echo "Warning 4ZABBIX: Check make_15min_rinex.log"; 
			echo "There was an error with RNX2CRX. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_15min_rinex.log
        		mv -f "$NEW_FILE_PATHrnx" "$FINAL_DIR_BIN" # move rnx if corrupt to arcchive folder
			if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_15min_rinex.log
  				echo "Warning 4ZABBIX: Check make_15min_rinex.log"; \
			fi
		else

    			# gzip crx to crx.gz
    			gzip -f ${NEW_FILE_PATHcrx}
        		if [ $? != 0 ]; then
	    			echo "There was an error with gzip. Move corrupt $NEW_FILE_NAMEcrx to archive folder" >> make_15min_rinex.log
				echo "[$(date +%T)] WARNING: gzip could not process $NEW_FILE_NAMEcrx" >> make_15min_rinex.log 
  				echo "Warning 4ZABBIX: Check make_15min_rinex.log"; 
				echo "There was an error with gzip. Move $NEW_FILE_NAMEcrx to archive folder" >> make_15min_rinex.log
            			mv -f "$NEW_FILE_PATHcrx" "$FINAL_DIR_BIN" # move crx if corrupt to archive
				if [ $? != 0 ]; then
					echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMEcrx to archive folder" >> make_15min_rinex.log
  					echo "Warning 4ZABBIX: Check make_15min_rinex.log"; \
				fi
        		fi
		fi

        else
		echo "Skipping $RNX_FILE: Only $EPOCH_COUNT epochs (less than $nSEC2KEEP)" >> make_15min_rinex.log
  	fi

    done

fi

# Remove processed rnx files
echo "Remove processed rnx files..."
echo "Remove processed rnx files" >> make_15min_rinex.log
rm -f "$RAW_DIR"/*.rnx
if [ $? != 0 ]; then
	echo "[$(date +%T)] Warning: $? Can not remove processed rnx files" >> make_15min_rinex.log
  	echo "Warning 4ZABBIX: Check make_15min_rinex.log"
fi

## Cleanup temp files
echo "Remove temporary $TEMP_DIR folder" >> make_15min_rinex.log
rm -rf "$TEMP_DIR"
if [ $? != 0 ]; then
	echo "[$(date +%T)] Warning: $? Can not remove temporary $TEMP_DIR folder" >> make_15min_rinex.log
  	echo "Warning 4ZABBIX: Check make_15min_rinex.log"
fi

# Move bin files if not opened by str2str
echo "Move processed bin file(s) to archive folder" >> make_15min_rinex.log
for BINFILE in "$RAW_DIR"/*."$binEXT"; do
	if [ -f "$BINFILE" ] && ! fuser -s "$BINFILE"; then
		mv -f "$BINFILE" "$FINAL_DIR_BIN" # move processed bin file to archive folder
		if [ $? != 0 ]; then
			echo "[$(date +%T)] Warning: $? Can not move processed $BINFILE to archive folder" >> make_15min_rinex.log
  			echo "Warning 4ZABBIX: Check make_15min_rinex.log"
		fi
	fi
done

echo "15-min file ${NEW_FILE_NAMEcrxgz} (with more than: ${nSEC2KEEP} 1S EPOCHs) are cleaned and ready" >> make_15min_rinex.log

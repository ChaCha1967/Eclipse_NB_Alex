#!/bin/bash

# Recovery data by converting bin -> rnx -> crx -> crx.gz after outages or other data acquisition failure

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
    	&& echo "[$(date +%T)] Directory ready: $RAW_DIR" >> startup_rnx_recovery.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $RAW_DIR" >> startup_rnx_recovery.log; \ 
    		echo "Critical Error 4ZABBIX: Check startup_rnx_recovery.log"; \
        	exit 1; \
    	   }
fi
# Temporary folder for processing
if [ ! -d "$TEMP_DIR" ]; then
    mkdir -p "$TEMP_DIR" \
    	&& echo "[$(date +%T)] Directory ready: $TEMP_DIR" >> startup_rnx_recovery.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $TEMP_DIR" >> startup_rnx_recovery.log; \
    		echo "Critical Error 4ZABBIX: Check startup_rnx_recovery.log"; \
        	exit 1; \
    	   }
fi
# Folder with output compressed rinex (.crx.gz)
if [ ! -d "$FINAL_DIR" ]; then
    mkdir -p "$FINAL_DIR" \
    	&& echo "[$(date +%T)] Directory ready: $FINAL_DIR" >> startup_rnx_recovery.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $FINAL_DIR" >> startup_rnx_recovery.log; \
    		echo "Critical Error 4ZABBIX: Check startup_rnx_recovery.log"; \
        	exit 1; \
    	   }
fi
# Folder with processed bin (and corrupt rnx if any) data. For further remove
if [ ! -d "$FINAL_DIR_BIN" ]; then
    mkdir -p "$FINAL_DIR_BIN" \
    	&& echo "[$(date +%T)] Directory ready: $FINAL_DIR_BIN" >> startup_rnx_recovery.log \
	|| {
		echo "[$(date +%T)] ERROR: $? Could not create $FINAL_DIR_BIN" >> startup_rnx_recovery.log; \
    		echo "Critical Error 4ZABBIX: Check startup_rnx_recovery.log"; \
        	exit 1; \
    	   }
fi

# Process each BIN file found in the record directory
for BINFILE in "$RAW_DIR"/*."$binEXT"; do
    [ -f "$BINFILE" ] || continue

    echo "Converting $(basename "$BINFILE")..."

    # Create a unique temp name for the RINEX fragment
    TEMP_OUT="$RAW_DIR/$(basename "$BINFILE" ."$binEXT").rnx"

    echo "[$(date +%T)] Runing convbin to convert $BINFILE to rnx" >> startup_rnx_recovery.log 
    convbin -ti 1.0000 -od -os -v 3.04 \
            -hr "UBX-ZED-F9P" \
            -ha "ANN-MB-00" \
            -hm "$STATION" \
            -o "$TEMP_OUT" "$BINFILE"

    # echo error if convbin fail
    if [ $? != 0 ]; then
	echo "[$(date +%T)] WARNING: $? Could not convert $BINFILE to rnx" >> startup_rnx_recovery.log 
  	echo "Warning 4ZABBIX: Check startup_rnx_recovery.log" 
	echo "There was an error with convbin. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> startup_rnx_recovery.log
     	mv -f "$BINFILE" "$FINAL_DIR_BIN" # move bin if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $BINFILE to archive folder" >> startup_rnx_recovery.log
  				echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"; \
		fi
    fi

done

# Merge and split into the 15-min grid. and move resulting rnx to $TEMP_DIR
# Note: Using $RAW_DIR/*.rnx to include ALL files in the batch.
echo "Merging and splitting into 15-min grid..."
gfzrnx -finp "$RAW_DIR/*.rnx" \
       -fout "$TEMP_DIR/::RX3::" \
       -split 900  \
       -f \
       -vo 3.04 \
       -chk >> startup_rnx_recovery.log 2>&1

# echo error if gfzrnx fail
if [ $? != 0 ]; then
	echo "[$(date +%T)] WARNING: $? gfzrnx could not make grid of rnx files" >> startup_rnx_recovery.log 
  	echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"
	echo "There was an error with gfzrnx. Move corrupt rnx files to archive folder" >> startup_rnx_recovery.log
     	mv -f "$RAW_DIR/*.rnx" "$FINAL_DIR_BIN" # move rnx ailes if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt rnx files to archive folder" >> startup_rnx_recovery.log
  				echo "Warning 4ZABBIX: Check startup_rnx_recovery.log" 
		fi

# preparing output files
else

    for RNX_FILE in "$TEMP_DIR"/*01S*.rnx; do
    	[ -f "$RNX_FILE" ] || continue

    	# Count the number of epochs (lines starting with '>')
    	EPOCH_COUNT=$(grep -c "^>" "$RNX_FILE")

	# Find the first line starting with '>' after the header ends
	FIRST_EPOCH=$(sed -n '/END OF HEADER/,$ { /^>/p; }' "$RNX_FILE" | head -n 1)
	# Extract components
	YEAR=$(echo "$FIRST_EPOCH" | awk '{print $2}')
	MONTH=$(echo "$FIRST_EPOCH" | awk '{print $3}')
	DAY=$(echo "$FIRST_EPOCH" | awk '{print $4}')
	HOUR=$(echo "$FIRST_EPOCH" | awk '{print $5}')
	MINUTE=$(echo "$FIRST_EPOCH" | awk '{print $6}')
	SECOND=$(echo "$FIRST_EPOCH" | awk '{print $7}' | cut -d'.' -f1) # Removes decimals

        # Check if the count is NOT less than nSEC2KEEP (Count >= nSEC2KEEP) and  not first or last 30 sec file
	if [[ "$EPOCH_COUNT" -ge "$nSEC2KEEP" ]] && \
   	! ( ( [[ 10#$MINUTE -eq 59 ]] && [[ 10#$SECOND -eq 30 ]] && [[ $EPOCH_COUNT -le 31 ]] ) || \
       	  ( [[ 10#$MINUTE -eq 0 ]] && [[ 10#$SECOND -eq 30 ]] && [[ $EPOCH_COUNT -le 31 ]] ) ); then

		echo "Processing $RNX_FILE with  $EPOCH_COUNT epochs" >> startup_rnx_recovery.log

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
			echo "[$(date +%T)] WARNING: RNX2CRC could not convert $NEW_FILE_NAMErnx to RNX" >> startup_rnx_recovery.log 
  			echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"; 
			echo "There was an error with RNX2CRX. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> startup_rnx_recovery.log
        		mv -f "$NEW_FILE_PATHrnx" "$FINAL_DIR_BIN" # move rnx if corrupt to arcchive folder
			if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMErnx to archive folder" >> startup_rnx_recovery.log
  				echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"; \
			fi
		else

    			# gzip crx to crx.gz
    			gzip -f ${NEW_FILE_PATHcrx}
        		if [ $? != 0 ]; then
	    			echo "There was an error with gzip. Move corrupt $NEW_FILE_NAMEcrx to archive folder" >> startup_rnx_recovery.log
				echo "[$(date +%T)] WARNING: gzip could not process $NEW_FILE_NAMEcrx" >> startup_rnx_recovery.log 
  				echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"; 
				echo "There was an error with gzip. Move $NEW_FILE_NAMEcrx to archive folder" >> startup_rnx_recovery.log
            			mv -f "$NEW_FILE_PATHcrx" "$FINAL_DIR_BIN" # move crx if corrupt to archive
				if [ $? != 0 ]; then
					echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMEcrx to archive folder" >> startup_rnx_recovery.log
  					echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"; \
				fi
        		fi
		fi

        else
		echo "Skipping $RNX_FILE: Only $EPOCH_COUNT epochs (less than $nSEC2KEEP)" >> startup_rnx_recovery.log
  	fi

    done

fi

## Cleanup temp files
echo "Remove temporary $TEMP_DIR folder" >> startup_rnx_recovery.log
rm -rf "$TEMP_DIR"
if [ $? != 0 ]; then
	echo "[$(date +%T)] Warning: $? Can not remove temporary $TEMP_DIR folder" >> startup_rnx_recovery.log
  	echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"
fi

# Move bin files if not opened by str2str
echo "Move processed bin file(s) to archive folder" >> startup_rnx_recovery.log
for BINFILE in "$RAW_DIR"/*."$binEXT"; do
	mv -f "$BINFILE" "$FINAL_DIR_BIN" # move processed bin file to archive folder
	if [ $? != 0 ]; then
		echo "[$(date +%T)] Warning: $? Can not move processed $BINFILE to archive folder" >> startup_rnx_recovery.log
		echo "Warning 4ZABBIX: Check startup_rnx_recovery.log"
	fi
done

echo "satartup processing of files in $RAW_DIR folder are finished" >> startup_rnx_recovery.log

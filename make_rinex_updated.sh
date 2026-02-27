#!/bin/bash

# The script takes the UBX bin recorded data and translates it into a RINEX version 3 file

# ----- FUNCTIONS SECTION ----------------------------------------------------------------

# ----- FUNCTION 1------------------------------------------------------------------------
#
# Is file ready ?
# return:
# 0 (true) - file is ready
# 1 (false) - file not exist
# 2 (false) - file is open by some process
is_file_ready() {
    local target_file="$1"

    # File not exist
    if [[ ! -f "$target_file" ]]; then
        return 1
    fi

    # File locked by some process
    if lsof -t "$target_file" >/dev/null 2>&1; then
        return 2
    fi

    # File exist and not locked
    return 0
}


# ----- FUNCTION 2 -----------------------------------------------------------------------
#
# log_errors function with multiple arguments
log_errors() {
    # Initialize local variables with default values
    local err_level="0"
    local err_message="OK"
    local err_output="OK"

    # Loop through all arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --err_level)
                err_level="$2"
                shift 2
                ;;
            --err_message)
                err_mesage="$2"
                shift 2
                ;;
            --err_output)
                err_output="$2"
                shift 2
                ;;
            *)
                # Handle unknown options
                echo "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Logic using the arguments
    echo "Error level: ${err_level} (0 - OK, 1 - critical error, 2 - warning)"
    echo "Error message: ${err_message}"
    echo "Error output: ${err_output}"

    # SOME PROCESSING: TBD ...
}

# ----- END OF FUNCTIONS SECTION-----------------------------------------------------------

# Configuration for manual input
# rpiUSER="alexk" # user name
# STATION="ANTC" # station name
# binEXT="ubx" # bin file extention
nSEC2KEEP=1 # if 15 min rinex file conatins less seconds than this value not keep such file

#  Definition of folders
RAW_DIR="${HOME}/record" # Temporary folder for processing
DATA_DIR="${HOME}/data"  # Folder with output compressed rinex (.crx.gz) 
ARCHIVE_DIR="${HOME}/archive" # Folder with processed bin (and corrupt rnx if any) data. For further remove

# Creation of folders
TEMP_DIR="$(mktemp -d -t TEMP_DIR_XXXXXX)"
# Auto removing if  exit or interruption 
trap 'rm -rf "${TEMP_DIR}"' EXIT


# Folder with output compressed rinex (.crx.gz)
if [[ ! -d "$DATA_DIR" ]]; then
    mkdir -p "$DATA_DIR" \
	|| {
#		echo "[$(date +%T)] ERROR: $? Could not create $DATA_DIR" >> make_rinex_updated.log; \
                notify_zabbix 1 "[$(date +%T)] make_15min_rinex.sh ERROR: Can not create $DATA_DIR"
        	exit 1; \
    	   }
fi
# Folder with processed bin (and corrupt rnx if any) data. For further remove
if [[ ! -d "$ARCHIVE_DIR" ]]; then
    mkdir -p "$ARCHIVE_DIR" \
	|| {
#		echo "[$(date +%T)] ERROR: $? Could not create $ARCHIVE_DIR" >> make_rinex_updated.log; \
                notify_zabbix 1 "[$(date +%T)] make_15min_rinex.sh ERROR: Can not create $ARCHIVE_DIR"
        	exit 2; \
    	   }
fi

# Date/time of run
echo "$(date +%T) Start bin files processing" >> make_rinex_updated.log

# First, what quarter of the hour is it.
QUARTER=$1

# Get parts of the date and time
if [[ "10#$QUARTER" -lt 4 ]]; then

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
    [[ -f "$BINFILE" ]] || continue

    echo "Converting $(basename "$BINFILE")..."

    # Create a unique temp name for the RINEX fragment
    TEMP_OUT="$RAW_DIR/$(basename "$BINFILE" ."$binEXT").rnx"

    echo "[$(date +%T)] Runing convbin to convert $BINFILE to rnx" >> make_rinex_updated.log 
    convbin -ti 1.0000 -od -os -v 3.04 \
            -hr "UBX-ZED-F9P" \
            -ha "ANN-MB-00" \
            -hm "$STATION" \
            -o "$TEMP_OUT" "$BINFILE"

    # echo error if convbin fail
    if [[ $? != 0 ]]; then
	echo "[$(date +%T)] WARNING: $? Could not convert $BINFILE to rnx" >> make_rinex_updated.log 
        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? convbin can not convert $BINFILE to rnx"
	echo "There was an error with convbin. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_rinex_updated.log
     	mv -f "$BINFILE" "$ARCHIVE_DIR" # move bin if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $BINFILE to archive folder" >> make_rinex_updated.log
                		notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not not move corrupt $BINFILE to archive folder"
		fi
    fi

done

if [[ "10#$QUARTER" -eq 10#0 ]]; then

# Merge and split into the 15-min grid. and move resulting rnx to $TEMP_DIR
# Note: Using $RAW_DIR/*.rnx to include ALL files in the batch.
echo "Merging and splitting into 15-min grid..."
gfzrnx -finp "$RAW_DIR/*.rnx" \
       -fout "$TEMP_DIR/::RX3::" \
       -split 900  \
       -f \
       -vo 3.04 \
       -chk >> make_rinex_updated.log 2>&1

else

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
           -d 900 -f -vo 3.04 -chk >> make_rinex_updated.log 2>&1
fi


# echo error if gfzrnx fail
if [[ $? != 0 ]]; then
	echo "[$(date +%T)] WARNING: $? gfzrnx could not merge rnx files" >> make_rinex_updated.log 
        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? gfzrnx can not make grid of rnx files"
	echo "There was an error with gfzrnx. Move corrupt rnx files to archive folder" >> make_rinex_updated.log
     	mv -f "$RAW_DIR/*.rnx" "$ARCHIVE_DIR" # move rnx ailes if corrupt to archive folder
		if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt rnx files to archive folder" >> make_rinex_updated.log
        			notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not move rnx files to archive folder"
		fi

# preparing output files
else

    for RNX_FILE in "$TEMP_DIR"/*01S*.rnx; do
    	[[ -f "$RNX_FILE" ]] || continue

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

    # Check if the EPOCH_COUNT>=nSEC2KEEP for QUARTER 1,2,3,4 or
    # Not first 30-31 sec or last 30-31 sec on the edge of the hour for QUARTER 0
    if (( (10#$QUARTER > 10#0 && 10#$EPOCH_COUNT >= 10#$nSEC2KEEP) || (10#$QUARTER == 10#0 && !( (10#$EPOCH_COUNT <=31 && 10#$MINUTE == 59) || (10#$EPOCH_COUNT <=31 && 10#$MINUTE == 10#0) ) ) )); then

        ## Check if the count is NOT less than nSEC2KEEP (Count >= nSEC2KEEP)
        #if [[ "$EPOCH_COUNT" -ge "$nSEC2KEEP" ]]; then

		echo "Processing $RNX_FILE with  $EPOCH_COUNT epochs" >> make_rinex_updated.log

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
    		NEW_FILE_PATHrnx="$DATA_DIR/$NEW_FILE_NAMErnx"
    		NEW_FILE_PATHcrx="$DATA_DIR/$NEW_FILE_NAMEcrx"

    		# PERFORM RENAME
    		mv "$RNX_FILE" "$NEW_FILE_PATHrnx"

    		# Convert to crx
    		RNX2CRX -d ${NEW_FILE_PATHrnx}
		if [ $? != 0 ]; then
			echo "There was an error: $? with RNX2CRC"
			echo "[$(date +%T)] WARNING: RNX2CRC could not convert $NEW_FILE_NAMErnx to RNX" >> make_rinex_updated.log 
		        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? RNX2CRX can not convert $NEW_FILE_NAMErnx to crx"
			echo "There was an error with RNX2CRX. Move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_rinex_updated.log
        		mv -f "$NEW_FILE_PATHrnx" "$ARCHIVE_DIR" # move rnx if corrupt to arcchive folder
			if [ $? != 0 ]; then
				echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMErnx to archive folder" >> make_rinex_updated.log
			        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not convert moce $NEW_FILE_NAMErnx to archive folder"
			fi
		else

    			# gzip crx to crx.gz
    			gzip -f ${NEW_FILE_PATHcrx}
        		if [ $? != 0 ]; then
	    			echo "There was an error with gzip. Move corrupt $NEW_FILE_NAMEcrx to archive folder" >> make_rinex_updated.log
				echo "[$(date +%T)] WARNING: gzip could not process $NEW_FILE_NAMEcrx" >> make_rinex_updated.log 
			        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not move corrupt $NEW_FILE_NAMEcrx to archive folder"
				echo "There was an error with gzip. Move $NEW_FILE_NAMEcrx to archive folder" >> make_rinex_updated.log
            			mv -f "$NEW_FILE_PATHcrx" "$ARCHIVE_DIR" # move crx if corrupt to archive
				if [ $? != 0 ]; then
					echo "[$(date +%T)] Can not move corrupt $NEW_FILE_NAMEcrx to archive folder" >> make_rinex_updated.log
					notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not move $NEW_FILE_NAMEcrx to archive folder"
				fi
        		else
				notify_zabbix 0 "[$(date +%T)] make_15min_rinex.sh CANCELATION: script finished smootly"
        		fi
		fi

        else
		echo "Skipping $RNX_FILE: Only $EPOCH_COUNT epochs (less than $nSEC2KEEP)" >> make_rinex_updated.log
  	fi

    done

fi

# Remove processed rnx files if loop processing
if [[ "10#$QUARTER" -gt 10#0 ]]; then
    echo "Remove processed rnx files if loop processin"
    echo "Remove processed rnx files" >> make_rinex_updated.log
    rm -f "$RAW_DIR"/*.rnx
    if [[ $? != 0 ]]; then
		echo "[$(date +%T)] Warning: $? Can not remove processed rnx files" >> make_rinex_updated.log
    	    notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not remove rocessed rnx files"
    fi
fi

## Cleanup temp files
echo "Remove temporary $TEMP_DIR folder" >> make_rinex_updated.log
rm -rf "$TEMP_DIR"
if [[ $? != 0 ]]; then
	echo "[$(date +%T)] Warning: $? Can not remove temporary $TEMP_DIR folder" >> make_rinex_updated.log
        notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not remove $TEMP_DIR folder"
fi

# Move bin files if not opened by str2str
echo "Move processed bin file(s) to archive folder" >> make_rinex_updated.log
for BINFILE in "$RAW_DIR"/*."$binEXT"; do
	if is_file_ready "$BINFILE"; then
		mv -f "$BINFILE" "$ARCHIVE_DIR" # move processed bin file to archive folder
		if [[ $? != 0 ]]; then
			echo "[$(date +%T)] Warning: $? Can not move processed $BINFILE to archive folder" >> make_rinex_updated.log
	        	notify_zabbix 2 "[$(date +%T)] make_15min_rinex.sh WARNING: $? Can not move processed  $BINFILE to archive folder"
		fi
	fi
done

echo "15-min file(s) ${NEW_FILE_NAMEcrxgz} (with more than: ${nSEC2KEEP} 1S EPOCHs) are cleaned and ready" >> make_rinex_upd

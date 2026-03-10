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
    if [[ ! -f "${target_file}" ]]; then
        return 1
    fi

    # File locked by some process
    if lsof -t "${target_file}" >/dev/null 2>&1; then
        return 2
    fi

    # File exist and not locked
    return 0
}


# ----- FUNCTION 2 -----------------------------------------------------------------------
#
# log function with multiple arguments
log() {
    # Initialize local variables with default values
    local err_level=""  # 0 - Ok, 1 - warning, 2 - error, 3 - critical error (require exit from script)
    local err_message="" # Information message
    local err_output="" #  Text output proused by target utility if any

    # Loop through all arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -l)
                err_level="$2"
                shift 2
                ;;
            -m)
                err_message="$2"
                shift 2
                ;;
            -o)
                err_output="$2"
                shift 2
                ;;
            *)
                # Handle unknown options
                return 1
                ;;
        esac
    done

    # Logic using the arguments
    echo "${err_message}"
    # echo "${err_output}" # TBD what to do with this
    # SOME PROCESSING: TBD ...
}

# ----- FUNCTION 3 -----------------------------------------------------------------------
#
# Show Help on the screen
printHelp() {
  cat << EOF
==============================================================================
GNSS BINARY TO RINEX 3.0 CONVERSION SCRIPT
==============================================================================
This script automates the conversion of raw GNSS binary data (e.g., .ubx) 
into RINEX version 3.04 format. It handles file merging, 15-minute 
interval splitting, and compression (.crx.gz).

USAGE EXAMPLE:
  $0 --quarter 1 --station "ANTC" --extension "ubx"

MANDATORY PARAMETERS:
  -q    Processing window: 0 (Startup), 1, 2, 3, or 4
  -s    Station ID: 4 Capital Characters (e.g., ANTC)
  -e    Raw file extension: e.g., ubx, bin, dat

OPTIONAL PARAMETERS:
  -ep   Min epochs to keep a file (Default: 0 - keeps all)
  -h    Show this help documentation

QUARTER REFERENCE GUIDE:
  The --quarter parameter defines the processing time window:
  1: HH:00:00 to HH:15:00
  2: HH:15:00 to HH:30:00
  3: HH:30:00 to HH:45:00
  4: HH:45:00 to (HH+1):00:00
  0: Startup Mode. Processes all existing files in the record folder.

PROCESSING LOGIC:
  1. Conversion: Uses convbin for initial RINEX fragments.
  2. Splitting:  Uses gfzrnx for precise 15-minute grid alignment.
  3. Validation: Filters files by the --epoch threshold.
  4. Renaming:   Applies RINEX 3 naming conventions using Station ID.
  5. Compression: Converts .rnx to .crx (Hatanaka) and applies gzip.
  6. Archive:    Moves processed binary files to ~/archive (if not locked).
==============================================================================
EOF
}

# ----- END OF FUNCTIONS SECTION-----------------------------------------------------------

# Default parameters
QUARTER="" #QUARTER of script call (0 - at startup, 1 - 16 min, 2 - 31 min, 3 - 46 min, 4 -1 min)
STATION="" # station name
binEXT="" # bin file extention
### STARTP BLOCK - HAVE TO BE SET MANUAL !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
nEPOCH2KEEP=0 # if 15 min rinex file conatins less EPOCHS than this value not keep such file
SAMPLING=1 # sampling rate of GNSS receiver
### STOP BLOCK - HAVE TO BE SET MANUAL !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
EPOCH30SEC=$((${SAMPLING}*30+1)) # Number of epoch in 30 sec interval (for removing diring startup processing)
log -l 0 -m "In 30 seconds should exists ${EPOCH30SEC} epochs or less" -o ""
RNX2MRGprev=0 # Initial number of rnx files berore convbin to merge with gfzrnx
RNX2MRGconv=0 # Number of rnx files produced by convbin to merge with gfzrnx
RNXMRG=0 # Flag for merging rnx before splitting (0 - single file 1 - merged file (splitting can be not good)

# --- Loop through arguments (your current code) ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        -q)   QUARTER="$2";   shift 2 ;;
        -s)   STATION="$2";   shift 2 ;;
        -e)   binEXT="$2";    shift 2 ;;
        -ep)  nEPOCH2KEEP="$2"; shift 2 ;;
        -h)   printHelp;      exit 1  ;;
        *) log -l 3 -m  "Unknown option: $1" -o ""; printHelp; exit 2 ;;
    esac
done

# ---  Validation Check (The part you need) ---
MISSING=""
[[ -z "${QUARTER}" ]] && MISSING+="--q "
[[ -z "${STATION}" ]] && MISSING+="--s "
[[ -z "${binEXT}"  ]] && MISSING+="--e "

if [[ -n "${MISSING}" ]]; then
    log -l 3 -m "ERROR: Missing mandatory parameters: ${MISSING}" -o ""
    printHelp
    exit 3
fi

log -l 0 -m "Number of parameters for Station: $STATION is correct" -o ""

# Logic using the arguments
log -l 0 -m "Qaurter: ${QUARTER} (0 - startup, 1-4 - some quarter)" -o ""
log -l 0 -m "Station: ${STATION}" -o ""
log -l 0 -m "BIN file extension: ${binEXT}" -o ""
log -l 0 -m "Number of epoch to keep in rinex file: ${nEPOCH2KEEP} or more" -o ""

# SET TZ to UTC
export TZ=UTC

#  Definition of folders
RAW_DIR="${HOME}/record" # Temporary folder for processing
DATA_DIR="${HOME}/data"  # Folder with output compressed rinex (.crx.gz) 
ARCHIVE_DIR="${HOME}/archive" # Folder with processed bin (and corrupt rnx if any) data. For further remove

# Creation of folders
# Temporary folder
TEMP_DIR="$(mktemp -d -t make_rinex_XXXXXX)"
# Auto removing if  exit or interruption 
#trap 'rm -rf "${TEMP_DIR}"' EXIT

# Folder with output compressed rinex (.crx.gz)
if [[ ! -d "${DATA_DIR}" ]]; then
    mkdir -p "${DATA_DIR}" \
	|| {
                log -l 3 -m "ERROR: $? Could not create ${DATA_DIR}" -o ""
        	exit 3; \
    	   }
fi

# Folder with processed bin (and corrupt rnx if any) data. For further remove
if [[ ! -d "${ARCHIVE_DIR}" ]]; then
    mkdir -p "${ARCHIVE_DIR}" \
	|| {
                log -l 3 -m "ERROR: $? Could not create ${ARCHIVE_DIR}" -o ""
        	exit 4; \
    	   }
fi

# Date/time of run
log -l 0 -m "Start bin files processing" -o ""

# Get parts of the date and time
if [[ "${QUARTER}" -lt 4 ]]; then

    # For actual time: YEAR MONTH DAY DOY HOUR
    read -r YEARPREV MONTHPREV DAYPREV DOYPREV HOURPREV <<< "$(date -d "-1 hour" "+%Y %m %d %j %H")"
    read -r YEAR MONTH DAY DOY HOUR <<< "$(date "+%Y %m %d %j %H")"

else

    # For actual time -1 hour: YEAR MONTH DAY DOY HOUR
    read -r YEAR MONTH DAY DOY HOUR <<< "$(date -d "-1 hour" "+%Y %m %d %j %H")"
    read -r YEARNEXT MONTHNEXT DAYNEXT DOYNEXT HOURNEXT <<< "$(date "+%Y %m %d %j %H")"

fi

# Check number of rnx files in RAW_DIR before convbin if any
rnx_files=("${RAW_DIR}"/*.rnx)
RNX2MRGprev=${#rnx_files[@]}
if [[ ! -e "${rnx_files[0]}" ]]; then
    RNX2MRGprev=0
fi

if [[ "${QUARTER}" -eq 0 ]]; then # Convbin run at startup

    # Process each BIN file found in the record directory at startup
    for BINFILE in "${RAW_DIR}"/*."${binEXT}"; do
        [[ -f "${BINFILE}" ]] || continue

        # Create a unique temp name for the RINEX fragment
        TEMP_OUT="${RAW_DIR}/$(basename "${BINFILE}" ."${binEXT}").rnx"

	log -l 0 -m "Runing convbin to convert ${BINFILE} to rnx" -o ""

        # Run convbin for processing at startup
        # capture convbin stderr but strip all repetitive stuff ending with \r CR
        ~/bin/convbin -ti 1.0000 -od -os -v 3.04 -hm "${STATION}" -o "${TEMP_OUT}" "${BINFILE}" 2>${TEMP_DIR}/convbin.log

    	# Error if convbin fail
    	if [[ $? -ne 0 ]]; then
	    # Check if the error log file actually exists and is not empty (-s)
	    if [[ -s "${TEMP_DIR}/convbin.log" ]]; then
    		# Read the file if it has content
    		ERR_OUT=$(cat "${TEMP_DIR}/convbin.log" | tr -d '\n\r')
	    else
    		# Fallback if the command failed but the log is missing/empty
    		ERR_OUT="Unknown convbin error (No log output generated)"
	    fi

        	log -l 2 -m "WARNING: $? Could not convert ${BINFILE} to rnx" -o "${ERR_OUT}"
		log -l 2 -m "There was an error: $? with convbin. Move corrupt ${BINFILE} to archive folder" -o ""
     		mv -f "${BINFILE}" "${ARCHIVE_DIR}" # move bin if corrupt to archive folder
		if [[ $? -ne 0 ]]; then
              		log -l 2 -m "Can not move corrupt ${BINFILE} to archive folder" -o ""
		fi
    	else
		log -l 0 -m "Convbin successfully converted ${BINFILE} to rnx" -o ""
    	fi
    done

else # Convbin run in loop

    # preapare start-stop date and time for convbin in loop mode
    case ${QUARTER} in

        1) # QUATER 1
        START_DATE="${YEARPREV}/${MONTHPREV}/${DAYPREV}"
        START_TIME="${HOURPREV}:59:59"
        STOP_DATE="${YEAR}/${MONTH}/${DAY}"
        STOP_TIME="${HOUR}:15:01"
        ;;

        2) # QUATER 2
        START_DATE="${YEAR}/${MONTH}/${DAY}"
        START_TIME="${HOUR}:14:59"
        STOP_DATE="${YEAR}/${MONTH}/${DAY}"
        STOP_TIME="${HOUR}:30:01"
        ;;

        3) # QUATER 3
        START_DATE="${YEAR}/${MONTH}/${DAY}"
        START_TIME="${HOUR}:29:59"
        STOP_DATE="${YEAR}/${MONTH}/${DAY}"
        STOP_TIME="${HOUR}:45:01"
        ;;

        4) # QUATER 4
        START_DATE="${YEAR}/${MONTH}/${DAY}"
        START_TIME="${HOUR}:44:59"
        STOP_DATE="${YEARNEXT}/${MONTHNEXT}/${DAYNEXT}"
        STOP_TIME="${HOURNEXT}:00:01"
        ;;

    esac

    # Process each BIN file found in the record directory in loop mode 
    for BINFILE in "${RAW_DIR}"/*."${binEXT}"; do
        [[ -f "${BINFILE}" ]] || continue

        # Create a unique temp name for the RINEX fragment
        TEMP_OUT="${RAW_DIR}/$(basename "${BINFILE}" ."${binEXT}").rnx"

	log -l 0 -m "Runing convbin to convert ${BINFILE} to rnx" -o ""

        # Run convbin for processing at startup
        # capture convbin stderr but strip all repetitive stuff ending with \r CR
        ~/bin/convbin -ts "${START_DATE}" "${START_TIME}" -te "${STOP_DATE}" "${STOP_TIME}" \
                      -ti 1.0000 -od -os -v 3.04 -hm "${STATION}" -o "${TEMP_OUT}" "${BINFILE}" 2>${TEMP_DIR}/convbin.log

    	# Error if convbin fail
    	if [[ $? -ne 0 ]]; then
		# Check if the error log file actually exists and is not empty (-s)
		if [[ -s "${TEMP_DIR}/convbin.log" ]]; then
    		    # Read the file if it has content
    		    ERR_OUT=$(cat "${TEMP_DIR}/convbin.log" | tr -d '\n\r')
		else
    		    # Fallback if the command failed but the log is missing/empty
    		    ERR_OUT="Unknown convbin error (No log output generated)"
		fi
        	log -l 2 -m "WARNING: $? Could not convert ${BINFILE} to rnx" -o "ERR_OUT"
		log -l 2 -m "There was an error: $? with convbin. Move corrupt ${BINFILE} to archive folder" -o ""
     		mv -f "${BINFILE}" "${ARCHIVE_DIR}" # move bin if corrupt to archive folder
		if [[ $? -ne 0 ]]; then
              		log -l 2 -m "Can not move corrupt ${BINFILE} to archive folder" -o ""
		fi
    	else
		log -l 0 -m "Convbin successfully converted ${BINFILE} to rnx" -o ""
    	fi
    done

fi


# Check number of rnx files in RAW_DIR after convbin
rnx_files=("${RAW_DIR}"/*.rnx)
RNX2MRGconv=${#rnx_files[@]}
if [[ ! -e "${rnx_files[0]}" ]]; then
    RNX2MRGconv=0
    log -l 2 -m "WARNING: no rnx files in ${RAW_DIR} folder for gfzrnx processing" -o ""
fi


# Process rnx file prepared by convbin
if [[ "${QUARTER}" -eq 0 ]]; then       # for QUARTER=0 - at startup


    # Prepare single rnx file from one or multiple files for further splitting by gfzrnx
    if [[ "${RNX2MRGconv}" -eq 1 ]]; then # one file to copy to merged.rnx

        log -l 0 -m "Only one rnx file selected for furthure splitting by gfzrnx" -o ""
        cp "${rnx_files[0]}" "${RAW_DIR}/merged.rnx"

    else # merge all existing rnx files to merged.rnx

        log -l 0 -m "Several rnx files merged to one file for furthure splitting by gfzrnx" -o ""
        ~/bin/gfzrnx -finp "${RAW_DIR}"/*.rnx \
          -fout "${RAW_DIR}/merged.rnx" \
          -kv \
          -f \
          -vo 3.04 \
          -errlog ${TEMP_DIR}/gfz-error.log \
          -chk

        # Error if gfzrnx fail to merge file in single rnx file
        if [[ $? -ne 0 ]]; then
	    # Check if the error log file actually exists and is not empty (-s)
	    if [[ -s "${TEMP_DIR}/gfz-error.log" ]]; then
    		# Read the file if it has content
    		ERR_OUT=$(cat "${TEMP_DIR}/gfz-error.log" | tr -d '\n\r')
	    else
    		# Fallback if the command failed but the log is missing/empty
    		ERR_OUT="Unknown gfzrnx error (No log output generated)"
	    fi
	    log -l 2 -m "WARNING: $? gfzrnx could not merge rnx files to single file" -o "ERR_OUT"
	    log -l 2 -m "There was an error with gfzrnx. Move corrupt rnx files to archive folder" -o ""
	    mv -f "${RAW_DIR}"/*.rnx "${ARCHIVE_DIR}" # move rnx files if corrupt to archive folder
	    if [ $? != 0 ]; then
		log -l 2 -m "Can not move corrupt rnx files to archive folder" -o ""
	    fi
	else
            MRGRNX=1 # Set flag of rnx to 1  (merging happend) 
	fi

    fi

    # Split into the 15-min grid and move resulting rnx to $TEMP_DIR
    # Note: Using "$RAW_DIR"/*.rnx to include ALL files in the batch.
    log -l 0 -m "Merging and splitting into 15-min grid..." -o ""
    ~/bin/gfzrnx -finp "${RAW_DIR}"/merged.rnx \
        -fout "${TEMP_DIR}/::RX3::" \
        -split 900 \
        -kv \
        -f \
        -vo 3.04 \
        -crux ${HOME}/etc/crux.txt \
        -errlog ${TEMP_DIR}/gfz-split-error.log \
        -chk

else  # For QUARTER>0 - loop processing

    # Preapare single rnx file from one or multiple files for further splitting by gfzrnx while loop processing
    if (( ( QUARTER < 4 && RNX2MRGconv == 1 ) || ( QUARTER == 4 && RNX2MRGprev == 0 && RNX2MRGconv == 2) )); then # one file to copy to merged.rnx

        log -l 0 -m "Only one rnx (${RNX2MRGconv}) file selected for furthure loop processing by gfzrnx" -o ""
        cp "${rnx_files[0]}" "${RAW_DIR}/merged.rnx"

    else # merge all existing rnx files to merged.rnx

        log -l 0 -m "Several rnx files merged to one file for furthure loop processing by gfzrnx" -o ""
        ~/bin/gfzrnx -finp "${RAW_DIR}"/*.rnx \
          -fout "${RAW_DIR}/merged.rnx" \
          -kv \
          -f \
          -vo 3.04 \
          -errlog ${TEMP_DIR}/gfz-error.log \
          -chk

        # Error if gfzrnx fail to merge file in single rnx file while loop processing
        if [[ $? -ne 0 ]]; then
	    # Check if the error log file actually exists and is not empty (-s)
	    if [[ -s "${TEMP_DIR}/gfz-error.log" ]]; then
    		# Read the file if it has content
    		ERR_OUT=$(cat "${TEMP_DIR}/gfz-error.log" | tr -d '\n\r')
	    else
    		# Fallback if the command failed but the log is missing/empty
    		ERR_OUT="Unknown gfzrnx error (No log output generated)"
	    fi
	    log -l 2 -m "WARNING: $? gfzrnx could not merge rnx files to single file while loop processing" -o "ERR_OUT"
	    log -l 2 -m "There was an error with gfzrnx. Move corrupt rnx files to archive folder" -o ""
	    mv -f "${RAW_DIR}"/*.rnx "${ARCHIVE_DIR}" # move rnx files if corrupt to archive folder
	    if [ $? != 0 ]; then
		log -l 2 -m "Can not move corrupt rnx files to archive folder" -o ""
	    fi
	else
            MRGRNX=1 # Set flag of rnx to 1  (merging happend) 
	fi

    fi

    # preapare start time for gfzrnx
    case ${QUARTER} in
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

    # Merge and split into the 15-min rnx file with START_TIME + 900 sec
    # and move resulting rnx to $TEMP_DIR
    log -l 0 -m "Merging and splitting into 15-min file start time: ${START_TIME}" -o ""
    ~/bin/gfzrnx -finp "${RAW_DIR}"/merged.rnx \
           -fout "${TEMP_DIR}/::RX3::" \
           -epo_beg "${START_TIME}" \
           -d 900 \
           -f \
           -vo 3.04 \
           -crux $HOME/etc/crux.txt \
           -errlog ${TEMP_DIR}/gfz-split-error.log \
           -chk
fi


# Error if gfzrnx fail while making output file(s)
if [[ $? -ne 0 ]]; then
	    # Check if the error log file actually exists and is not empty (-s)
	    if [[ -s "${TEMP_DIR}/gfz-split-error.log" ]]; then
    		# Read the file if it has content
    		ERR_OUT=$(cat "${TEMP_DIR}/gfz-split-error.log" | tr -d '\n\r')
	    else
    		# Fallback if the command failed but the log is missing/empty
    		ERR_OUT="Unknown gfzrnx error (No log output generated)"
	    fi
        log -l 2 -m "WARNING: $? gfzrnx could not make output rnx file(s) from merged rnx" -o "ERR_OUT"
	log -l 2 -m "There was an error with gfzrnx. Move corrupt rnx files to archive folder" -o ""
     	mv -f "${RAW_DIR}"/*.rnx "${ARCHIVE_DIR}" # move rnx files if corrupt to archive folder
		if [ $? != 0 ]; then
			log -l 2 -m "Can not move corrupt rnx files to archive folder" -o ""
		fi

# preparing output files
else

    # Delete merged.rnx file from RAW_DIR folder after processing
    log -l 0 -m  "Remove merged.rnx file after processing" -o ""
    rm -f "${RAW_DIR}"/merged.rnx
    if [[ $? -ne 0 ]]; then
	log -l 2 -m  "WARNING: $? Can not remove processed rnx files" -o ""
    fi

    for RNX_FILE in "${TEMP_DIR}"/*.rnx; do
    	[[ -f "${RNX_FILE}" ]] || continue

    	# Count the number of epochs (lines starting with '>')
    	EPOCH_COUNT=$(grep -c "^>" "${RNX_FILE}")

	if [[ "${QUARTER}" -eq 0 ]]; then
		# Find the first line starting with '>' after the header ends
	    	FIRST_EPOCH=$(sed -n '/END OF HEADER/,$ { /^>/p; }' "${RNX_FILE}" | head -n 1)
	    	# Extract components
	    	YEAR=$(echo "${FIRST_EPOCH}" | awk '{print $2}')
	    	MONTH=$(echo "${FIRST_EPOCH}" | awk '{print $3}')
    		DAY=$(echo "${FIRST_EPOCH}" | awk '{print $4}')
	    	HOUR=$(echo "${FIRST_EPOCH}" | awk '{print $5}')
	    	MINUTE=$(echo "${FIRST_EPOCH}" | awk '{print $6}')
    		SECOND=$(echo "${FIRST_EPOCH}" | awk '{print $7}' | cut -d '.' -f1) # Removes decimals
        else
		MINUTE=0
        fi

    	# Check if the EPOCH_COUNT>=nEPOCH2KEEP for QUARTER 1,2,3,4 or
    	# Not first 30-31 sec or last 30-31 sec on the edge of the hour for QUARTER 0
    	if (( (QUARTER > 0 && EPOCH_COUNT > nEPOCH2KEEP) || (QUARTER == 0 && !( (EPOCH_COUNT <= EPOCH30SEC && MINUTE == 59) || (EPOCH_COUNT <= EPOCH30SEC && MINUTE == 0) ) ) )); then

		log -l 0 -m  "Processing ${RNX_FILE} with  ${EPOCH_COUNT} epochs" -o ""

    		# Get the base filename (e.g., 202200XXX_R_20220410045_15M_01S_MO.rnx)
    		BASE_NAME=$(basename "${RNX_FILE}")

    		# DYNAMIC RENAMING
    		# We take everything from the 10th character onwards and
    		# prepend your $STATION and "00CAN"
    		# The 'cut -c 10-' command removes the first 9 characters (the wrong ID)
    		SUFFIX=$(echo "${BASE_NAME}" | cut -c 10-)
    		NEW_FILE_NAME="${STATION}00CAN${SUFFIX}"
      		# Extract the part before the last dot
		BASE_FILE_NAME="${NEW_FILE_NAME%.*}"
		# Extract the extension (including the dot)
		EXT_NAME="${NEW_FILE_NAME##*.}"

		# New file names and file names with path
                # If gfzrnx make correct splitting from single rnx file
		if [[ "${MRGRNX}" -eq 0 ]]; then
                    log -l 0 -m "Output rnx file made from single rnx" -o ""
		    NEW_FILE_NAMErnx="${BASE_FILE_NAME}.${EXT_NAME}"
    		    NEW_FILE_NAMEcrx="${BASE_FILE_NAME}.crx"
    		    NEW_FILE_NAMEcrxgz="${BASE_FILE_NAME}.crx.gz"
                # If gfzrnx make splitting from merged rnx file (may be not correct output rnx
		else
                    log -l 0 -m "Output rnx file made from merged rnx files (m added to file name)" -o ""
		    NEW_FILE_NAMErnx="${BASE_FILE_NAME}m.${EXT_NAME}"
    		    NEW_FILE_NAMEcrx="${BASE_FILE_NAME}m.crx"
    		    NEW_FILE_NAMEcrxgz="${BASE_FILE_NAME}m.crx.gz"
		fi
    		NEW_FILE_PATHrnx="${DATA_DIR}/${NEW_FILE_NAMErnx}"
    		NEW_FILE_PATHcrx="${DATA_DIR}/${NEW_FILE_NAMEcrx}"

    		# PERFORM RENAME
    		mv "${RNX_FILE}" "${NEW_FILE_PATHrnx}"

    		# Convert to crx
    		~/bin/RNX2CRX -d "${NEW_FILE_PATHrnx}" 2>${TEMP_DIR}/hatanaka-error.log
		if [[ $? -ne 0 ]]; then
		    # Check if the error log file actually exists and is not empty (-s)
		    if [[ -s "${TEMP_DIR}/hatanaka-error.log" ]]; then
    			# Read the file if it has content
    			ERR_OUT=$(cat "${TEMP_DIR}/hatanaka-error.log" | tr -d '\n\r')
		    else
    			# Fallback if the command failed but the log is missing/empty
    			ERR_OUT="Unknown CRX2RNX error (No log output generated)"
		    fi

			log -l 2 -m " WARNING: $? with RNX2CRX could not convert ${NEW_FILE_NAMErnx} to rnx" -o "${ERR_OUT}"
			log -l 2 -m  "There was an error with RNX2CRX. Move corrupt ${NEW_FILE_NAMErnx} to archive folder" -o ""
        		mv -f "${NEW_FILE_PATHrnx}" "${ARCHIVE_DIR}" # move rnx if corrupt to archive folder
			if [[ $? -ne 0 ]]; then
				log -l 2 -m  "Can not move corrupt ${NEW_FILE_NAMErnx} to archive folder" -o ""
			else
				log -l 0 -m  "Corrupt ${NEW_FILE_NAMErnx} moved to archive folder" -o ""
			fi
		else

    			# gzip crx to crx.gz
    			gzip -f "${NEW_FILE_PATHcrx}"
        		if [[ $? -ne 0 ]]; then
				log -l 2 -m  "WARNING: $? gzip could not process ${NEW_FILE_NAMEcrx}" -o ""
				log -l 2 -m "There was an error with gzip. Move ${NEW_FILE_NAMEcrx} to archive folder" -o ""
            			mv -f "${NEW_FILE_PATHcrx}" "${ARCHIVE_DIR}" # move crx if corrupt to archive
				if [ $? != 0 ]; then
					log -l 2 -m  "Can not move corrupt ${NEW_FILE_NAMEcrx} to archive folder" -o ""
        			else
					log -l 0 -m  "Corrupt ${NEW_FILE_NAMErnx} moved to archive folder" -o ""
        			fi
			fi
		fi

        else
		log -l 2 -m "Skipping ${RNX_FILE}: Only ${EPOCH_COUNT} epochs (less than $nEPOCH2KEEP)" -o ""
  	fi

    done

fi

# Remove processed rnx files if loop processing
if [[ "${QUARTER}" -gt 0 ]]; then
    log -l 0 -m  "Remove processed rnx files if loop processing" -o ""
    rm -f "${RAW_DIR}"/*.rnx
    if [[ $? -ne 0 ]]; then
	    log -l 2 -m  "WARNING: $? Can not remove processed rnx files" -o ""
    fi
fi

## Cleanup temp files
log -l 0 -m  "Remove temporary ${TEMP_DIR} folder" -o ""
rm -rf "${TEMP_DIR}"
if [[ $? -ne 0 ]]; then
	log -l 0 -m  "WARNING: $? Can not remove temporary ${TEMP_DIR} folder" -o ""
fi

# Move bin files if not opened by str2str
log -l 0 -m  "Move processed bin file(s) to archive folder" -o ""
for BINFILE in "${RAW_DIR}"/*."${binEXT}"; do
	if is_file_ready "${BINFILE}"; then
		mv -f "${BINFILE}" "${ARCHIVE_DIR}" # move processed bin file to archive folder
		if [[ $? -ne 0 ]]; then
			log -l 2 -m  "WARNING: $? Can not move processed $BINFILE to archive folder" -o ""
		fi
	fi
done

log -l 0 -m  "15-min file(s) with more than: ${nEPOCH2KEEP} 1S EPOCHs are cleaned and ready" -o ""

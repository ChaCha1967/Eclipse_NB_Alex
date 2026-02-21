#!/bin/bash

# Recovery data by converting bin -> rnx -> crx -> crx.gz after outages or other data acquisition failure

# Configuration for maual input
rpiUSER="alexk"
STATION="ANTC"
binEXT="ubx"

# Prepare Folders structure
RAW_DIR="/home/$rpiUSER/record"
TEMP_DIR="/home/$rpiUSER/record/temp_recovery"
FINAL_DIR="/home/$rpiUSER/data"
ARCH_DIR="/home/$rpiUSER/archive"
#BIN_DIR="/home/alexk/bin"
#STATION="ANTC"

# Make Folders structure
mkdir -p "$TEMP_DIR"
mkdir -p "$FINAL_DIR"
mkdir -p "$ARCH_DIR"

# 1. Process each BIN file found in the record directory
for WORKFILE in "$RAW_DIR"/*."$binEXT"; do
    [ -f "$WORKFILE" ] || continue

    echo "Converting $(basename "$WORKFILE")..."

    # Create a unique temp name for the RINEX fragment
    TEMP_OUT="$TEMP_DIR/$(basename "$WORKFILE" ."$binEXT").rnx"

    # Step 1: Convert BIN to RINEX
    convbin -ti 1.0000 -od -os -v 3.04 \
        -hm "$STATION" \
        -hc "For permission to use this data, contact:" \
        -hc "PT Jayachandran (chain@unb.ca)" \
        -hc "Canadian High Arctic Ionospheric Network" \
        -hc "Telephone: 506-453-4637" \
        -ho "PT Jayachandran/CHAIN" \
        -hr "Unknown/U-Blox C099-F9P" \
        -ha "Unknown/TOPGNSS TOP158" \
        -o "$TEMP_OUT" "$WORKFILE"
		
    # Step 2: Clean the temp file
    sed -i -e 's/[ \t]*$//' -e '/log:/d' "$TEMP_OUT"
done

# Step 3: Merge and split into the 15-min grid. 
# Note: Using "$TEMP_DIR/*.rnx" to include ALL files in the batch.
echo "Merging and splitting into 15-min grid..."
gfzrnx -finp "$TEMP_DIR/*.rnx" \
       -fout "$FINAL_DIR/${STATION}_%Y%j%H%M00_01Sa.rnx::RX3::" \
       -split 900  \
       -f \
       -vo 3.04 

# 4. Final cleaning and header fixing AFTER gfzrnx
echo "Finalizing output RINEX files..."
for RNX_FILE in "$FINAL_DIR"/*01S*.rnx; do
    [ -f "$RNX_FILE" ] || continue
    
    ## A. Rename XXX to CAN in the filename if it exists
    ## Example: ANTC00XXX_R_... -> ANTC00CAN_R_...
    #NEW_NAME=$(echo "$RNX_FILE" | sed 's/202200XXX/ANTC00CAN/')
    #if [ "$RNX_FILE" != "$NEW_NAME" ]; then
    #    mv "$RNX_FILE" "$NEW_NAME"
    #    RNX_FILE="$NEW_NAME"
    #fi
	
	# A. Get the base filename (e.g., 202200XXX_R_20220410045_15M_01S_MO.rnx)
    BASE_NAME=$(basename "$RNX_FILE")
    
    # DYNAMIC RENAMING
    # We take everything from the 10th character onwards and 
    # prepend your $STATION and "00CAN"
    # The 'cut -c 10-' command removes the first 9 characters (the wrong ID)
    SUFFIX=$(echo "$BASE_NAME" | cut -c 10-)
    NEW_FILE_NAME="${STATION}00CAN${SUFFIX}"
	# Extract the part before the last dot
	BASE_FILE_NAMEa="${NEW_FILE_NAME%.*}a"
	# Extract the extension (including the dot)
	EXT_NAMEa="${NEW_FILE_NAME##*.}"
	# Reconstruct with "a"
	NEW_FILE_NAMErnx="${BASE_FILE_NAMEa}.${EXT_NAMEa}"
	NEW_FILE_NAMEcrx="${BASE_FILE_NAMEa}.crx"
	NEW_FILE_NAMEcrxgz="${BASE_FILE_NAMEa}.crx.gz"
    NEW_FILE_PATHrnx="$FINAL_DIR/$NEW_FILE_NAMErnx"
    NEW_FILE_PATHcrx="$FINAL_DIR/$NEW_FILE_NAMEcrx"
    #NEW_FILE_PATHcrxgz="$FINAL_DIR/$NEW_FILE_NAMEcrxgz"
	
	
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
    # rm -f "$NEW_FILE_PATHcrx"
    # convert rnx to crx
    RNX2CRX -d ${NEW_FILE_PATHrnx}
	if [[ $? != 0 ]]; then
	    echo "There was an error with RNX2CRX. Move corrupt RNX to archive"
            mv "$NEW_FILE_PATHrnx" "$ARCH_DIR" # move rnx if corrupt to archive 
	fi

    # gzip crx to crx.gz
    gzip -f ${NEW_FILE_PATHcrx}
        if [[ $? != 0 ]]; then
	    echo "There was an error with gzip crx 2 crx.gz. Move corrupt CRX to archive"
            mv "$NEW_FILE_PATHcrx" "$ARCH_DIR" # move crx if corrupt to archive
        fi

done

# 5. Archive processed files to archive
echo "Archiving processed bin files..."
mv "$RAW_DIR"/*."$binEXT" "$ARCH_DIR" # move bin to archive 

# Cleanup temp files
rm -rf "$TEMP_DIR"

echo "Recovery complete. All 15-min files are cleaned and ready."

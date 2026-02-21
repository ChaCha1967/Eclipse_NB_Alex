#!/bin/bash

# Processing of the data transfered from rpi-gps
# Automatic filling the gap because of outage or other failures in data aquitition

# Configuration for maual input
rpiUSER="alexk"
STATION="ANTC"

# Define the suffix we are looking for (the 'a' before the extension)
SUFFIX="a"
EXTENSION=".crx.gz"

# Data folders
CRXGZ_mDIR="/home/$rpiUSER/rnx_main/" # main rnx data 
CRXGZ_aDIR="/home/$rpiUSER/data_crxgz/" # additional rnx data  
PROC_DIR="/home/$rpiUSER/proc/" # folder for data processing

# Make Folders structure if not exist
mkdir -p "$CRXGZ_aDIR"
mkdir -p "$PROC_DIR"

cd "$CRXGZ_mDIR"

# Finding all pair files in main rnx folder and move to processing folder
for file_a in *"${SUFFIX}${EXTENSION}"; do
    
    # Check if any matching files actually exist to avoid errors
    [[ -e "$file_a" ]] || { echo "No files matching pattern found."; break; }

    # 2. Determine the base file name
    # This removes 'a.crx.gz' from the end and adds '.crx.gz' back
     base_file="${file_a%${SUFFIX}${EXTENSION}}${EXTENSION}"

    # 3. Check if the primary (base) file exists
    if [[ -f "$base_file" ]]; then
        echo "Found pair: [ $base_file ] and [ $file_a ]"
        
        # Move both files to the processing folder
        mv "$base_file" "$file_a" "$PROC_DIR"
    else
        mv "$file_a" "$PROC_DIR"
    fi
done




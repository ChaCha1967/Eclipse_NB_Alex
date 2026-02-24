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

case $QUARTER in
    1) # QUATER 1
    START_TIME = "${YEAR}-${MONYH}-${DAY}T${HOUR}:00:00"
    ;;

    2) # QUATER 2
    START_TIME = "${YEAR}-${MONYH}-${DAY}T${HOUR}:15:00"
    ;;

    3) # QUATER 3
    START_TIME = "${YEAR}-${MONYH}-${DAY}T${HOUR}:30:00"
    ;;

    4) # QUATER 4
    START_TIME = "${YEAR}-${MONYH}-${DAY}T${HOUR}:45:00"
    ;;

esac

YEAR=`date -u +"%Y"`
MONTH=`date -u +"%m"`
DAY=`date -u +"%d"`
DOY=`date -u +"%j"`
HOUR=`date -u +"%H"`
FILENAMES=`ls -t *."$binEXT"`
FILECOUNT=`ls *."$binEXT" | wc -w`
if [[ "$QUARTER" -lt "4" ]]; then
    WORKFILE=`echo $FILENAMES | cut -f 1 -d " "`
else
    WORKFILE=`echo $FILENAMES | cut -f 2 -d " "`
fi
OUTFILE="${STATION}00CAN_R_${YEAR}${DOY}${HOUR}"

echo "There were $FILECOUNT files in quarter $QUARTER"

# QUATER 1,2,3
if [[ "$QUARTER" -lt "4" && "$FILECOUNT" -gt "1" ]]; then
    echo "We have too many files. As a fix, we will delete the oldest files."
    FILES_TO_DELETE=`echo $FILENAMES | cut --complement -f 1 -d " "`
    echo "We need to delete $FILES_TO_DELETE"
    for FILE in $FILES_TO_DELETE
    do
	mv -f $FILE "$TRASH_DIR"
    done
fi
# QUATER 4
if [[ "$QUARTER" == "4" && "$FILECOUNT" -gt "2" ]]; then
    echo "We have too many files. As a fix, we will delete the oldest files."
    FILES_TO_DELETE=`echo $FILENAMES | cut --complement -f 1,2 -d " "`
    echo "We need to delete $FILES_TO_DELETE"
    for FILE in $FILES_TO_DELETE
    do
	mv -f $FILE "$TRASH_DIR"
    done
fi

FILECOUNT=`ls *."$binEXT" | wc -w`

echo "There are $FILECOUNT files in quarter $QUARTER"
echo "Workfile $WORKFILE"
echo "OUTFILE $OUTFILE"

#COMMON_OPTS="-ti 1.0000 -od -os -v 3 -hm ANTC -hc For\ permission\ to\ use\ this\ data,\ contact: -hc PT\ Jayachandran\ (chain@unb.ca) -hc Canadian\ High\ Arctic\ Ionospheric\ Network -hc Telephone:\ #506-453-4637 -ho PT\ Jayachandran/Canadian\ High\ Arctic\ Ionospheric\ Network -hr Unknown/U-Blox\ C099-F9P -ha Unknown/TOPGNSS\ TOP158"

case $QUARTER in
    1) # QUATER 1
    
	# A: Convert BIN to RINEX
    convbin -ts $YEAR/$MONTH/$DAY $HOUR:00:00 -te $YEAR/$MONTH/$DAY $HOUR:15:00 \
	    -ti 1.0000 -od -os -v 3.04 \
        -hm "$STATION" \
        -hc "For permission to use this data, contact:" \
        -hc "PT Jayachandran (chain@unb.ca)" \
        -hc "Canadian High Arctic Ionospheric Network" \
        -hc "Telephone: 506-453-4637" \
        -ho "PT Jayachandran/CHAIN" \
        -hr "Unknown/U-Blox C099-F9P" \
        -ha "Unknown/TOPGNSS TOP158" \
        -o ${OUTFILE}00_15M_01S_MO.rnx $WORKFILE #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with convbin"
	fi

        # B: Clean the temp file
        sed -i -e 's/[ \t]*$//' -e '/log:/d' ${OUTFILE}00_15M_01S_MO.rnx

        # B: Convert RNX to CRX
	RNX2CRX ${OUTFILE}00_15M_01S_MO.rnx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with RNX2CRX"
	fi
	
	# C: gzip crx to crx.gz
        gzip ${OUTFILE}00_15M_01S_MO.crx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with gzip crx 2 crx.gz"
	fi
	
	# D: Move crx.gz file to data folder and remove rnx file
	mv ${OUTFILE}00_15M_01S_MO.crx.gz "$FINAL_DIR"
	rm ${OUTFILE}00_15M_01S_MO.rnx
	;;

    2) # QUATER 2
    
	# A: Convert BIN to RINEX
    convbin -ts $YEAR/$MONTH/$DAY $HOUR:15:00 -te $YEAR/$MONTH/$DAY $HOUR:30:00 \
	    -ti 1.0000 -od -os -v 3.04 \
        -hm "$STATION" \
        -hc "For permission to use this data, contact:" \
        -hc "PT Jayachandran (chain@unb.ca)" \
        -hc "Canadian High Arctic Ionospheric Network" \
        -hc "Telephone: 506-453-4637" \
        -ho "PT Jayachandran/CHAIN" \
        -hr "Unknown/U-Blox C099-F9P" \
        -ha "Unknown/TOPGNSS TOP158" \
        -o ${OUTFILE}15_15M_01S_MO.rnx $WORKFILE #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with convbin"
	fi

        # B: Clean the temp file
        sed -i -e 's/[ \t]*$//' -e '/log:/d' ${OUTFILE}15_15M_01S_MO.rnx

        # B: Convert RNX to CRX
	RNX2CRX ${OUTFILE}15_15M_01S_MO.rnx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with RNX2CRX"
	fi
	
	# C: gzip crx to crx.gz
        gzip ${OUTFILE}15_15M_01S_MO.crx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with gzip crx 2 crx.gz"
	fi
	
	# D: Move crx.gz file to data folder and remove rnx file
	mv ${OUTFILE}15_15M_01S_MO.crx.gz "$FINAL_DIR"
	rm ${OUTFILE}15_15M_01S_MO.rnx
	;;

    3) # QUATER 3
    
	# A: Convert BIN to RINEX
    convbin -ts $YEAR/$MONTH/$DAY $HOUR:30:00 -te $YEAR/$MONTH/$DAY $HOUR:45:00 \
	    -ti 1.0000 -od -os -v 3.04 \
        -hm "$STATION" \
        -hc "For permission to use this data, contact:" \
        -hc "PT Jayachandran (chain@unb.ca)" \
        -hc "Canadian High Arctic Ionospheric Network" \
        -hc "Telephone: 506-453-4637" \
        -ho "PT Jayachandran/CHAIN" \
        -hr "Unknown/U-Blox C099-F9P" \
        -ha "Unknown/TOPGNSS TOP158" \
        -o ${OUTFILE}30_15M_01S_MO.rnx $WORKFILE #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with convbin"
	fi

        # B: Clean the temp file
        sed -i -e 's/[ \t]*$//' -e '/log:/d' ${OUTFILE}30_15M_01S_MO.rnx

        # B: Convert RNX to CRX
	RNX2CRX ${OUTFILE}30_15M_01S_MO.rnx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with RNX2CRX"
	fi
	
	# C: gzip crx to crx.gz
        gzip ${OUTFILE}30_15M_01S_MO.crx #>/dev/null 2>&1
	if [[ $? != 0 ]]; then
	    echo "There was an error with gzip crx 2 crx.gz"
	fi
	
	# D: Move crx.gz file to data folder and remove rnx file
	mv ${OUTFILE}30_15M_01S_MO.crx.gz "$FINAL_DIR"
	rm ${OUTFILE}30_15M_01S_MO.rnx
	;;

    4) # QUATER 3
	
	HOUR=$((10#${HOUR} - 1))
	if [ "$HOUR" == "-1" ]; then
	    YEAR=`date -u +"%Y" -d "-1 hour"`
	    MONTH=`date -u +"%m" -d "-1 hour"`
	    DAY=`date -u +"%d" -d "-1 hour"`
	    DOY=`date -u +"%j" -d "-1 hour"`
	    HOUR=`date -u +"%H" -d "-1 hour"`
	    NEXT_YEAR=`date -u +"%Y"`
	    NEXT_MONTH=`date -u +"%m"`
	    NEXT_DAY=`date -u +"%d"`
	    NEXT_DOY=`date -u +"%j"`
	    NEXT_HOUR=`date -u +"%H"`
	elif [ "$HOUR" -lt "10" ] ; then
	    HOUR="0$HOUR"
	    NEXT_YEAR=$YEAR
	    NEXT_MONTH=$MONTH
	    NEXT_DAY=$DAY
	    NEXT_DOY=$DOY
	    NEXT_HOUR=`date -u +"%H"`
	else
	    NEXT_YEAR=$YEAR
	    NEXT_MONTH=$MONTH
	    NEXT_DAY=$DAY
	    NEXT_DOY=$DOY
	    NEXT_HOUR=`date -u +"%H"`
	fi
	
	OUTFILE="${STATION}00CAN_R_${YEAR}${DOY}${HOUR}"
	
	if [ $FILECOUNT == 2 ]; then
		# A: Convert BIN to RINEX
		convbin -ts $YEAR/$MONTH/$DAY $HOUR:45:00 -te $YEAR/$MONTH/$DAY $NEXT_HOUR:00:00 \
			-ti 1.0000 -od -os -v 3.04 \
			-hm "$STATION" \
			-hc "For permission to use this data, contact:" \
			-hc "PT Jayachandran (chain@unb.ca)" \
			-hc "Canadian High Arctic Ionospheric Network" \
			-hc "Telephone: 506-453-4637" \
			-ho "PT Jayachandran/CHAIN" \
			-hr "Unknown/U-Blox C099-F9P" \
			-ha "Unknown/TOPGNSS TOP158" \
			-o ${OUTFILE}45_15M_01S_MO.rnx $WORKFILE #>/dev/null 2>&1
		if [[ $? != 0 ]]; then
			echo "There was an error with convbin"
		fi

		# B: Clean the temp file
		sed -i -e 's/[ \t]*$//' -e '/log:/d' ${OUTFILE}45_15M_01S_MO.rnx

	        # B: Convert RNX to CRX
		RNX2CRX ${OUTFILE}45_15M_01S_MO.rnx #>/dev/null 2>&1
		if [[ $? != 0 ]]; then
			echo "There was an error with RNX2CRX"
		fi
		
		# C: gzip crx to crx.gz
		gzip ${OUTFILE}45_15M_01S_MO.crx #>/dev/null 2>&1
		if [[ $? != 0 ]]; then
			echo "There was an error with gzip crx 2 crx.gz"
		fi
		


			mv ${OUTFILE}45_15M_01S_MO.crx.gz "$FINAL_DIR"
			#rm ${OUTFILE}45_15M_01S_MO.rnx
			#rm ${WORKFILE}
			# Temporarily move WORFILE and RNX to TRESH folder
			mv ${OUTFILE}45_15M_01S_MO.rnx "$TRASH_DIR"
			mv ${WORKFILE} "$TRASH_DIR"
	else
	    echo "There are more files than there should be"
	fi
	;;
esac

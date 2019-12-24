#!/bin/bash

# Calibrate data using GLEAM year 1 catalogue
start_time=`date +%s`

# Set default values for optional parameters
flag=yes

# Read the options
TEMP=`getopt -o a:b:c:d:e:f --long input_data:,cal_dir:,obsid_list:,cal_obsid:,chan:,noflag -- "$@"`
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true ; do
      case "$1" in
        -a|--input_data) # input directory containing raw measurement set (required argument)
            case "$2" in
                "") shift 2 ;;
                *) input_data=$2 ; shift 2 ;;
            esac ;;
        -b|--cal_dir) # input directory containing calibrator solutions.
            case "$2" in
                "") shift 2 ;;
                *) cal_dir=$2 ; shift 2 ;;
            esac ;;
        -c|--obsid_list) # obsID list (required argument)
            case "$2" in
                "") shift 2 ;;
                *) obsid_list=$2 ; shift 2 ;;
            esac ;;
        -d|--cal_obsid) # obsID list (required argument)
            case "$2" in
                "") shift 2 ;;
                *) cal_obsid=$2 ; shift 2 ;;
            esac ;;
        -e|--chan) # channel (required argument); set to 69, 93, 121, 145 or 169
            case "$2" in
                "") shift 2 ;;
                *) chan=$2 ; shift 2 ;;
            esac ;;
        -f|--noflag) flag=no ; shift ;; # do not flag tiles in obsid_list (no argument, acts as flag)
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# Check required arguments have been specified
if [ -z "$input_data" ]; then
  echo "Error: input_data not specified. Aborting."
  exit 1
elif [ -z "$cal_dir" ]; then
  echo "Error: cal_dir not specified. Aborting."
  exit 1
elif [ -z "$cal_dir" ]; then
  echo "Error: cal_dir not specified. Aborting."
  exit 1
elif [ -z "$obsid_list" ]; then
  echo "Error: obsid_list not specified. Aborting."
  exit 1
elif [ -z "$cal_obsid" ]; then
  echo "Error: No calibrator OBSID given, aborting script!"
  exit 1
elif [ -z "$chan" ]; then
  echo "Error: chan not specified. Aborting."
  exit 1
fi

# Check chan parameter
if [ $chan != "69" ] && [ $chan != "93" ] && [ $chan != "121" ] && [ $chan != "145" ] && [ $chan != "169" ] && [ $chan != "236" ]; then
  echo "Error: chan should be set to 69, 93, 121, 145, 169, or 236. Aborting."
  exit 1
fi

# Set obsid
#obsid=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $1}'`
obsid=` awk '{print $1}' $obsid_list`

# Create output directory
if [ ! -e $cal_dir ]; then
  mkdir $cal_dir
fi

# Create snapshot directory
# remove 4 hashes below
if [ -e $cal_dir/$obsid ]; then
  rm -rf $cal_dir/$obsid
fi
mkdir $cal_dir/$obsid
#cd $input_data/$obsid/
cd $cal_dir/$obsid

# Write input parameters to file for record
cat >> input_parameters_cal_year1.txt <<EOPAR
input_data = $input_data
cal_dir = $cal_dir
obsid_list = $obsid_list
chan = $chan
flag = $flag
robust = $robust
EOPAR

# Copy measurement set, metafits file and sky model to output directory
if [ -e $input_data/$obsid/$obsid.ms ] && [ -e $input_data/$obsid/$obsid.metafits ]; then
# kluge to refresh stale file handles
    cd $input_data/$obsid/
    cd $cal_dir/$obsid
    cp -r $input_data/$obsid/$obsid.ms $input_data/$obsid/$obsid.metafits .
else
    echo "Error: input files are missing. Aborting."
    exit 1
fi

# -------------------------------------------------------------

# Flag tiles if required
if [ $flag == "yes" ]; then
  #tile_list=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $2}'`
  tile_list=` awk '{print $2}' $obsid_list`
  echo $tile_list
  if [ -z "$tile_list" ]; then
    echo "No tiles to flag for snapshot $obsid"
  elif [ $tile_list == "none" ]; then
    echo "No tiles to flag for snapshot $obsid"
  else
    tile_list=`echo ${tile_list//,/ }`
# Check tiles are integers between 0 and 127
    for tile in ${tile_list[@]}; do  
      if [ "${tile//[0-9]}" != "" ] || [ $(echo "$tile < 0"|bc) -eq 1 ] || [ $(echo "$tile > 127"|bc) -eq 1 ]; then
        echo "Error: tile $tile is not an integer between 0 and 127. Aborting."
        exit 1
      fi
    done
# Flag tiles
    echo "Flagging tiles $tile_list for snapshot $obsid listed in $obsid_list"
    flagantennae $obsid.ms $tile_list
  fi
fi

################################################################################
#Calibration testing begin.
################################################################################
# flagging data:

echo "Flagging RFI and first three coarse channels."

cmd='["mode='clip' datacolumn='DATA' spw='0:0~95' clipminmax=[0.0,0.0] clipzeros=True","mode='rflag' datacolumn='DATA' timedevscale=4.0"]'
echo "flagdata(vis='${obsid}.ms',mode='list',inpfile=${cmd},action='apply')"
casa --nologger -c "flagdata(vis='${obsid}.ms',mode='list',inpfile=${cmd},action='apply')"

# Apply the solutions
echo "Transferring calibration solutions from $cal_obsid to $obsid"
applysolutions $obsid.ms $cal_dir/${cal_obsid}/${cal_obsid}_solutions.bin

# Further flagging RFI.
aoflagger -v -column CORRECTED_DATA $obsid.ms

## Plot phase and amplitude calibration solutions
#echo "Doing plot of phase and amplitude"
#aocal_plot.py --refant=127 ${obsid}_solutions.bin

## Re-plot amplitude calibration solutions, this time setting maximum of y axis to 100 and 10000
#for amp in 100 10000; do
#  mkdir t
#  aocal_plot.py --refant=127 --outdir=./t --amp_max=$amp ${obsid}_solutions.bin
#  mv ./t/${obsid}_solutions_amp.png ${obsid}_solutions_amp_max${amp}.png
#  rm -rf t
#done

# -------------------------------------------------------------

casa --nologger -c "plotms(vis='${obsid}.ms',xaxis='frequency',yaxis='amp',correlation='xx,yy',ydatacolumn='corrected',coloraxis='spw',plotfile='amp_vfreq_{0}_corrected.png'.format(${obsid}),showgui=False,overwrite=True)"

end_time=`date +%s`
duration=`echo "$end_time-$start_time" | bc -l`
echo "Total runtime = $duration sec"

# Move output and error files to output directory
#mv $MYDATA/cal_year1.o${obsid} $MYDATA/cal_year1.e${obsid} .

exit 0

#!/bin/bash

# Calibrate data using GLEAM year 1 catalogue
start_time=`date +%s`

# Set default values for optional parameters
flag=yes

# Read the options
TEMP=`getopt -o a:b:c:d:e:f --long input_data:,input_model:,output_dir:,obsid_list:,chan:,noflag -- "$@"`
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true ; do
      case "$1" in
        -a|--input_data) # input directory containing raw measurement set (required argument)
            case "$2" in
                "") shift 2 ;;
                *) input_data=$2 ; shift 2 ;;
            esac ;;
        -b|--input_model) # input directory containing model for calibration (required argument)
            case "$2" in
                "") shift 2 ;;
                *) input_model=$2 ; shift 2 ;;
            esac ;;
        -c|--output_dir) # output directory (required argument)
            case "$2" in
                "") shift 2 ;;
                *) output_dir=$2 ; shift 2 ;;
            esac ;;
        -d|--obsid_list) # obsID list (required argument)
            case "$2" in
                "") shift 2 ;;
                *) obsid_list=$2 ; shift 2 ;;
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
elif [ -z "$input_model" ]; then
  echo "Error: input_model not specified. Aborting."
  exit 1
elif [ -z "$output_dir" ]; then
  echo "Error: output_dir not specified. Aborting."
  exit 1
elif [ -z "$obsid_list" ]; then
  echo "Error: obsid_list not specified. Aborting."
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

# Set other input parameters
imsize=5000 # a quick image is made after calibration as a sanity check; imsize is the size of this image
#robust="-1.0"
robust="0.7"
ncpus=12
mem=31

# Create output directory
if [ ! -e $output_dir ]; then
  mkdir $output_dir
fi

# Create snapshot directory
# remove 4 hashes below
if [ -e $output_dir/$obsid ]; then
  rm -rf $output_dir/$obsid
fi
mkdir $output_dir/$obsid
#cd $input_data/$obsid/
cd $output_dir/$obsid

# Write input parameters to file for record
cat >> input_parameters_cal_year1.txt <<EOPAR
input_data = $input_data
input_model = $input_model
output_dir = $output_dir
obsid_list = $obsid_list
chan = $chan
flag = $flag
imsize = $imsize
robust = $robust
EOPAR

# Set pixel size
scale=`echo "0.55 / $chan" | bc -l`
scale=${scale:0:8}
#scale=0.04

# Copy measurement set, metafits file and sky model to output directory
if [ -e $input_data/$obsid/$obsid.ms ] && [ -e $input_data/$obsid/$obsid.metafits ] && [ -e $input_model/$obsid/skymodelformat.txt ]; then
# kluge to refresh stale file handles
    cd $input_data/$obsid/
    cd $output_dir/$obsid
    cp -r $input_data/$obsid/$obsid.ms $input_data/$obsid/$obsid.metafits $input_model/$obsid/skymodelformat.txt .
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

# determin max uv
maxuvm=887250/$chan

# Find calibration solutions
# edit out for now
echo "Running calibrate on  $obsid"


################################################################################
#Calibration testing begin.
################################################################################
# flagging data:


cmd='["mode='rflag' datacolumn='DATA' timedevscale=4.0", "mode='clip' datacolumn='DATA' spw='0:0~95' clipminmax=[0.0,0.0] clipzeros=True"]'
echo "flagdata(vis='vis',mode='list',inpfile=${cmd},action='apply')"
casa --nologger -c "flagdata(vis='${obsid}.ms',mode='list',inpfile=${cmd},action='apply')"
echo "Plotting DATA column amp vs frequency solutions!"
casa --nologger -c "plotms(vis='${obsid}.ms',xaxis='frequency',yaxis='amp',correlation='xx,yy',ydatacolumn='data',coloraxis='spw',plotfile='amp_vfreq_${obsid}_data-tcrop-rflag-clip-og.png',showgui=False,overwrite=True)"
echo "Running CALIBRATE!"
# Once the RFI has been flagged we can calibrate:

# This method will hopefully take a sky model and apply the beam across the bandwidth for each source.
#calibrate -m skymodelformat.txt -minuv 60 -maxuv $maxuvm -applybeam $obsid.ms ${obsid}_solutions.bin

# -beam-on-source is no longer an option.
#calibrate -m skymodelformat.txt -minuv 60 -maxuv $maxuvm -beam-on-source $obsid.ms ${obsid}_solutions.bin

# This method takes the apparent sky model and calibrates the data.
calibrate -m skymodelformat.txt -absmem $mem -minuv 60 -maxuv $maxuvm $obsid.ms ${obsid}_solutions.bin

################################################################################
#Calibration testing end.
################################################################################

# Apply the solutions
# edit out for now

echo "Applying solutions to  $obsid"
applysolutions $obsid.ms ${obsid}_solutions.bin

# Before aoflagger.
echo "Plotting CORRECTED_DATA column amp vs frequency solutions!"
casa --nologger -c "plotms(vis='${obsid}.ms',xaxis='frequency',yaxis='amp',correlation='xx,yy',ydatacolumn='corrected',coloraxis='spw',plotfile='amp_vfreq_${obsid}_corrected-og.png',showgui=False,overwrite=True)"


casa --nologger -c "flagdata(vis='${obsid}.ms',mode='rflag',datacolumn='CORRECTED',timedevscale=4.0,action='apply')"
# Further flagging RFI.
#aoflagger -v -column CORRECTED_DATA $obsid.ms

# Might skip the aoflagger step, since it might reset the flags.

echo "Plotting DATA column amp vs frequency solutions!"
echo "Testing to see if aoflagger resets the solutions!"
casa --nologger -c "plotms(vis='${obsid}.ms',xaxis='frequency',yaxis='amp',correlation='xx,yy',ydatacolumn='data',coloraxis='spw',plotfile='amp_vfreq_${obsid}_data-tcrop-rflag-clip.png',showgui=False,overwrite=True)"

# Plot phase and amplitude calibration solutions
echo "Doing plot of phase and amplitude"
aocal_plot.py --refant=127 ${obsid}_solutions.bin

# Re-plot amplitude calibration solutions, this time setting maximum of y axis to 100 and 10000
for amp in 100 10000; do
  mkdir t
  aocal_plot.py --refant=127 --outdir=./t --amp_max=$amp ${obsid}_solutions.bin
  mv ./t/${obsid}_solutions_amp.png ${obsid}_solutions_amp_max${amp}.png
  rm -rf t
done

echo "Plotting CORRECTED_DATA column amp vs frequency solutions!"
casa --nologger -c "plotms(vis='${obsid}.ms',xaxis='frequency',yaxis='amp',correlation='xx,yy',ydatacolumn='corrected',coloraxis='spw',plotfile='amp_vfreq_${obsid}_corrected.png',showgui=False,overwrite=True)"

# -------------------------------------------------------------

end_time=`date +%s`
duration=`echo "$end_time-$start_time" | bc -l`
echo "Total runtime = $duration sec"

# Move output and error files to output directory
#mv $MYDATA/cal_year1.o${obsid} $MYDATA/cal_year1.e${obsid} .

exit 0

#!/bin/bash

# Build sky model for snapshot using the 300 MHz interpolated catalogue.

start_time=`date +%s`

# Set default values for optional parameters
pbeam_model=2016
# reduce to find many sources 
threshold=1
resolution=0.022 # Approximate 300 MHz psf major and minor axis size.

# Read the options
TEMP=`getopt -o a:b:c:d:e: --long input_dir:,output_dir:,obsid_list:,threshold:,chan: -- "$@"`
eval set -- "$TEMP"

# Extract options and their arguments into variables
while true ; do
      case "$1" in
        -a|--input_dir) # input directory (required argument)
            case "$2" in
                "") shift 2 ;;
                *) input_dir=$2 ; shift 2 ;;
            esac ;;
        -b|--output_dir) # output directory (required argument)
            case "$2" in
                "") shift 2 ;;
                *) output_dir=$2 ; shift 2 ;;
            esac ;;
        -c|--obsid_list) # obsID list (required argument)
            case "$2" in
                "") shift 2 ;;
                *) obsid_list=$2 ; shift 2 ;;
            esac ;;
	-d|--threshold) # obsID list (optional argument)
            case "$2" in
                "") shift 2 ;;
                *) threshold=$2 ; shift 2 ;;
            esac ;;
        -e|--chan) # channel (required argument); set to 69, 93, 121, 145 or 169
            case "$2" in
                "") shift 2 ;;
                *) chan=$2 ; shift 2 ;;
            esac ;;
        --) shift ; break ;;
        *) echo "Internal error!" ; exit 1 ;;
    esac
done

# Check required arguments have been specified
if [ -z "$input_dir" ]; then
  echo "Error: input_dir not specified. Aborting."
  exit 1
elif [ -z "$obsid_list" ]; then
  echo "Error: obsid_list not specified. Aborting."
  exit 1
fi

# Check chan parameter
if [ $chan != "69" ] && [ $chan != "93" ] && [ $chan != "121" ] && [ $chan != "145" ] && [ $chan != "169" ] && [ $chan != "236" ] && [ $chan != "237" ]; then
  echo "Error: chan should be set to 69, 93, 121, 145, 169 or 236. Aborting."
  exit 1
fi

# Set obsid (removed the list function):
#obsid=`sed "${SLURM_ARRAY_TASK_ID}q;d" $obsid_list | awk '{print $1}'`
#obsid=`sed $obsid_list | awk '{print $1}'`
obsid=` awk '{print $1}' $obsid_list`

# Create output directory
#if [ ! -e $output_dir ]; then
#  mkdir $output_dir
#fi

# Create snapshot directory
if [ -e $output_dir/$obsid ]; then
  echo "Error: Output directory $output_dir/$obsid already exists. Aborting."
  exit 1
else
  mkdir $output_dir/$obsid
  cd $output_dir/$obsid
fi

# Coping over the obsid and metafits.
if [ -e $input_dir/$obsid/$obsid.ms ] && [ -e $input_dir/$obsid/$obsid.metafits ]; then
   ln -s $input_dir/$obsid/$obsid.ms $input_dir/$obsid/$obsid.metafits .
else
  echo "Error: input files are missing. Aborting."
  exit 1
fi

# Set delays and frequency.
delays=$(fitshdr $obsid.metafits | grep 'DELAYS' | awk '{print $3}')
freq=$(fitshdr $obsid.metafits | grep 'FREQCENT' | awk '{print $2}')

echo "$obsid measurement set and metafits copied to output directory."
echo "delays = $delays"

#catalogue=/group/mwasci/tfranzen/GLEAM_IDR6/GLEAMIDR6_published.fits # to be used to calibrate the data

# Write input parameters to file for record
cat >> input_parameters_build_appsky.txt <<EOPAR
input_dir = $input_dir
output_dir = $output_dir
obsid_list = $obsid_list
threshold = $threshold
resolution = $resolution
catalogue = $catalogue
delays = $delays
EOPAR

# Set frequency depending on channel
if [[ $chan -eq 69 ]]; then
  freq=88
elif [[ $chan -eq 93 ]]; then
  freq=118
elif [[ $chan -eq 121 ]]; then
  freq=154
elif [[ $chan -eq 145 ]]; then
  freq=185
elif [[ $chan -eq 169 ]]; then
  freq=215
elif [[ $chan -eq 236 ]]; then
  freq=300
elif [[ $chan -eq 237 ]]; then
  freq=303
fi
echo "Central frequency for channel $chan = $freq MHz"

# Get RA and Dec of pointing centre from .metafits file, in deg
ra_pnt=$(fitshdr $obsid.metafits | grep 'RA of pointing center' | awk '{print $3}')
dec_pnt=$(fitshdr $obsid.metafits | grep 'Dec of pointing center' | awk '{print $3}')

# Sky model at 300 MHz
catalogue=/home/jaidencook/Documents/Masters/catalogues/Total-300MHz-skymodel.fits

# Creating the output V02 table skymodel.
#Model_format_2.py --obsid $obsid --freq $freq --delays $delays --catalogue $catalogue --ra $ra_pnt --dec $dec_pnt --threshold $threshold
Model_format_3.py --obsid $obsid --freq $freq --delays $delays --catalogue $catalogue --ra $ra_pnt --dec $dec_pnt --threshold $threshold

##mv "$PIPE_SCRIPTS/*.png" "$output_dir/$obsid"
##mv "$PIPE_SCRIPTS/*.vot" "$output_dir/$obsid"

# Convert the edited catalogue to a format which is readable by calibrate.
# Sources with int_flux_wide/peak_flux_wide < resolution will be considered to be unresolved.
vo2newmodel_2.py --catalogue model_morecolumns_temp.vot --output skymodelformat.txt --freq $freq --fluxcol S_centralfreq_uncorrected --coeff apparent_poly_coeff --point --resolution=$resolution

# Remove .ms and .metafits files and PSF template images
rm -rf $obsid.ms $obsid.metafits *.fits

# -------------------------------------------------------------

end_time=`date +%s`
duration=`echo "$end_time-$start_time" | bc -l`
echo "Total runtime = $duration sec"

# Move output and error files to output directory
mv $MYDATA/build_appsky.o${obsid} $MYDATA/build_appsky.e${obsid} .

exit 0


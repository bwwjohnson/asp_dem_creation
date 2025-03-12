#!/bin/bash
 
# Created by J. Hollingsworth
# Modifications by B. Johnson in March 2022 
# email benedict.johnson@st-annes.ox.ac.uk

# User input required to set up input files etc below. In addition to this, you should tweak parameters in stereo and point2dem.
# Running this script on a server machine is better for speed. 

### Summary of process (turn steps off to avoid repetative processing (e.g. if fiddling with point2dem parameters, turn off generate_pl, mapproject and stereo)):
# create_refdem: using a merged global DEM and a manually traced polygon, clip a reference dem for the area
# generate_pl: put together the tiled Pleiades images to make a the two stereo pair GeoTIFFs
# mapproject: orthorectify these images using low-res reference DEM. This helps stereo correlate the two images and reduces gaps.
# stereo: searches the two images for matching points, and uses triangulation to produce the point cloud
# rasterize: uses point2dem to filter the point cloud for outliers and grids it to make a DEM
# stereo_alignment: aligns the ASP DEM with a standard global DEM (e.g. ALOS). Then differences the DEMs. Check this difference map for systematic errors
# ortho: create orthoimages using the raw imagery and the ASP DEM

########################## USER INPUT REQUIRED BELOW ###########################
########################## CHANGE WHEN YOU FIRST USE THE SCRIPT ################
### check StereoPipeline path -- adapt this to your StereoPipeline path
asp_path="/home/cometsoft/StereoPipeline/bin"
[[ ":$PATH:" != *":/home/cometsoft/StereoPipeline/bin:"* ]] && PATH=${PATH}:$asp_path
### variables for making the reference DEM
big_dem=/home/cometraid13/benj/phd/GIS/data/topo/jaxa_from_cometraid4/jaxa_merge_pamir # change to your reference DEM path
demdir="/home/cometraid13/benj/khait/asp/jaxa" # change to your clipped DEM path
clip_polygon=pleiades_clip # polygon for clipping your large DEM -- create yourself in QGIS
clipped_dem=$demdir/pleiades_jaxa_ref
dem=${clipped_dem}_utm42.tif  # 30m DEM for differencing (to check stereo process has completed successfully)
demmp=${clipped_dem}_utm42_150.tif # downsampled DEM for mapprojecting before stereo
epsg="32642" # NUTM42 -- change to your UTM zone
### computer processing variables 
processes="4"
threads="12"
mem_lim="300000"  # memory limit in mb -- change to fit your RAM availability

########################## CHANGE ON A RUN-BY-RUN BASIS #####################
### AOI (for cropping) -- feed lon/lat here

LL="71.4056803, 39.1182968"
UR="71.41578943, 39.12719208"
# LL="71.291045, 39.081275" #= entire region (all overlaps)
# UR="71.506536, 39.212909"
LLutm=$(echo $LL | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
URutm=$(echo $UR | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
EXTENTS=$(echo $LLutm $URutm)

# alternatively give extents in UTM coords (minX minY maxX maxY)
# EXTENTS="645898 4339044 647514 4339768"

crop win URX LLX URY LLY

crop=`echo $EXTENTS | awk '{print $3,$1,$4,$2}'`
# crop window in pixels
# crop_win="--right-image-crop-win $crop --left-image-crop-win $crop"
crop_win="--left-image-crop-win 10661 5856 1938 987 --right-image-crop-win 10906 5815 1863 986"


# what to run?... 0 = no | 1 = yes
create_refdem="0"
generate_pl="0"
mapproject="0"
stereo="1"
rasterize="1"
stereo_alignment="1"
ortho="0"

# set the image dir
wdir="/home/cometraid13/benj/khait/pleiades"
# set the run name
runid=sgm0.5_small
# set resolution (m)
resmp="0.5" # res of mapproj images used for stereo (likely is same as resdem)
res="0.5" # res of the final orthos
resdem="0.5" # res of the final DEM

########################## OVERLAP LIST #####################
# manually enter all pairs which overlap (for tristereo, 3 overlapping pairs)
cat << EOF > $wdir/stereo_overlap_list.txt
5467721101 5467778101
5467721101 5467779101
5467778101 5467779101
EOF
########################## END OF USER INPUT ################
# if (($create_refdem == 1 )) ; then
# # prepare your reference DEM
# cd $demdir
# rm $clipped_dem*.tif
# echo "clip the dem"
# ls ${clip_polygon}.shp
# gdalwarp -of GTiff -cutline ${clip_polygon}.shp -cl $clip_polygon -crop_to_cutline -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 $big_dem.tif ${clipped_dem}_wgs84.tif
# echo "wgs84 --> UTM"
# gdalwarp -s_srs EPSG:4326 -t_srs EPSG:$epsg -r bilinear -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -of GTiff ${clipped_dem}_wgs84.tif ${clipped_dem}_utm42.tif
# echo "downsample"
# gdalwarp -tr 150 150 -r average -of GTiff ${clipped_dem}_utm42.tif ${clipped_dem}_utm42_150.tif
# echo "oversample 150m dem, interpolate w/ cubic spline to make smoothed 30m dem"
# gdalwarp -tr 30 30 -r cubicspline -of GTiff ${clipped_dem}_utm42_150.tif ${clipped_dem}_utm42_smooth.tif
# rm ${clipped_dem}_wgs84.tif 
# fi
#####################################
# lets go...
# this bit doesn't work and I don't understand why (B. Johnson 31 March 2022)
if (($generate_pl == 1 )) ; then
cd $wdir
mkdir -p asp
# merge tiles
dirs=`cat stereo_overlap_list.txt | tr " " "\n" | sort -u`
for dir in $dirs; do 
echo $dir
cd ${wdir}/${dir}/*001/ 
echo "tile $dir using DIM file"
# use GDAL v3.0.2 rather than ASP's version 2.0.2 which has a bug
gdal_translate DIM_*.XML $wdir/asp/${dir}.TIF -co TILED=YES
cp RPC*XML $wdir/asp/${dir}.XML
echo "wrote $dir.TIF"
done
cd $wdir
fi #generate_pl


## mapproject... for easier stereo matching
if (($mapproject == 1 )) ; then
echo "mapproject..."
mkdir -p $wdir/asp
cd $wdir/asp
rm -r $wdir/asp/$runid
mkdir -p $wdir/asp/$runid/
dirs=`cat $wdir/stereo_overlap_list.txt | tr " " "\n" | sort -u`
# make sure mapproject isn't interpreted as a GMT command!!
for f in $dirs ; do
$asp_path/mapproject -t rpc $demmp $f.TIF $f.XML $runid/${f}_MP.tif --nodata-value -250 --num-processes $processes --threads $threads --tr $resmp
echo "##### cp ${f}.XML $runid/${f}_MP.XML "
cp ${f}.XML $runid/${f}_MP.XML
done
fi #mapproject

#####################################
### START LOOP OVER OVERLAP PAIRS ###

cd $wdir/asp
mkdir -p multi
while read p; do
L=$(echo $p | tr " " "\n" | sort -n | sed -n "1p")
R=$(echo $p | tr " " "\n" | sort -nr | sed -n "1p")

# # 5467721101 5467778101
# # 5467721101 5467779101
# # 5467778101 5467779101

# # L=5467779101
# # R=5467721101

# L=5467778101
# R=5467721101

echo $L 
echo $R
pair_dir=$(echo "${L}__${R}")

#####################################
## run stereo
if (($stereo == 1 )) ; then
echo "stereo..."
cd $wdir/asp
out=$(echo "$runid/$pair_dir")
echo "removing $out"
rm -r $out  # CAREFUL!
session="-t rpcmaprpc --alignment-method none"
# run stereo...
filtering="--rm-cleanup-passes 1 --filter-mode 2 --rm-threshold 3.5 --rm-min-matches 50 --rm-half-kernel 9 9"
# sgm correlation
# parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.XML $runid/${R}_MP.XML $out/dem $demmp $crop_win --corr-timeout 600 --stereo-algorithm 2 --corr-kernel 5 5 --cost-mode 3 --subpixel-mode 1 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold -1 --min-xcorr-level 1 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 10 --nodata-value 0  $filtering --num-matches-from-disparity 1000
# block matching correlator
parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.XML $runid/${R}_MP.XML $out/dem $demmp $crop_win --corr-timeout 600 --stereo-algorithm 0 --corr-kernel 25 25 --cost-mode 2 --subpixel-mode 2 --subpixel-kernel 25 25 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold 2 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 30 --nodata-value 0  $filtering --num-matches-from-disparity 1000
fi # stereo

#####################################
## rasterize point cloud > DEM
if (($rasterize == 1 )) ; then
echo "rasterize..."
cd $wdir/asp
# rasterize DEM
out=$(echo "$runid/${L}__${R}")
point2dem --t_srs "EPSG:$epsg" --tr $resmp $out/dem-PC.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value -250 --tif-compress None --errorimage --threads 8 --remove-outliers-params 85 3
fi # rasterize

#####################################
## align each DEM independently to AW3D30
if (($stereo_alignment == 1 )) ; then
echo "#### pc_align..."
cd $wdir/asp
out=$(echo "$runid/${L}__${R}")
# get extents of stereo-dem (at 30m grid size)
EXTENTS=$(gdalinfo $out/dem-DEM.tif | awk '/(Lower Left)|(Upper Right)/' | awk '{gsub(/,|\)|\(/," ");print $3 " " $4}' | sed ':a;N;$!ba;s/\n/ /g')
echo "#### crop reference DEM to same size"
gdalwarp -te $EXTENTS -tr 30 30 -tap $dem $out/ref_crop.tif -overwrite
echo "#### align reference DEM to stereo-dem (best if low-res is aligned to high-res... we will use the inverse transform later)"
pc_align --max-displacement 150 --alignment-method point-to-plane $out/dem-DEM.tif $out/ref_crop.tif --save-inv-transformed-reference-points -o $out/trans --outlier-ratio 0.85 --num-iterations 1000 --highest-accuracy --threads $threads --max-num-source-points 1000000
# re-rasterize transformed pointcloud
point2dem --t_srs "$proj" --tr $resmp $out/trans-trans_reference.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value 0 --tif-compress None --errorimage --remove-outliers-params 95 3 --threads $threads --max-valid-triangulation-error 15.0 #trans-trans_reference-DEM.tif
mv $out/trans-trans_reference-DEM.tif $out/dem-DEM_aligned.tif
echo "#### difference aligned stereo-DEM with reference (quick quality control assessment)"
gdalwarp -tr 30 30 -r average -te $EXTENTS $out/dem-DEM_aligned.tif $out/dem-DEM_aligned_30m.tif -overwrite -srcnodata 0 -dstnodata 0 # -tap 
geodiff $out/ref_crop.tif $out/dem-DEM_aligned_30m.tif -o  $out/diff_aligned
echo "#### transform cameras (so they match the aligned DEM)"
cp $out/dem-disp-${L}_MP__${R}_MP.match $out/ba1-${L}__${R}.match
bundle_adjust -t rpc --force-reuse-match-files --skip-matching $L.TIF $R.TIF $L.XML $R.XML -o $out/ba1 --datum wgs84 --threads $threads --initial-transform $out/trans-inverse-transform.txt --max-iterations 0 --robust-threshold 0.5 --num-passes 1
echo "#### mapproject to get final ortho"
for f in $(echo $L $R) ; do
$asp_path/mapproject -t rpc $out/dem-DEM_aligned.tif $f.TIF $f.XML $runid/${f}_ortho_aligned.tif  --nodata-value -250 --threads 4  --tr $res --bundle-adjust-prefix $out/ba1
done
cp dem-DEM_aligned.tif $wdir/asp/multi/${pair_dir}_DEM_aligned.tif
fi # stereo_alignment
#####################################
### END STEREO PAIR LOOP ###
done <$wdir/stereo_overlap_list.txt

#####################################
### DEM MOSAIC + MERGE
cd $wdir/asp/multi
dem_mosaic --tr $resdem --median *DEM.tif -o DEM_merged_median.tif
dem_mosaic --tr $resdem --mean *DEM.tif -o DEM_merged_mean.tif
dem_mosaic --tr $resdem --count *DEM.tif -o DEM_merged_count.tif







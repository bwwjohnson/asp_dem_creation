#Here is a shortened version that works for a single stereo-pair...
#!/bin/bash

# assumes your mosaiced WV stereo image tiles (e.g. img_RnCm...tif) are in the folder wdir (see below), along with the xml files (with the RPCs). Label the raw image mosaics the same, but without the _RnCm string. e.g. 21JUL22060840-P2AS_R1C1-014162243010_01_P001.TIF, 21JUL22060840-P2AS_R1C2-014162243010_01_P001.TIF, etc > 21JUL22060840-P2AS-014162243010_01_P001.TIF
 
# check StereoPipeline path
[[ ":$PATH:" != *":/home/cometsoft/StereoPipeline/bin:"* ]] && PATH="/home/cometsoft/StereoPipeline/bin:${PATH}"

# # get jaxa 30m and 150m reference DEM from polygon shapefile
demdir="/home/cometraid13/benj/khait/asp/jaxa"
epsg="32642"
clip_polygon=ref_dem_clip
clip_shp=$demdir/${clip_polygon}.shp
big_dem=/home/cometraid13/benj/phd/GIS/data/topo/jaxa_from_cometraid4/jaxa_merge_pamir.tif
clipped_dem_wgs84=$demdir/jaxa_ref_wgs84.tif
clipped_dem_utm42=$demdir/jaxa_ref_utm42.tif
clipped_dem_utm42_150=$demdir/jaxa_ref_utm42_150.tif
clipped_dem_utm42_smooth=$demdir/jaxa_ref_utm42_smooth.tif
# # remove files
# rm $clipped_dem_wgs84
# rm $clipped_dem_utm42
# rm $clipped_dem_utm42_150
# rm $clipped_dem_utm42_smooth
# echo clip
# echo $clip_shp
# echo $clip_polygon
# gdalwarp -of GTiff -cutline $clip_shp -cl $clip_polygon -crop_to_cutline -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 $big_dem $clipped_dem_wgs84
# echo "wgs84 --> UTM42"
# gdalwarp -s_srs EPSG:4326 -t_srs EPSG:$epsg -r bilinear -co COMPRESS=DEFLATE -co PREDICTOR=2 -co ZLEVEL=9 -of GTiff $clipped_dem_wgs84 $clipped_dem_utm42
# echo downsample
# gdalwarp -tr 150 150 -r average -of GTiff $clipped_dem_utm42 $clipped_dem_utm42_150
# echo oversample 150m dem, interpolate w cubic spline to make smoothed 30m dem
# gdalwarp -tr 30 30 -r cubicspline -of GTiff $clipped_dem_utm42_150 $clipped_dem_utm42_smooth
# rm $clipped_dem_wgs84



wdir="/home/cometraid13/benj/khait/014162243010_01/014162243010_01_P002_PAN"
dem=$clipped_dem_utm42
demmp=$clipped_dem_utm42_150
processes="4"
threads="12"
mem_lim="300000"
epsg="32642" #NUTM42
resmp="0.3" #res of mapproj images used for stereo (likely is same as resdem)
res="0.3" # res of the final orthos
resdem="0.3" # res of the final DEM

extents_5m="--left-image-crop-win 1349 1469 464 410 --right-image-crop-win 1296 1398 554 495"
extents_2m="--left-image-crop-win 3473 3800 1197 948 --right-image-crop-win 3317 3619 1354 1034"


# P002 mapproject extents
#lhs
# mp_extents="--t_projwin 638131 4340704 638958 4339681"
#rhs
# mp_extents="--t_projwin 638788 4340627 639547 4339728"

mp_extents="--t_projwin 645898 4339044 647514 4339768"

# P002 and P004 extents 
# 645898 4339768 647514 4339044


runid=sgm0.3_p002p004_overlap
# what to run?... 0 = no | 1 = yes

generate_wv="1"
links="0"
mapproject="1"
stereo="1"
rasterize="1"
stereo_alignment="1"
ortho="1"
dem_mosaic="0"


#AOI (for cropping)
# LL="70.55 39.15" #= entire region (all overlaps)
# UR="71.05 39.29"
# LLutm=$(echo $LL | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
# URutm=$(echo $UR | gdaltransform -s_srs EPSG:4326 -t_srs EPSG:$epsg | awk '{print $1,$2}')
# EXTENTS=$(echo $LLutm $URutm)
#lhs
# EXTENTS="638131 4339681 638958 4340704" # opposite convention to --t_projwin!!!
EXTENTS="645898 4339044 647514 4339768"
#rhs
# EXTENTS="638788 4339728 639547 4340627"


# wdir="/home/cometraid13/benj/khait/014162243010_01/014162243010_01_P002_PAN"
# L=21SEP05062131-P2AS-014162243010_01_P002
# R=21SEP05062225-P2AS-014162243010_01_P002

# L=21AUG22060033-P2AS-014162243010_01_P003
# R=21AUG22060122-P2AS-014162243010_01_P003

wdir="/home/cometraid13/benj/khait/014162243010_01/014162243010_01_P004_PAN"
L=21JUL22060914-P2AS-014162243010_01_P004
R=21JUL22061006-P2AS-014162243010_01_P004


# lets go...
cd $wdir
pwd
if (($generate_wv == 1 )) ; then
cd $wdir
# merge tiles
pair=$(ls *XML)
left=$(echo $pair | awk '{print $1}' | sed "s@.XML@@g")
right=$(echo $pair | awk '{print $2}' | sed "s@.XML@@g")
leftp=$(echo $left | sed "s@-@ @g" | awk '{print $1}')
rightp=$(echo $right | sed "s@-@ @g" | awk '{print $1}')
echo variables assigned
gdalwarp -multi -wo NUM_THREADS=val/ALL_CPUS -co BIGTIFF=YES *${leftp}*.TIF $left.TIF
echo gdalwarp left done
gdalwarp -multi -wo NUM_THREADS=val/ALL_CPUS  -co BIGTIFF=YES *${rightp}*.TIF $right.TIF
echo gdalwarp right done
# no wv_correct needed for WV03 + mosaicing is done via gdalwarp (because the RPCs are delivered for the entire tile, a la Pleiades)
fi #generate_wvl



#####################################
## mapproject... for easier stereo matching
if (($mapproject == 1 )) ; then
echo "mapproject..."
mkdir -p $wdir/asp
cd $wdir/asp
rm -r $wdir/asp/$runid
mkdir -p $wdir/asp/$runid
for f in $(echo $L $R) ; do
mapproject -t rpc $demmp $wdir/$f.TIF $wdir/$f.XML $runid/${f}_MP.tif $mp_extents --nodata-value -250 --num-processes $processes --threads $threads --tr $resmp
done
fi #mapproject



#####################################
## run stereo
if (($stereo == 1 )) ; then
echo "stereo..."
cd $wdir/asp
out=$(echo "$runid/${L}__${R}")
rm -r $out  # CAREFUL!
session="-t rpcmaprpc --alignment-method none"
# run stereo...
filtering="--rm-cleanup-passes 1 --filter-mode 2 --rm-threshold 3.5 --rm-min-matches 50 --rm-half-kernel 9 9"
# sgm correlation
parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 2 --corr-kernel 7 7 --cost-mode 3 --subpixel-mode 12 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold -1 --min-xcorr-level 1 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 10 --nodata-value 0  $filtering --num-matches-from-disparity 1000
# block matching correlator
# parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 0 --corr-kernel 25 25 --cost-mode 2 --subpixel-mode 2 --subpixel-kernel 25 25 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold 2 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 30 --nodata-value 0  $filtering --num-matches-from-disparity 1000
# sgm with spm2 
# parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 2 --corr-kernel 7 7 --cost-mode 3 --subpixel-mode 2 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold -1 --min-xcorr-level 1 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 10 --nodata-value 0  $filtering --num-matches-from-disparity 1000
# sgm with 9x9 kernel
# parallel_stereo $session $runid/${L}_MP.tif $runid/${R}_MP.tif $runid/${L}_MP.RPB $runid/${R}_MP.RPB $out/dem $demmp --corr-timeout 600 --stereo-algorithm 2 --corr-kernel 9 9 --cost-mode 3 --subpixel-mode 12 --corr-memory-limit-mb $mem_lim --threads-multiprocess $threads --processes $processes --xcorr-threshold -1 --min-xcorr-level 1 --corr-seed-mode 1 --sgm-collar-size 512 --corr-tile-size 2048 --min-num-ip 10 --nodata-value 0  $filtering --num-matches-from-disparity 1000



fi # stereo

#####################################
## rasterize point cloud > DEM
if (($rasterize == 1 )) ; then
echo "rasterize..."
cd $wdir/asp
# rasterize DEM
out=$(echo "$runid/${L}__${R}")
point2dem --t_srs "EPSG:$epsg" --tr $resmp $out/dem-PC.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value -250 --tif-compress None --errorimage --threads 8 --remove-outliers-params 85 3
# mapproject raw images with basic DEM output
for f in $(echo $L $R) ; do
mapproject -t rpc $out/dem-DEM.tif $wdir/$f.TIF $wdir/$f.xml $runid/${f}_ortho.tif  --nodata-value -250 --threads $threads  --tr $res --bundle-adjust-prefix $out/ba1
done
fi # rasterize

#####################################
## align each DEM independently to AW3D30
if (($stereo_alignment == 1 )) ; then
echo "pc_align..."
cd $wdir/asp
out=$(echo "$runid/${L}__${R}")
# get extents of stereo-dem (at 30m grid size)

# EXTENTS=$(gdalinfo $out/dem-DEM.tif | awk '/(Lower Left)|(Upper Right)/' | awk '{gsub(/,|\)|\(/," ");print $3 " " $4}' | sed ':a;N;$!ba;s/\n/ /g')
echo "####crop reference DEM to same size"
gdalwarp -te $EXTENTS -tr 30 30 -tap $dem $out/ref_crop.tif -overwrite
echo "####align reference DEM to stereo-dem (best if low-res is aligned to high-res... we will use the inverse transform later)"
pc_align --max-displacement 150 --alignment-method point-to-plane $out/dem-DEM.tif $out/ref_crop.tif --save-inv-transformed-reference-points -o $out/trans --outlier-ratio 0.85 --num-iterations 1000 --highest-accuracy --threads $threads --max-num-source-points 1000000
# re-rasterize transformed pointcloud
point2dem --t_srs "$proj" --tr $resmp $out/trans-trans_reference.tif --median-filter-params 9 9 --dem-hole-fill-len 150 --erode-length 0 --nodata-value 0 --tif-compress None --errorimage --remove-outliers-params 95 3 --threads $threads --max-valid-triangulation-error 15.0 #trans-trans_reference-DEM.tif
mv $out/trans-trans_reference-DEM.tif $out/dem-DEM_aligned.tif
echo "####difference aligned stereo-DEM with reference (quick quality control assessment)"
gdalwarp -tr 30 30 -r average -te $EXTENTS $out/dem-DEM_aligned.tif $out/dem-DEM_aligned_30m.tif -overwrite -srcnodata 0 -dstnodata 0 # -tap 
geodiff $out/ref_crop.tif $out/dem-DEM_aligned_30m.tif -o  $out/diff_aligned
echo "####transform cameras (so they match the aligned DEM)"
cp $out/dem-disp-${L}___${R}_.match $out/ba1-${L}__${R}.match
bundle_adjust -t rpc --force-reuse-match-files --skip-matching $wdir/$L.TIF $wdir/$R.TIF $wdir/$L.xml $wdir/$R.xml -o $out/ba1 --datum wgs84 --threads $threads --initial-transform $out/trans-inverse-transform.txt --max-iterations 0 --robust-threshold 0.5 --num-passes 1
echo mapproject to get final ortho
for f in $(echo $L $R) ; do
mapproject -t rpc $out/dem-DEM_aligned.tif $wdir/$f.TIF $wdir/$f.xml $runid/${f}_ortho_aligned.tif  --nodata-value -250 --threads 4  --tr $res --bundle-adjust-prefix $out/ba1
done
fi # stereo_alignment
#####################################



#####################################
## mosaic DEM tiles + smooth DEM (if using a single stereo-pair, this will still be useful for smoothing and filling holes)...
## this part is only necessary if you are mosaicing multiple stereo-pairs... everything above is written for a single stereopair
if (($dem_mosaic == 1 )) ; then
echo "dem_mosaic..."
cd $wdir/asp
# dem_mosaic
rm -r $runid/final_dem/*
out="$runid/final_dem"
dem_mosaic $(ls $runid/*/dem-DEM.tif) -o $out/tajik_2m.tif  --hole-fill-length 250 --threads 4 --tr $resmp --output-nodata-value 0 #--dem-blur-sigma 0.6
dem_mosaic $(ls $runid/*/dem-DEM_aligned.tif) -o $out/tajik_aligned_2m.tif  --hole-fill-length 250 --threads 4 --tr $resmp --output-nodata-value 0
# difference raw DEM
gdalwarp -tr 30 30 -r average -tap $out/tajik_2m.tif $out/tajik_30m.tif -overwrite -srcnodata 0 -dstnodata 0
EXTENTS=$(gdalinfo $out/tajik_30m.tif | awk '/(Lower Left)|(Upper Right)/' | awk '{gsub(/,|\)|\(/," ");print $3 " " $4}' | sed ':a;N;$!ba;s/\n/ /g')
gdalwarp -te $EXTENTS $dem $out/ref_crop.tif -overwrite
gdalwarp -tr 30 30 -r average -tap -te $EXTENTS $out/tajik_aligned_2m.tif $out/tajik_aligned_30m.tif -overwrite
geodiff $out/ref_crop.tif $out/tajik_30m.tif -o  $out/diff
geodiff $out/ref_crop.tif $out/tajik_aligned_30m.tif -o  $out/diff_aligned
# mosaic orthos
rm -r $runid/final_dem/*
out="$runid/final_dem/final_ortho"
dem_mosaic $(ls $runid/*/*ortho.tif) -o $out/tajik_ortho_mosaic_${res}m.tif  --hole-fill-length 250 --threads 4 --tr $res --output-nodata-value 0
dem_mosaic $(ls $runid/*/*ortho_aligned.tif) -o $out/tajik_ortho_mosaic_aligned_2m.tif  --hole-fill-length 250 --threads 4 --tr $res --output-nodata-value 0
fi # dem_mosaic
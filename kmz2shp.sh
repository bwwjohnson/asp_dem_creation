#!/bin/bash

# unzip kmz
for f in *.KMZ; do unzip -o $f; done

# tidy
rm *.JPG
rm *.png

# convert kml to shapefile folder
for f in *KML; do ogr2ogr -f "ESRI Shapefile" -skipfailures `basename $f .KML`.shp $f; done

# remove spaces from AOI Produced.shp name
for f in *.shp; do cd $f; rename 's/ /_/g' *; cd ..; done


# move aoi polygon out of shapefile folder
for f in *.shp; do
aoi=`echo $f | awk -F"_" '{print $NF}' | awk -F"." '{print $1}'`
for g in dbf prj shp shx; do mv $f/AOI*.$g ./$aoi.$g; done
rm -r $f
done

rm *.KML

#!/bin/bash

source ~/miniconda3/etc/profile.d/conda.sh
conda activate gdal

for dir in 7*1; do gdal_translate $dir/*_P_*/DIM*XML ./$dir.TIF ; done
for dir in 7*1; do cp $dir/*_P_*/DIM*XML ./$dir.XML ; done
for dir in 7*1; do cp $dir/*_P_*/RPC*XML ./$dir.RPC ; done

#!/bin/bash
EXTENSIONS=$(find build -name *\.stripped)

TOTAL_LOADED_SIZE=0
TOTAL_BINARY_SIZE=0

for EXTENSION in $EXTENSIONS;
do
	LOADED_SIZE=$(size -G $EXTENSION | tail -1 | awk '{print $4}');
	IMAGE_SIZE=$(du -b $EXTENSION | awk '{print $1;}');
	echo "$EXTENSION: $LOADED_SIZE / $IMAGE_SIZE ";
	TOTAL_LOADED_SIZE=$(expr $TOTAL_LOADED_SIZE + $LOADED_SIZE)
	TOTAL_BINARY_SIZE=$(expr $TOTAL_BINARY_SIZE + $IMAGE_SIZE)
done

TOTAL_OVERHEAD=$(expr $TOTAL_BINARY_SIZE - $TOTAL_LOADED_SIZE)

echo "Total image size: $TOTAL_BINARY_SIZE Total loaded size: $TOTAL_LOADED_SIZE overhead: $TOTAL_OVERHEAD"

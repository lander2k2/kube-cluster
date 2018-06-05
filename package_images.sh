#!/bin/bash

USAGE=$(cat <<END
Package up some images for preloading

Usage: ./package_images.sh [-h] <file>

Required argument:
file - a file containing the images to package; one image per line
END
)

if [ "$1" = "-h" ]; then
    echo "$USAGE"
    exit 0
elif [ "$1" = "" ]; then
    echo "Error: missing file argument"
    echo "$USAGE"
    exit 1
fi

IMAGE_FILE=$1

if [ ! -f $IMAGE_FILE ]; then
    echo "Error: no file found at $IMAGE_FILE"
    echo "$USAGE"
    exit 1
fi

set -e

IMAGES=$(cat $IMAGE_FILE)
IMAGE_STR=""

for img in $IMAGES; do
    docker pull $img
    IMAGE_STR="$IMAGE_STR $img"
done

docker save --output images/$IMAGE_FILE.tar $IMAGE_STR

exit 0


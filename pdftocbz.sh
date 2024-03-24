#!/bin/bash

# Check if an argument is provided
if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Assign the directory argument to a variable
DIR=$1

# Check if the provided directory exists
if [ ! -d "$DIR" ]; then
    echo "Error: Directory '$DIR' does not exist."
    exit 1
fi

# Iterate over files in the provided directory
for file in "$DIR"/*; do
    if [ -f "$file" ]; then
        echo "Processing file: $file"
	filename="${file%.*}"
	echo "$filename"
	mkdir "$DIR/output"
	pdftoppm -jpeg -r 300 "$file" "$DIR/output/output"
	echo "$filename.cbz"
        zip -r "$filename.cbz" "$DIR/output"
	rm -r "$DIR/output"
    fi
done


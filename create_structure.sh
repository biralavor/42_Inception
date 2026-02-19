#!/bin/bash

# Array to track the current path at each indentation level
declare -a path_stack

# Read the tree structure from README.md (lines 31-53)
sed -n '31,53p' README.md | while IFS= read -r line; do
  # Skip empty lines
  [[ -z "$line" ]] && continue
  
  # Calculate indentation level (each level is 4 spaces)
  indent=$(echo "$line" | sed 's/[^ │].*//' | wc -c)
  indent=$((indent / 4))
  
  # Remove tree drawing characters and whitespace
  name=$(echo "$line" | sed 's/.*[├└]── //' | sed 's/│   //' | sed 's/^[ ]*//')
  
  # Skip if name is empty
  [[ -z "$name" ]] && continue
  
  # Build the full path
  path_stack[$indent]="$name"
  full_path=""
  for ((i=0; i<=indent; i++)); do
    if [[ -n "${path_stack[$i]}" ]]; then
      if [[ -z "$full_path" ]]; then
        full_path="${path_stack[$i]}"
      else
        full_path="$full_path${path_stack[$i]}"
      fi
    fi
  done
  
  # Check if it's a directory (ends with /)
  if [[ "$full_path" == */ ]]; then
    dir_path="${full_path%/}"
    mkdir -p "$dir_path"
    echo "Created directory: $dir_path"
  else
    # It's a file
    file_path="$full_path"
    dir_name=$(dirname "$file_path")
    if [[ "$dir_name" != "." ]]; then
      mkdir -p "$dir_name"
    fi
    touch "$file_path"
    echo "Created file: $file_path"
  fi
done

echo "Directory structure created successfully!"

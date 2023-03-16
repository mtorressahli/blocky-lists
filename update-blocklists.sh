#!/bin/bash

# Initialize optional variables with default values
OUTPUT_DIR=""
SOURCELISTS_PATH=""
LOG_FILE=""
PUSH_TO_GITHUB=true

# Parse optional arguments
while getopts "o:s:l:p" opt; do
  case $opt in
    o)
      OUTPUT_DIR="$OPTARG"
      ;;
    s)
      SOURCELISTS_PATH="$OPTARG"
      ;;
    l)
      LOG_FILE="$OPTARG"
      ;;
    p)
      PUSH_TO_GITHUB=false
      ;;
    *)
      echo "Usage: $0 [-o OUTPUT_DIR] [-s SOURCELISTS_PATH] [-l LOG_FILE] [-p] [REPO_DIR] REPO_URL"
      exit 1
      ;;
  esac
done

# Shift arguments to remove the optional flags that have already been parsed
shift $((OPTIND-1))

# Check if the correct number of non-optional arguments is provided
if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "Usage: $0 [-o OUTPUT_DIR] [-s SOURCELISTS_PATH] [-l LOG_FILE] [-p] [REPO_DIR] REPO_URL"
  exit 1
fi

# Assign non-optional arguments to variables
if [ "$#" -eq 1 ]; then
  REPO_DIR="$(pwd)/blocky-lists"
  REPO_URL="$1"
else
  REPO_DIR="$1"
  REPO_URL="$2"
fi

# Set default values for OUTPUT_DIR and SOURCELISTS_PATH if not provided
if [ -z "$OUTPUT_DIR" ]; then
  OUTPUT_DIR="$REPO_DIR/blocklists"
fi

if [ -z "$SOURCELISTS_PATH" ]; then
  SOURCELISTS_PATH="$REPO_DIR/blocklists/sourcelists.md"
fi

# Redirect stdout and stderr to the log file if provided
if [ -n "$LOG_FILE" ]; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

# Pull github repo
echo
echo           "#######################"
echo -e "\033[1m# Pulling Github repo #\033[0m"
echo           "#######################"
echo

# Clone the repository if it doesn't exist
if [ ! -d "$REPO_DIR" ]; then
  echo "Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

# Move to the repository directory
cd "$REPO_DIR"

# Pull any changes to the repository
echo "Pulling changes from repository..."
git pull


# Download blocklists in parallel
echo
echo           "######################################"
echo -e "\033[1m# Downloading blocklists by category #\033[0m"
echo           "######################################"
echo

# Define a function to download a blocklist
download_blocklist() {
  line="$1"
  category="$2"
  raw_output="$OUTPUT_DIR/$category-raw.txt"
  consolidated_output="$OUTPUT_DIR/$category-consolidated.txt"
  echo "For category $category: Downloading $line"
  if ! curl -sL "$line" | awk '!a[$0]++' >> "$raw_output"; then
    echo "Error: Could not download blocklist file: $line" >&2
    return
  fi
}

while read line; do
  # Check if the line starts with a hash (#) character
  if [[ $line =~ ^# ]]; then
    # Extract the category name from the line
    category="${line#"# "}"
    # Create a new output file for this category
    raw_output="$OUTPUT_DIR/$category-raw.txt"
    consolidated_output="$OUTPUT_DIR/$category-consolidated.txt"
    # Delete any existing files
    rm -f "$raw_output" "$consolidated_output"
#    echo
#    echo -e "\033[1mDownloading lists from $category category\033[0m"
  fi

  # Check if the line is a valid URL and download the blocklist
  if [[ $line =~ ^https?:// ]]; then
    download_blocklist "$line" "$category" &
  fi
done < "$SOURCELISTS_PATH"

# Wait for all downloads to complete
wait


# Consolidate all category files into full-raw.txt and full-consolidated.txt files
echo
echo "###################################"
echo -e "\033[1m# Consolidating lists by category #\033[0m"
echo "###################################"
echo

# Define a function to consolidate a category-specific blocklist
consolidate_category_lists() {
  raw_output="$1"
  category="$(basename "${raw_output%-raw.txt}")"
  if [[ $category == full ]]; then
    return
  fi
  consolidated_output="$OUTPUT_DIR/$category-consolidated.txt"
  echo "Consolidating blocklists for $category"
  sort -u "$raw_output" -o "$consolidated_output"

  # Calculate unique and shared lines
  unique_raw="$(comm -23 <(sort "$raw_output") <(sort "$consolidated_output") | wc -l)"
  unique_consolidated="$(comm -23 <(sort "$consolidated_output") <(sort "$raw_output") | wc -l)"
  shared="$(comm -12 <(sort "$raw_output") <(sort "$consolidated_output") | wc -l)"

  # Verify that consolidation was successful
  if [[ $unique_consolidated -ne 0 || $shared -gt $(wc -l < "$raw_output") ]]; then
    echo "Error: Consolidation failed for $category" >&2
    continue
  fi

  # Print results
  total_lines="$(wc -l < "$raw_output")"
  unique_pct=$(awk "BEGIN { printf \"%.2f\", ${unique_consolidated}/${total_lines}*100 }")
  shared_pct=$(awk "BEGIN { printf \"%.2f\", ${shared}/${total_lines}*100 }")
  echo "Consolidation succeeded for $category ($shared/$total_lines lines shared, $shared_pct%)"
}


# Consolidate each category-specific blocklist
for raw_output in "$OUTPUT_DIR"/*-raw.txt; do
  consolidate_category_lists "$raw_output" &
done

# Wait for all consolidations to complete
wait

# Remove duplicates between all pairs of category-specific files
echo
echo           "##########################################"
echo -e "\033[1m# Removing duplicates between categories #\033[0m"
echo           "##########################################"
echo


remove_duplicates() {
  high_priority_file="$1"
  low_priority_file="$2"
  tmp_file="$(mktemp)"

  # Remove duplicates from the low priority file
  duplicates_removed=$(comm -12 <(sort "$high_priority_file") <(sort "$low_priority_file") | wc -l)
  comm -23 <(sort "$low_priority_file") <(sort "$high_priority_file") > "$tmp_file"

  # Replace the low priority file with the temporary file
  mv "$tmp_file" "$low_priority_file"

  echo "Removed $duplicates_removed duplicates between $(basename "$high_priority_file") and $(basename "$low_priority_file")"

  # Update the global variable
  last_duplicates_removed=$duplicates_removed
}

# Extract categories from sourcelists.md file
categories=()
while read line; do
  if [[ $line =~ ^# ]]; then
    category="${line#"# "}"
    categories+=("$category")
  fi
done < "$SOURCELISTS_PATH"

num_categories=${#categories[@]}

# Array to store the total number of duplicates removed per file
declare -A total_duplicates_removed
last_duplicates_removed=0

# Initialize the total_duplicates_removed array
for category in "${categories[@]}"; do
  total_duplicates_removed["$OUTPUT_DIR/${category}-consolidated.txt"]=0
done

# Remove duplicates and update the total_duplicates_removed array
for ((i = 0; i < num_categories - 1; i++)); do
  for ((j = i + 1; j < num_categories; j++)); do
    high_priority_file="$OUTPUT_DIR/${categories[$i]}-consolidated.txt"
    low_priority_file="$OUTPUT_DIR/${categories[$j]}-consolidated.txt"
    remove_duplicates "$high_priority_file" "$low_priority_file"
    total_duplicates_removed["$low_priority_file"]=$((total_duplicates_removed["$low_priority_file"] + last_duplicates_removed))
  done
done

echo
echo "Summary:"
echo "---------"

# Print the summary for each file
for category in "${categories[@]}"; do
  file="$OUTPUT_DIR/${category}-consolidated.txt"
  original_count=$(wc -l < "$file")
  duplicates_removed=${total_duplicates_removed["$file"]}
  retained_count=$((original_count - duplicates_removed))
  percentage_retained=$(awk "BEGIN {printf \"%.2f\", $retained_count / $original_count * 100}")
  echo "$duplicates_removed lines removed from $(basename "$file") – $percentage_retained% retained"
done


echo
echo           "################################################################################"
echo -e "\033[1m# Consolidating all category files into full-raw.txt and full-consolidated.txt #\033[0m"
echo           "################################################################################"
echo

# Remove previously existing full-*.txt files
full_raw="$OUTPUT_DIR/full-raw.txt"
full_consolidated="$OUTPUT_DIR/full-consolidated.txt"
rm -f "$full_raw" "$full_consolidated"

# Concatenate all consolidated files into a full-raw.txt file
echo "Concatenating all category-specific consolidated files into full-raw.txt"
cat "$OUTPUT_DIR"/*-consolidated.txt > "$OUTPUT_DIR/full-raw.txt"


# Consolidating unique addresses of full-raw.txt into full-consolidated.txt
echo
echo "Consolidating full-raw.txt into full-consolidated.txt"
sort -u "$full_raw" -o "$full_consolidated"

# Check if consolidation was successful
echo "Checking if consolidation succeeded"

# Calculate unique and shared lines
unique_raw_full="$(comm -23 <(sort "$full_raw") <(sort "$full_consolidated") | wc -l)"
unique_consolidated_full="$(comm -23 <(sort "$full_consolidated") <(sort "$full_raw") | wc -l)"
shared_full="$(comm -12 <(sort "$full_raw") <(sort "$full_consolidated") | wc -l)"

# Verify that consolidation was successful
if [[ $unique_consolidated_full -ne 0 || $shared_full -gt $(wc -l < "$full_raw") ]]; then
  echo "Error: Consolidation failed for full-raw.txt" >&2
else
  # Print results
  total_lines_full="$(wc -l < "$full_raw")"
  unique_pct_full=$(awk "BEGIN { printf \"%.2f\", ${unique_consolidated_full}/${total_lines_full}*100 }")
  shared_pct_full=$(awk "BEGIN { printf \"%.2f\", ${shared_full}/${total_lines_full}*100 }")
  echo "Consolidation succeeded for full-raw.txt ($shared_full/$total_lines_full lines shared, $shared_pct_full%)"
fi


# Print completion message
echo
echo "Done! Output files are located in $OUTPUT_DIR."

if $PUSH_TO_GITHUB; then
  # Push to github repo
  echo
  echo           "##########################"
  echo -e "\033[1m# Pushing to Github repo #\033[0m"
  echo           "##########################"
  echo

  # Move to the output directory
  cd "$OUTPUT_DIR"

  # Add all files to git
  echo "Adding files to Git..."
  git add .

  # Commit the changes
  echo "Committing changes..."
  git commit -m "Updated blocklists $(date +%F)"

  # Push changes to the remote repository
  echo "Pushing changes to remote repository..."
  git push

  # Move back to the original directory
  cd -
else
  echo "Skipping push to GitHub repo."
fi

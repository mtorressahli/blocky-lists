#!/bin/bash

# Define the output directory and git repo paths
OUTPUT_DIR="/mnt/apps/opt/tools/blocky-lists/blocklists"
REPO_DIR="/mnt/apps/opt/tools/blocky-lists"
REPO_URL="https://github.com/mtorressahli/blocky-lists.git"

# Define the path to the local copy of the Markdown file
SOURCELISTS_PATH="/mnt/apps/opt/tools/blocky-lists/blocklists/sourcelists.md"

# Git username and email
GIT_USERNAME="mtorressahli"
GIT_EMAIL="mtorressahli@gmail.com"

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
git config user.name "$GIT_USERNAME"
git config user.email "$GIT_EMAIL"
git commit -m "Updated blocklists $(date +%F)"

# Push changes to the remote repository
echo "Pushing changes to remote repository..."
git push

# Move back to the original directory
cd -

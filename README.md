# blocky-lists

Blocklists compiled from several sources.

The core of the repo is a shell script – `update-blocklists.sh` – that downloads, consolidates, and deduplicates domain blocklists from various sources defined in `blocklists/sourcelists.md`. The script accepts optional arguments to customize the output directory, the source lists file, and to toggle pushing the results to a GitHub repository.

Here's a summary of the script's functionality:

- Parse optional arguments and set default values for output directory, source lists file, and log file.
- Clone the specified GitHub repository if it doesn't exist, or pull the latest changes if it does.
- Extract categories from the source lists file and download the blocklists in parallel.
- Print a summary of the downloads, including any failed downloads.
- Consolidate all category files into full-raw.txt and full-consolidated.txt files.
- Remove duplicates between all pairs of category-specific files.
- Create simple-named category files and deduplicated category files.
- Consolidate all category files into full-raw.txt and full-consolidated.txt files.
- If the -p flag is not set, push the updated blocklists to the GitHub repository.

The script uses several helper functions to download blocklists, consolidate category lists, remove duplicates, and more. It uses curl, awk, sort, comm, wc, rm, cp, mv, and git command-line utilities to perform its tasks.

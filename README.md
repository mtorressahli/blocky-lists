# blocky-lists

Blocklists compiled from several sources.

## Blocklist updater – `update-blocklists.sh`

This script downloads and consolidates blocklists from different sources and categories specified in a sourcelists markdown file. It removes duplicates between categories and generates simple-named category files and deduplicated category files. Optionally, it can also push the generated blocklists to a GitHub repository.

### Usage

```bash
./blocklist-updater.sh [-o OUTPUT_DIR] [-s SOURCELISTS_PATH] [-l LOG_FILE] [-p] [REPO_DIR] REPO_URL
```

### Options

- `-o OUTPUT_DIR`: The output directory for the generated blocklists. Defaults to `REPO_DIR/blocklists`.
- `-s SOURCELISTS_PATH`: The path to the sourcelists markdown file. Defaults to `REPO_DIR/blocklists/sourcelists.md`.
- `-l LOG_FILE`: The path to the log file. If provided, the script will log its output to this file.
- `-p`: Disables pushing to the GitHub repository.

### Arguments

- `REPO_DIR`: The local directory of the GitHub repository. Defaults to the current working directory (`./blocky-lists`).
- `REPO_URL`: The URL of the GitHub repository.

### Example

```bash
bash ./blocklist-updater.sh -o ./output -s ./sourcelists.md -l ./log.txt -p ./blocky-lists https://github.com/mtorressahli/blocky-lists.git
```

This command will:

1. Download blocklists to the `./output` directory.
2. Use the sources listed in `./sourcelists.md`.
3. Log the output to `./log.txt`.
4. Disable pushing to the GitHub repository.
5. Use the local repository directory `./blocky-lists`.
6. Clone or pull the repository at `https://github.com/mtorressahli/blocky-lists.git`.

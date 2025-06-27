#!/bin/bash

set -euo pipefail

# Default values
DPI=300
FORMAT="jpeg"
FORCE=false
VERBOSE=false
QUIET=false
DRY_RUN=false

# Function to show usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] <directory>

Convert PDF files to CBZ format.

OPTIONS:
    -d, --dpi DPI       Set DPI for image extraction (default: 300)
    -f, --format FMT    Image format: jpeg, png (default: jpeg)
    --force             Overwrite existing CBZ files
    -v, --verbose       Verbose output
    -q, --quiet         Quiet mode (minimal output)
    -n, --dry-run       Show what would be done without executing
    -h, --help          Show this help message

EXAMPLES:
    $0 /path/to/pdfs
    $0 --dpi 600 --format png /path/to/pdfs
    $0 --force --verbose /path/to/pdfs
EOF
}

# Function to log messages
log() {
    if [[ "$QUIET" == false ]]; then
        echo "$@" >&2
    fi
}

# Function to log verbose messages
log_verbose() {
    if [[ "$VERBOSE" == true ]]; then
        echo "[VERBOSE] $@" >&2
    fi
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v pdftoppm >/dev/null 2>&1; then
        missing_deps+=("pdftoppm (install poppler-utils)")
    fi
    
    if ! command -v zip >/dev/null 2>&1; then
        missing_deps+=("zip")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies:" >&2
        printf "  - %s\n" "${missing_deps[@]}" >&2
        exit 2
    fi
}

# Function to validate PDF file
is_pdf_file() {
    local file="$1"
    [[ "${file,,}" == *.pdf ]] && [[ -f "$file" ]]
}

# Function to get PDF page count
get_page_count() {
    local pdf_file="$1"
    if command -v pdfinfo >/dev/null 2>&1; then
        pdfinfo "$pdf_file" 2>/dev/null | grep "Pages:" | awk '{print $2}' || echo "?"
    else
        echo "?"
    fi
}

# Function to convert single PDF
convert_pdf() {
    local pdf_file="$1"
    local base_name="${pdf_file%.*}"
    local cbz_file="${base_name}.cbz"
    
    # Skip if CBZ exists and not forcing
    if [[ -f "$cbz_file" && "$FORCE" == false ]]; then
        log "Skipping $pdf_file (CBZ already exists, use --force to overwrite)"
        return 0
    fi
    
    local page_count
    page_count=$(get_page_count "$pdf_file")
    
    if [[ "$DRY_RUN" == true ]]; then
        log "Would convert: $pdf_file -> $cbz_file ($page_count pages)"
        return 0
    fi
    
    log "Converting: $(basename "$pdf_file") -> $(basename "$cbz_file") ($page_count pages)"
    
    # Create unique temporary directory
    local temp_dir
    temp_dir=$(mktemp -d -t pdftocbz.XXXXXX) || {
        echo "Error: Failed to create temporary directory" >&2
        return 3
    }
    
    # Ensure cleanup on exit
    trap "rm -rf '$temp_dir'" EXIT
    
    # Convert PDF to images
    log_verbose "Extracting images to $temp_dir"
    if ! pdftoppm -"$FORMAT" -r "$DPI" "$pdf_file" "$temp_dir/page"; then
        echo "Error: Failed to convert PDF pages: $pdf_file" >&2
        rm -rf "$temp_dir"
        return 4
    fi
    
    # Check if any images were created
    if ! ls "$temp_dir"/page* >/dev/null 2>&1; then
        echo "Error: No images were extracted from: $pdf_file" >&2
        rm -rf "$temp_dir"
        return 5
    fi
    
    # Create CBZ file
    log_verbose "Creating CBZ archive: $cbz_file"
    if ! (cd "$temp_dir" && zip -q -r "$cbz_file" page*); then
        echo "Error: Failed to create CBZ file: $cbz_file" >&2
        rm -rf "$temp_dir"
        return 6
    fi
    
    # Move CBZ to final location if created in temp dir
    if [[ -f "$temp_dir/$(basename "$cbz_file")" ]]; then
        mv "$temp_dir/$(basename "$cbz_file")" "$cbz_file"
    fi
    
    # Cleanup
    rm -rf "$temp_dir"
    trap - EXIT
    
    log_verbose "Successfully created: $cbz_file"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dpi)
            DPI="$2"
            if ! [[ "$DPI" =~ ^[0-9]+$ ]] || [[ "$DPI" -lt 72 ]] || [[ "$DPI" -gt 2400 ]]; then
                echo "Error: DPI must be a number between 72 and 2400" >&2
                exit 1
            fi
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            if [[ "$FORMAT" != "jpeg" && "$FORMAT" != "png" ]]; then
                echo "Error: Format must be 'jpeg' or 'png'" >&2
                exit 1
            fi
            shift 2
            ;;
        --force)
            FORCE=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -q|--quiet)
            QUIET=true
            shift
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Check if directory argument is provided
if [[ $# -ne 1 ]]; then
    echo "Error: Directory argument required" >&2
    usage >&2
    exit 1
fi

DIR="$1"

# Validate directory
if [[ ! -d "$DIR" ]]; then
    echo "Error: Directory '$DIR' does not exist." >&2
    exit 1
fi

# Check dependencies
check_dependencies

# Find PDF files
mapfile -d '' pdf_files < <(find "$DIR" -maxdepth 1 -name "*.pdf" -o -name "*.PDF" -print0 2>/dev/null)

if [[ ${#pdf_files[@]} -eq 0 ]]; then
    log "No PDF files found in: $DIR"
    exit 0
fi

log_verbose "Found ${#pdf_files[@]} PDF file(s)"
log_verbose "DPI: $DPI, Format: $FORMAT"

# Process each PDF file
success_count=0
error_count=0

for pdf_file in "${pdf_files[@]}"; do
    if convert_pdf "$pdf_file"; then
        ((success_count++))
    else
        ((error_count++))
        log "Failed to convert: $(basename "$pdf_file")"
    fi
done

# Summary
if [[ "$QUIET" == false && ${#pdf_files[@]} -gt 1 ]]; then
    echo
    log "Conversion complete: $success_count successful, $error_count failed"
fi

# Exit with error code if any conversions failed
[[ $error_count -eq 0 ]]


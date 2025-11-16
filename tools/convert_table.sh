#!/bin/bash

# Script to convert table_cells JSON to human-readable table format
# Usage: ./convert_table.sh <input_json_file> [output_file]

set -e

INPUT_FILE="${1:-bug-table.json}"
OUTPUT_FILE="${2:-}"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found" >&2
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first." >&2
    exit 1
fi

# Function to format a cell value
format_cell() {
    local sample_slot=$1
    local volume=$2
    local pitch=$3
    
    # Check if cell is empty (all -1)
    if [ "$sample_slot" = "-1" ] && [ "$volume" = "-1" ] && [ "$pitch" = "-1" ]; then
        printf "%-18s" "---"
    else
        # Handle negative values
        local vol_str
        local pitch_str
        if [ "$volume" = "-1" ]; then
            vol_str="-1.00"
        else
            vol_str=$(printf "%.2f" "$volume")
        fi
        if [ "$pitch" = "-1" ]; then
            pitch_str="-1.00"
        else
            pitch_str=$(printf "%.2f" "$pitch")
        fi
        printf "%-18s" "S:$sample_slot V:$vol_str P:$pitch_str"
    fi
}

# Strip comments and extract table data
# Remove /* */ style comments from JSON
CLEAN_JSON=$(sed '/^\/\*/d; /^\s*\*/d; /^\s*\*\//d' "$INPUT_FILE" | sed 's|/\*.*\*/||g')
TABLE_DATA=$(echo "$CLEAN_JSON" | jq -c '.snapshot.source.table')
TABLE_CELLS=$(echo "$TABLE_DATA" | jq -c '.table_cells')
SECTIONS=$(echo "$TABLE_DATA" | jq -c '.sections')

# Get number of rows
NUM_ROWS=$(echo "$TABLE_CELLS" | jq 'length')
NUM_SECTIONS=$(echo "$SECTIONS" | jq 'length')

# Function to check if a row is the start of a section
is_section_start() {
    local row=$1
    local section_idx=$2
    local start_step=$(echo "$SECTIONS" | jq -r ".[$section_idx].start_step")
    if [ "$row" = "$start_step" ]; then
        return 0
    fi
    return 1
}

# Function to get section info for a row
get_section_info() {
    local row=$1
    for ((i=0; i<NUM_SECTIONS; i++)); do
        local start_step=$(echo "$SECTIONS" | jq -r ".[$i].start_step")
        local num_steps=$(echo "$SECTIONS" | jq -r ".[$i].num_steps")
        local end_step=$((start_step + num_steps - 1))
        if [ "$row" -ge "$start_step" ] && [ "$row" -le "$end_step" ]; then
            if [ "$row" = "$start_step" ]; then
                echo "$i|$start_step|$num_steps|START"
            else
                echo "$i|$start_step|$num_steps|CONTINUE"
            fi
            return 0
        fi
    done
    echo "|||UNKNOWN"
}

# Process output
{
    # Print header
    printf "%-6s" "Row"
    for col in {0..15}; do
        printf "%-18s" "Col $col"
    done
    echo ""
    
    # Print separator
    printf "%*s\n" 300 "" | tr ' ' '-'
    
    # Print each row
    for ((row=0; row<NUM_ROWS; row++)); do
        # Check if this is a section start
        SECTION_INFO=$(get_section_info "$row")
        SECTION_NUM=$(echo "$SECTION_INFO" | cut -d'|' -f1)
        SECTION_START=$(echo "$SECTION_INFO" | cut -d'|' -f2)
        SECTION_STEPS=$(echo "$SECTION_INFO" | cut -d'|' -f3)
        SECTION_STATUS=$(echo "$SECTION_INFO" | cut -d'|' -f4)
        
        # Add section separator if this is a section start
        if [ "$SECTION_STATUS" = "START" ]; then
            echo ""
            printf "%*s\n" 300 "" | tr ' ' '='
            printf "SECTION %s: Steps %s-%s (Length: %s steps)\n" "$((SECTION_NUM + 1))" "$SECTION_START" "$((SECTION_START + SECTION_STEPS - 1))" "$SECTION_STEPS"
            printf "%*s\n" 300 "" | tr ' ' '='
            echo ""
        fi
        
        # Print row number with section indicator
        if [ "$SECTION_STATUS" = "START" ]; then
            printf "%-6s" "[$row]"
        else
            printf "%-6d" "$row"
        fi
        
        # Get the row
        ROW=$(echo "$TABLE_CELLS" | jq -c ".[$row]")
        
        # Print each cell in the row (16 columns)
        for col in {0..15}; do
            CELL=$(echo "$ROW" | jq -c ".[$col]")
            SAMPLE_SLOT=$(echo "$CELL" | jq -r '.sample_slot')
            VOLUME=$(echo "$CELL" | jq -r '.settings.volume')
            PITCH=$(echo "$CELL" | jq -r '.settings.pitch')
            
            format_cell "$SAMPLE_SLOT" "$VOLUME" "$PITCH"
            printf " "
        done
        echo ""
    done
    
} | if [ -n "$OUTPUT_FILE" ]; then
    tee "$OUTPUT_FILE"
else
    cat
fi

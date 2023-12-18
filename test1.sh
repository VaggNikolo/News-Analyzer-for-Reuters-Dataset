#!/bin/bash

declare -A categories_per_document
declare -A terms_per_document
declare -A term_id_to_stem
declare -A stem_to_term_id
declare -A doc_per_term
declare -A doc_per_category
declare -A jaccard_index

# Function definitions

# Parses the qrels file and returns a mapping of each document ID to a list of categories


parse_categories_per_document() {
    local filepath=$1

    while IFS=' ' read -r category document_id _; do
        if [[ -n "$document_id" ]]; then
            # Append the category to the existing string, separated by spaces
            categories_per_document["$document_id"]+="${category} "
        fi
    done < "$filepath"
}

# Parses multiple vectors files and returns a mapping of each document ID to a list of term IDs
parse_terms_in_documents() {
    local filepath=$1

    while IFS=' ' read -r document_id terms; do
        if [[ -n "$document_id" ]]; then
            # Extract just the term IDs (ignoring the weights) and append them to the string
            term_ids=$(echo "$terms" | grep -oE '[0-9]+:' | sed 's/://g')
            for term_id in $term_ids; do
                terms_per_document["$document_id"]+="${term_id} "
            done
        fi
    done < "$filepath"
}

# Parses the stem-term-idf map file and returns a mapping of term IDs to stems and vice versa
parse_tid_to_stem() {
    local filepath=$1
    local line_counter=0

    while IFS=' ' read -r stem term_id _; do
        ((line_counter++))
        # Skip the first two lines
        if [ "$line_counter" -le 2 ]; then
            continue
        fi

        # Skip stems consisting of underscores only
        if [ "$stem" = "______" ]; then
            continue
        fi

        # Populate both mappings: term_id to stem and stem to term_id
        term_id_to_stem["$term_id"]="$stem"
        stem_to_term_id["$stem"]="$term_id"
    done < "$filepath"
}

# Precomputes DOC(T) and DOC(C)
precompute_doc_sets() {
    # Precompute DOC(T)
    for document_id in "${!terms_per_document[@]}"; do
        for term_id in ${terms_per_document[$document_id]}; do
            doc_per_term["$term_id"]+="${document_id} "
        done
    done

    # Precompute DOC(C)
    for document_id in "${!categories_per_document[@]}"; do
        for category in ${categories_per_document[$document_id]}; do
            doc_per_category["$category"]+="${document_id} "
        done
    done
}

# Calculates the Jaccard Index
calculate_jaccard_index() {
    for term_id in "${!doc_per_term[@]}"; do
        local term_docs=(${doc_per_term[$term_id]})

        for category in "${!doc_per_category[@]}"; do
            local category_docs=(${doc_per_category[$category]})
            local intersection=($(echo "${term_docs[@]}" "${category_docs[@]}" | tr ' ' '\n' | sort | uniq -d))
            local union=($(echo "${term_docs[@]}" "${category_docs[@]}" | tr ' ' '\n' | sort | uniq))

            local intersection_count=${#intersection[@]}
            local union_count=${#union[@]}

            # Calculate Jaccard Index and store in jaccard_index array
            if [ "$union_count" -ne 0 ]; then
                jaccard_index["$term_id,$category"]=$(echo "$intersection_count / $union_count" | bc -l)
            else
                jaccard_index["$term_id,$category"]=0
            fi
        done
    done
}

# Handles user commands
handle_command() {
    local command=$1
    local args=($command)
    local command_type=${args[0]}

    case $command_type in
        '@')
            local category=${args[1]}
            local k=${args[2]}
            show_top_k_stems_for_category "$category" "$k"
            ;;
        '#')
            local stem=${args[1]}
            local k=${args[2]}
            show_top_k_categories_for_stem "$stem" "$k"
            ;;
        '$')
            local stem=${args[1]}
            local category=${args[2]}
            show_jaccard_index_for_pair "$stem" "$category"
            ;;
        'P')
            local doc_id=${args[1]}
            local switch=${args[2]}
            show_stems_or_categories_for_document "$doc_id" "$switch"
            ;;
        'C')
            local doc_id=${args[1]}
            local switch=${args[2]}
            count_terms_or_categories_for_document "$doc_id" "$switch"
            ;;
        '*')
            echo "Invalid command."
            ;;
    esac
}

show_top_k_stems_for_category() {
    local category=$1
    local k=$2
    local count=0

    # Create a temporary file for sorting
    local temp_file=$(mktemp)

    # Collect Jaccard Index scores for the category and store in the temporary file
    for key in "${!jaccard_index[@]}"; do
        if [[ $key == *",$category" ]]; then
            echo "${jaccard_index[$key]} $key" >> "$temp_file"
        fi
    done

    # Sort the scores and extract the top k stems
    sort -nr $temp_file | while read -r line && (( count < k )); do
        local score=$(echo $line | cut -d ' ' -f1)
        local term_id=$(echo $line | cut -d ' ' -f2 | cut -d ',' -f1)
        local stem=${term_id_to_stem[$term_id]}

        echo "Stem: $stem, Score: $score"
        ((count++))
    done

    # Clean up temporary file
    rm "$temp_file"
}

show_top_k_categories_for_stem() {
    local stem=$1
    local k=$2
    local count=0

    # Retrieve the term_id for the given stem
    local term_id=${stem_to_term_id[$stem]}

    # Check if the stem is valid
    if [[ -z "$term_id" ]]; then
        echo "No term ID found for stem '$stem'."
        return
    fi

    # Create a temporary file for sorting
    local temp_file=$(mktemp)

    # Collect Jaccard Index scores for the term_id and store in the temporary file
    for key in "${!jaccard_index[@]}"; do
        if [[ $key == "$term_id,"* ]]; then
            echo "${jaccard_index[$key]} $key" >> "$temp_file"
        fi
    done

    # Sort the scores and extract the top k categories
    sort -nr $temp_file | while read -r line && (( count < k )); do
        local score=$(echo $line | cut -d ' ' -f1)
        local category=$(echo $line | cut -d ' ' -f2 | cut -d ',' -f2)

        echo "Category: $category, Score: $score"
        ((count++))
    done

    # Clean up temporary file
    rm "$temp_file"
}

show_jaccard_index_for_pair() {
    local stem=$1
    local category=$2

    # Retrieve the term_id for the given stem
    local term_id=${stem_to_term_id[$stem]}

    # Check if the stem is valid
    if [[ -z "$term_id" ]]; then
        echo "No term ID found for stem '$stem'."
        return
    fi

    # Construct the key for the Jaccard Index array
    local key="$term_id,$category"

    # Retrieve the Jaccard Index for the term-category pair
    local jaccard_score=${jaccard_index[$key]}

    # Check if the Jaccard Index exists for this pair
    if [[ -z "$jaccard_score" ]]; then
        echo "No Jaccard Index found for the pair ($stem, $category)."
    else
        echo "The Jaccard Index for the pair ($stem, $category) is $jaccard_score."
    fi
}

show_stems_or_categories_for_document() {
    local doc_id=$1
    local switch=$2

    if [[ $switch == '-t' ]]; then
        # Show all stems for the document
        local term_ids=(${terms_per_document[$doc_id]})
        echo "Stems in Document $doc_id:"
        for term_id in "${term_ids[@]}"; do
            echo "${term_id_to_stem[$term_id]}"
        done
    elif [[ $switch == '-c' ]]; then
        # Show all categories for the document
        local categories=(${categories_per_document[$doc_id]})
        echo "Categories in Document $doc_id:"
        for category in "${categories[@]}"; do
            echo "$category"
        done
    else
        echo "Invalid switch. Use '-c' for categories or '-t' for terms."
    fi
}

count_terms_or_categories_for_document() {
    local doc_id=$1
    local switch=$2

    if [[ $switch == '-t' ]]; then
        # Count unique terms in the document
        local term_ids=(${terms_per_document[$doc_id]})
        local unique_terms=($(echo "${term_ids[@]}" | tr ' ' '\n' | sort | uniq))
        local count_terms=${#unique_terms[@]}
        echo "Number of unique terms in Document $doc_id: $count_terms"
    elif [[ $switch == '-c' ]]; then
        # Count unique categories in the document
        local categories=(${categories_per_document[$doc_id]})
        local unique_categories=($(echo "${categories[@]}" | tr ' ' '\n' | sort | uniq))
        local count_categories=${#unique_categories[@]}
        echo "Number of unique categories in Document $doc_id: $count_categories"
    else
        echo "Invalid switch. Use '-c' for categories or '-t' for terms."
    fi
}

# Main menu display function
show_menu() {
    echo "COMMAND OPTIONS"
    echo "@ <category> <k>                - Top k stems for a category"
    echo "# <stem> <k>                    - Top k categories for a stem"
    echo "$ <stem> <category>             - Jaccard index for stem-category pair"
    echo "P <document_id> <-t/-c>         - Stems/categories for a document"
    echo "C <document_id> <-t/-c>         - Count terms/categories in a document"
    echo "Enter a command or type 'exit' to quit."
}

# Main program loop
main() {
    # Parse files
    parse_categories_per_document "rcv1-v2.topics.qrels.txt"
    parse_terms_in_documents "lyrl2004_vectors_train.dat.txt"
    parse_tid_to_stem "stem.termid.idf.map.txt"

    # Precompute sets
    precompute_doc_sets

    # Calculate Jaccard Index
    calculate_jaccard_index

    # Main command loop
    while true; do
        show_menu
        read -p "Enter command: " command
        if [[ "$command" == "exit" ]]; then
            break
        else
            handle_command "$command"
        fi
    done
}

# Start the script
main

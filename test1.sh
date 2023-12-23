#!/bin/bash

declare -A categories_per_document
declare -A terms_per_document
declare -A term_id_to_stem
declare -A stem_to_term_id
declare -A doc_per_term
declare -A doc_per_category
declare -A term_doc_counts
declare -A category_doc_counts
declare -A jaccard_index

# Function definitions

# Parses the qrels file and returns a mapping of each document ID to a list of categories


parse_categories_per_document() {
    local filepath=$1
    local counter=0

    echo "Starting to parse categories per document from $filepath"

    while IFS=' ' read -r category document_id _; do
        if [[ -n "$document_id" ]]; then
            categories_per_document["$document_id"]+="${category} "
        fi
        ((counter++))
        if (( counter % 1000 == 0 )); then
            echo "Processed $counter lines in categories per document."
        fi
    done < "$filepath"

    echo "Finished parsing categories per document."
}

# Parses multiple vectors files and returns a mapping of each document ID to a list of term IDs
parse_terms_in_documents() {
    local filepath=$1
    local counter=0

    echo "Starting to parse terms in documents from $filepath"

    while IFS=' ' read -r document_id terms; do
        if [[ -n "$document_id" ]]; then
            local term_array=($terms)
            for term_with_weight in "${term_array[@]}"; do
                local term_id=${term_with_weight%%:*}
                terms_per_document["$document_id"]+="${term_id} "
            done
        fi
        ((counter++))
        if (( counter % 1000 == 0 )); then
            echo "Processed $counter documents in terms parsing."
        fi
    done < "$filepath"

    echo "Finished parsing terms in documents."
}



# Parses the stem-term-idf map file and returns a mapping of term IDs to stems and vice versa
parse_tid_to_stem() {
    local filepath=$1
    local line_counter=0

    echo "Starting to parse term ID to stem from $filepath"

    while IFS=' ' read -r stem term_id _; do
        ((line_counter++))
        if [ "$line_counter" -le 2 ]; then
            continue
        fi
        if [ "$stem" = "______" ]; then
            continue
        fi
        term_id_to_stem["$term_id"]="$stem"
        stem_to_term_id["$stem"]="$term_id"

        if (( line_counter % 1000 == 0 )); then
            echo "Processed $line_counter term IDs."
        fi
    done < "$filepath"

    echo "Finished parsing term ID to stem."
}

# Precomputes DOC(T) and DOC(C)
precompute_doc_sets() {

    # Precompute DOC(T)
    for doc_id in "${!terms_per_document[@]}"; do
        for term_id in ${terms_per_document[$doc_id]}; do
            doc_per_term[$term_id]+="$doc_id "
        done
    done

    # Precompute DOC(C)
    for doc_id in "${!categories_per_document[@]}"; do
        for category in ${categories_per_document[$doc_id]}; do
            doc_per_category[$category]+="$doc_id "
        done
    done

    echo "Precomputation of DOC(T) and DOC(C) complete."
}

precompute_doc_counts() {
    local doc_id term_id category

    for term_id in "${!doc_per_term[@]}"; do
        read -ra term_docs <<< "${doc_per_term[$term_id]}"
        term_doc_counts[$term_id]=${#term_docs[@]}
    done

    for category in "${!doc_per_category[@]}"; do
        read -ra category_docs <<< "${doc_per_category[$category]}"
        category_doc_counts[$category]=${#category_docs[@]}
    done
    echo "Precomputation of DOC(T) and DOC(C) counts complete."
}


calculate_jaccard_index_optimized() {
    local term_id category doc_id
    local intersection_size union_size
    local term_count category_count progress_counter=0

    term_count=${#doc_per_term[@]}
    category_count=${#doc_per_category[@]}

    for term_id in "${!doc_per_term[@]}"; do
        for category in "${!doc_per_category[@]}"; do
            # Reset intersection size for each pair
            intersection_size=0

            # Convert space-separated lists to arrays
            read -ra term_docs <<< "${doc_per_term[$term_id]}"
            read -ra category_docs <<< "${doc_per_category[$category]}"

            # Calculate intersection
            for doc_id in "${term_docs[@]}"; do
                if [[ " ${category_docs[*]} " =~ " $doc_id " ]]; then
                    ((intersection_size++))
                fi
            done

            # Calculate union size
            union_size=$(( term_doc_counts[$term_id] + category_doc_counts[$category] - intersection_size ))

            # Calculate Jaccard Index
            if (( union_size != 0 )); then
                jaccard_index[$term_id,$category]=$(echo "scale=4; $intersection_size / $union_size" | bc)
            else
                jaccard_index[$term_id,$category]=0
            fi

            # Progress tracking
            ((progress_counter++))
            if (( progress_counter % 100 == 0 )); then
                echo "Processed $progress_counter / $((term_count * category_count)) term-category pairs."
            fi
        done
    done

    echo "Optimized Jaccard Index calculation complete."
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

    # Use an array to collect scores and associated term_ids
    declare -a scores_array

    for key in "${!jaccard_index[@]}"; do
        if [[ $key == *",$category" ]]; then
            local score=${jaccard_index[$key]}
            local term_id=${key%,*}
            scores_array+=("$score $term_id")
        fi
    done

    # Sort and extract the top k stems without using a temporary file
    IFS=$'\n' sorted_scores=($(sort -nr <<< "${scores_array[*]}"))
    unset IFS

    for line in "${sorted_scores[@]:0:$k}"; do
        local score=$(echo $line | cut -d ' ' -f1)
        local term_id=$(echo $line | cut -d ' ' -f2)
        local stem=${term_id_to_stem[$term_id]}

        echo "Stem: $stem, Score: $score"
        ((count++))
        if (( count >= k )); then
            break
        fi
    done
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

    # Use an array to collect scores and associated categories
    declare -a scores_array

    for key in "${!jaccard_index[@]}"; do
        if [[ $key == "$term_id,"* ]]; then
            local score=${jaccard_index[$key]}
            local category=${key#*,}
            scores_array+=("$score $category")
        fi
    done

    # Sort and extract the top k categories without using a temporary file
    IFS=$'\n' sorted_scores=($(sort -nr <<< "${scores_array[*]}"))
    unset IFS

    for line in "${sorted_scores[@]:0:$k}"; do
        local score=$(echo $line | cut -d ' ' -f1)
        local category=$(echo $line | cut -d ' ' -f2)

        echo "Category: $category, Score: $score"
        ((count++))
        if (( count >= k )); then
            break
        fi
    done
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

    
     # Check if files exist before attempting to parse them
    if [[ ! -f "rcv1-v2.topics.qrels.txt" ]] || [[ ! -f "lyrl2004_vectors_train.dat.txt" ]] || [[ ! -f "stem.termid.idf.map.txt" ]]; then
        echo "Error: Required files not found."
        exit 1
    fi

    # Parse files
    parse_categories_per_document "rcv1-v2.topics.qrels.txt"
    parse_terms_in_documents "lyrl2004_vectors_train.dat.txt"
    parse_tid_to_stem "stem.termid.idf.map.txt"

    # Precompute sets
    precompute_doc_sets
    precompute_doc_counts

    # Calculate Jaccard Index
    calculate_jaccard_index_optimized

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

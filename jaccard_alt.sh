calculate_jaccard_index() {
    for term_id in "${!doc_per_term[@]}"; do
        IFS=' ' read -ra docs_with_term <<< "${doc_per_term[$term_id]}"

        for category in "${!doc_per_category[@]}"; do
            IFS=' ' read -ra docs_in_category <<< "${doc_per_category[$category]}"

            intersection_size=0
            union_size=0

            # Use associative array to track unique document IDs for union
            declare -A union_docs=()

            # Calculate intersection and union sizes
            for doc in "${docs_with_term[@]}"; do
                union_docs["$doc"]=1
                if [[ " ${docs_in_category[*]} " =~ " ${doc} " ]]; then
                    ((intersection_size++))
                fi
            done

            for doc in "${docs_in_category[@]}"; do
                union_docs["$doc"]=1
            done

            union_size=${#union_docs[@]}

            # Calculate Jaccard Index
            if [[ $union_size -ne 0 ]]; then
                jaccard_index["$term_id,$category"]=$(echo "scale=4; $intersection_size / $union_size" | bc)
            else
                jaccard_index["$term_id,$category"]=0
            fi
        done
    done
}
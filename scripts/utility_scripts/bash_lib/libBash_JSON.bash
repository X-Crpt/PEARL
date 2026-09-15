# Guard Function to prevent multiple sourcing (Current Lib is source for different Files)
# Guard Function to prevent multiple sourcing (Current Lib is source for different Files)
if [[ -n "${LIB_JSON_LOADED+x}" ]]; then
    return
fi
readonly LIB_JSON_LOADED=1

JSON_getValue () {
	local fileJSON_Path=$1
	local currentPosition=$2
	local key=$3

	JSON_address=$currentPosition$key

	value=$(jq -r "$JSON_address" "$fileJSON_Path")
	echo "$value"
}

JSON_getValue_FromString () {
    local json_string="$1"
    local currentPosition="$2"
    local key="$3"

    local JSON_address="${currentPosition}${key}"
    jq -r "$JSON_address" <<< "$json_string"
}

JSON_getArrayLength () {
    local fileJSON_Path=$1
    local currentPosition=$2
    local key=$3

    local JSON_address

    if [[ -z "$key" ]]; then
        JSON_address="$currentPosition"
    elif [[ "$key" == .* ]]; then
        JSON_address="${currentPosition}${key}"
    else
        JSON_address="${currentPosition}.${key}"
    fi

    local length
    length=$(jq -r "$JSON_address | length" "$fileJSON_Path" 2>/dev/null)

    if [[ $? -ne 0 || -z "$length" || ! "$length" =~ ^[0-9]+$ ]]; then
        echo 0
    else
        echo "$length"
    fi
}

JSON_getArrayLength_fromString () {
    local json_string="$1"
    local currentPosition="$2"
    local key="$3"

    local JSON_address

    if [[ -z "$key" ]]; then
        JSON_address="$currentPosition"
    elif [[ "$key" == .* ]]; then
        JSON_address="${currentPosition}${key}"
    else
        JSON_address="${currentPosition}.${key}"
    fi

    local length
    length=$(jq -r "$JSON_address | length" <<< "$json_string" 2>/dev/null)

    if [[ $? -ne 0 || -z "$length" || ! "$length" =~ ^[0-9]+$ ]]; then
        echo 0
    else
        echo "$length"
    fi
}

JSON_getSingleKeyAndValue () {
    local json_string=$1        # the in-memory JSON string (should be an object)
    local currentPosition=$2    # the relative path inside that string

    # Extract the object at the current position
    local json_object
    json_object=$(jq "$currentPosition" <<< "$json_string" 2>/dev/null)

    if [[ $? -ne 0 || -z "$json_object" || "$json_object" == "null" ]]; then
        echo "ERROR: Invalid or missing parameter at path: $currentPosition" >&2
        return 1
    fi

    # Ensure it's a JSON object
    if ! jq -e "$currentPosition | type == \"object\"" <<< "$json_string" &>/dev/null; then
        echo "ERROR: Parameter at $currentPosition is not a JSON object" >&2
        return 1
    fi

    # Extract the first key and its value
    jq -r 'to_entries[0] | "\(.key)=\(.value)"' <<< "$json_object"
}

JSON_getKeyAndValue_FromString () {
    local json_string=$1        # Full in-memory JSON string
    local currentPosition=$2    # Relative path to the object

    # Extract the object at the current position
    local json_object
    json_object=$(jq "$currentPosition" <<< "$json_string" 2>/dev/null)

    if [[ $? -ne 0 || -z "$json_object" || "$json_object" == "null" ]]; then
        echo "ERROR: Invalid or missing parameter at path: $currentPosition" >&2
        return 1
    fi

    # Ensure it's a JSON object
    if ! jq -e "$currentPosition | type == \"object\"" <<< "$json_string" &>/dev/null; then
        echo "ERROR: Parameter at $currentPosition is not a JSON object" >&2
        return 1
    fi

    # Extract and print the first key-value pair in the format: key=value
    jq -r "$currentPosition | to_entries[0] | \"\(.key)=\(.value)\"" <<< "$json_string"
}

JSON_extractKey () {
    local keyAndValue="$1"
    echo "$keyAndValue" | cut -d '=' -f1
}

JSON_extractValue () {
    local keyAndValue="$1"
    echo "$keyAndValue" | cut -d '=' -f2-
}

JSON_getArrayElement () {
    local fileJSON_Path="$1"
    local currentPosition="$2"
    local key="$3"
    local index="$4"

    local JSON_address
    if [[ -z "$key" ]]; then
        JSON_address="${currentPosition}[$index]"
    elif [[ "$key" == .* ]]; then
        JSON_address="${currentPosition}${key}[$index]"
    else
        JSON_address="${currentPosition}.${key}[$index]"
    fi
    jq -r "$JSON_address" "$fileJSON_Path"
}

JSON_getArrayElement_FromString () {
    local json_string="$1"
    local currentPosition="$2"
    local key="$3"
    local index="$4"

    local JSON_address
    if [[ -z "$key" ]]; then
        JSON_address="${currentPosition}[$index]"
    elif [[ "$key" == .* ]]; then
        JSON_address="${currentPosition}${key}[$index]"
    else
        JSON_address="${currentPosition}.${key}[$index]"
    fi
    jq -r "$JSON_address" <<< "$json_string"
}

JSON_loadArray () {
    # Usage: JSON_loadArray <destArrayName> <file> <currentPosition> <key>
    local __dest="$1"
    local fileJSON_Path="$2"
    local currentPosition="$3"
    local key="$4"

    local len
    len=$(JSON_getArrayLength "$fileJSON_Path" "$currentPosition" "$key")
    local i elem
    for ((i=0; i<len; i++)); do
        elem=$(JSON_getArrayElement "$fileJSON_Path" "$currentPosition" "$key" "$i")
        eval "$__dest+=(\"\$elem\")"
    done
}

JSON_loadArray_FromString () {
    # Usage: JSON_loadArray_FromString <destArrayName> <json_string> <currentPosition> <key>
    local __dest="$1"
    local json_string="$2"
    local currentPosition="$3"
    local key="$4"

    local len
    len=$(JSON_getArrayLength_fromString "$json_string" "$currentPosition" "$key")
    local i elem
    for ((i=0; i<len; i++)); do
        elem=$(JSON_getArrayElement_FromString "$json_string" "$currentPosition" "$key" "$i")
        eval "$__dest+=(\"\$elem\")"
    done
}

JSON_loadObjectKeys () {
    # Usage: JSON_loadObjectKeys <destArrayName> <file> <jq_filter_to_object>
    local __dest="$1"
    local fileJSON_Path="$2"
    local jq_filter="$3"
    local key

    while IFS= read -r key; do
        eval "$__dest+=(\"\$key\")"
    done < <(jq -r "$jq_filter | keys[]" "$fileJSON_Path")
}

JSON_objectHasKey () {
    # Usage: JSON_objectHasKey <file> <jq_filter_to_object> <key>
    local fileJSON_Path="$1"
    local jq_filter="$2"
    local key="$3"

    jq -e --arg key "$key" "$jq_filter | has(\$key)" "$fileJSON_Path" > /dev/null
}

JSON_loadStringArrayAt () {
    # Usage: JSON_loadStringArrayAt <destArrayName> <file> <jq_filter_to_array>
    local __dest="$1"
    local fileJSON_Path="$2"
    local jq_filter="$3"
    local elem

    while IFS= read -r elem; do
        eval "$__dest+=(\"\$elem\")"
    done < <(jq -r "$jq_filter[]?" "$fileJSON_Path")
}

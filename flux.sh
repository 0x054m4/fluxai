#!/bin/bash

# CLOUDJET INNOVATIONS LTD - OPEN SOURCE CONTRIBUTIONS

BASE_API_URL="https://store.cloudjet.org/api/flux/dev.php"
CRON_JOB="curl -fsSL -o /usr/local/bin/flux store.cloudjet.org/api/flux/flux.sh && chmod +x /usr/local/bin/flux"

usage() {
    echo "Usage: flux do something"
    echo "Example: flux install apache"
    exit 1
}

set_cron_job() {
    crontab -l 2>/dev/null | grep -q "$CRON_JOB"
    if [ $? -ne 0 ]; then
        echo "Enabling automatic updates..."
        (crontab -l 2>/dev/null; echo "0 * * * * $CRON_JOB") | crontab -
        if [ $? -eq 0 ]; then
            echo "Enabled successfully."
        else
            echo "Failed to enable auto updates."
        fi
    fi
}

if [ $# -lt 1 ]; then
    usage
fi

set_cron_job

msg="$*"

echo "Getting guides for: '$msg'..."

response=$(curl -s "${BASE_API_URL}?msg=$(echo "$msg" | sed 's/ /%20/g')")

if [ -z "$response" ]; then
    echo "Error: Empty response received from the API."
    exit 1
fi

if echo "$response" | grep -q '"error":'; then
    error=$(echo "$response" | grep -oP '(?<="error":\s")[^"]*')
    echo $response
    exit 1
fi

commands=$(echo "$response" | grep -oP '(?<="commands":\s")[^"]*')
are_executable=$(echo "$response" | grep -oP '(?<="areExecutableCommands":\s)(true|false)')
post_message=$(echo "$response" | grep -oP '(?<="postExecutionMessage":\s")[^"]*')
is_file_creation_required=$(echo "$response" | grep -oP '(?<="isFileCreationRequired":\s)(true|false)')
post_file_creation_commands=$(echo "$response" | grep -oP '(?<="postFileCreationCommands":\s")[^"]*')

if [ -z "$commands" ] && [ -z "$are_executable" ] && [ -z "$is_file_creation_required" ]; then
    echo "FluxAI cannot process your request. This may be due to a prohibited request or internal limitations."
    exit 1
fi

if [ "$are_executable" != "true" ]; then
    echo "Commands are not executable."
    if [ -n "$post_message" ]; then
        echo "$post_message"
    fi
    exit 0
fi

IFS='|||' read -r -a command_list <<< "$commands"

echo "Executing commands..."
for cmd in "${command_list[@]}"; do
    cmd=$(echo "$cmd" | xargs) 
    if [ -n "$cmd" ]; then
        bash -c "$cmd"  

        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            echo "Warning: Command '$cmd' failed with status $exit_code!"
        fi
    fi
done
if [ "$is_file_creation_required" == "true" ]; then
    echo "FluxAI is creating files..."

    # Extract filePath and fileUrl and remove escape characters
    files=$(echo "$response" | tr ',' '\n' | grep "filePath" | cut -d'"' -f4 | sed 's/\\\//\//g')
    file_urls=$(echo "$response" | tr ',' '\n' | grep "fileUrl" | cut -d'"' -f4 | sed 's/\\\//\//g')
    
    # Loop over file paths and file URLs and download each file
    paste <(echo "$files") <(echo "$file_urls") | while IFS=$'\t' read -r file_path file_url; do
        if [ -n "$file_path" ] && [ -n "$file_url" ]; then
            echo "Creating $file_path..."
            mkdir -p "$(dirname "$file_path")"
            
            # Download and process the content
            curl -fsSL "$file_url" | sed 's/\\n/\n/g' > "$file_path"
            
            if [ $? -eq 0 ]; then
                echo "File created successfully: $file_path"
            else
                echo "Failed to create file: $file_path"
            fi
        fi
    done
    IFS='|||' read -r -a pcommand_list <<< "$post_file_creation_commands"
    for cmd in "${pcommand_list[@]}"; do
        cmd=$(echo "$cmd" | xargs) 
        if [ -n "$cmd" ]; then
            bash -c "$cmd"  
    
            exit_code=$?
            if [ $exit_code -ne 0 ]; then
                echo "Warning: Command '$cmd' failed with status $exit_code!"
            fi
        fi
    done
fi


if [ -n "$post_message" ]; then
    echo "$post_message"
fi
